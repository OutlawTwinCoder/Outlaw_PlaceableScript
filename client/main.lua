local Config = Config
local Locale = Locale
local Utils = Utils

local Placement = {
    active = false,
    item = nil,
    metadata = nil,
    model = nil,
    entity = nil,
    rotation = 0.0,
    distance = Config.Distance.max / 2.0,
    dropMode = 'place',
    isValid = false,
    reason = nil,
    position = nil,
    surfaceNormal = nil,
    surfaceEntity = nil,
    trunkInfo = nil,
    vehicleNetId = nil
}

local trackedObjects = {}
local trackedByEntity = {}
local placementThread
local trackingThread
local requestCounter = 0
local pendingRequests = {}
local trunkStates = {}

local function notify(key, default, type)
    local text
    if key and key:find('%.') then
        text = Locale.t(key, default)
    else
        text = Locale.t('notify.' .. (key or ''), default)
    end
    if lib and lib.notify then
        lib.notify({ title = 'Placeable', description = text, type = type or 'inform' })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function drawHelp()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(Locale.t('controls'))
    EndTextCommandDisplayHelp(0, false, true, 1)
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function getRayData(distance)
    local ped = PlayerPedId()
    if Config.Preview.mode == 'ped' then
        local from = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        local to = GetOffsetFromEntityInWorldCoords(ped, 0.0, distance, 0.0)
        return from, to
    else
        local camCoord = GetGameplayCamCoord()
        local camRot = GetGameplayCamRot(2)
        local dir = rotationToDirection(camRot)
        local to = camCoord + dir * distance
        return camCoord, to
    end
end

local function performRaycast(distance)
    local from, to = getRayData(distance)
    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, PlayerPedId(), 7)
    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
    return hit == 1, vector3(endCoords.x, endCoords.y, endCoords.z), vector3(surfaceNormal.x, surfaceNormal.y, surfaceNormal.z), entityHit
end

local function requestModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelValid(model) then return nil end
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(0)
        end
    end
    return model
end

local function destroyPreview()
    if Placement.entity and DoesEntityExist(Placement.entity) then
        DeleteEntity(Placement.entity)
    end
    Placement.entity = nil
end

local function ensurePreviewEntity()
    if Placement.entity and DoesEntityExist(Placement.entity) then return end
    if not Placement.model then return end
    local entity = CreateObject(Placement.model, 0.0, 0.0, 0.0, false, false, false)
    SetEntityCollision(entity, false, false)
    SetEntityAlpha(entity, 150, false)
    SetEntityCompletelyDisableCollision(entity, false, false)
    SetEntityInvincible(entity, true)
    FreezeEntityPosition(entity, true)
    Placement.entity = entity
end

local function updatePreviewColor(valid)
    if not Placement.entity or not DoesEntityExist(Placement.entity) then return end
    local color = valid and 200 or 60
    SetEntityAlpha(Placement.entity, color, false)
end

local function getItemConfig(item)
    if not item then return nil end
    return Config.Placeables[item]
end

local function getPlacementModel(item)
    local info = getItemConfig(item)
    if info and info.model then
        return info.model
    end
    if Config.MakeEverythingPlaceable.enabled then
        return Config.MakeEverythingPlaceable.fallbackModel
    end
    return nil
end

local function calculatePlacementPosition(hitCoords, normal, modelMin, modelMax)
    local height = math.abs(modelMin.z)
    local offset = vector3(0.0, 0.0, height)
    if normal then
        local align = vector3(normal.x, normal.y, 0.0)
        if #(align) > 0.001 then
            local heading = math.deg(math.atan2(align.y, align.x)) - 90.0
            Placement.rotation = heading
        end
    end
    return hitCoords + vector3(0.0, 0.0, math.abs(modelMin.z))
end

local function requestTrunkState(netId, dims)
    if not netId or netId == 0 then return nil end
    if dims and trunkStates[netId] and trunkStates[netId].hash == dims.hash then
        return trunkStates[netId]
    end
    requestCounter = requestCounter + 1
    local id = requestCounter
    local p = promise.new()
    pendingRequests[id] = p
    TriggerServerEvent('outlaw_placeables:requestTrunkState', netId, id, dims)
    local result = Citizen.Await(p)
    return result
end

local function buildTrunkPreview(vehicle, hitCoords, modelMin, modelMax)
    if not Config.Trunk.enabled then return nil, nil end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then return nil, nil end
    local dims = {
        x = math.abs(modelMax.x - modelMin.x),
        y = math.abs(modelMax.y - modelMin.y),
        z = math.abs(modelMax.z - modelMin.z)
    }
    dims.hash = string.format('%.2f:%.2f:%.2f', dims.x, dims.y, dims.z)
    local state = requestTrunkState(netId, dims)
    Placement.vehicleNetId = netId
    if not state then return nil, nil end
    local cell = state.nextCell
    if not cell then
        Placement.reason = 'trunk_full'
        return nil, nil
    end
    local pos = vector3(cell.x, cell.y, cell.z)
    return pos, vector3(0.0, 0.0, cell.w)
end

local function validatePlacement(coords)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    if #(coords - pedCoords) > Config.Distance.max + 0.5 then
        Placement.reason = 'out_of_range'
        return false
    end
    if #(coords - pedCoords) < Config.Distance.minFromPed then
        Placement.reason = 'too_close'
        return false
    end
    if Config.AntiStacking.enabled and not Placement.vehicleNetId then
        for _, data in pairs(trackedObjects) do
            if data.coords and #(coords - data.coords) < Config.AntiStacking.minSeparation then
                Placement.reason = 'stacking_blocked'
                return false
            end
        end
    end
    return true
end

local function updatePlacement()
    if not Placement.active or not Placement.model then return end
    ensurePreviewEntity()
    if not Placement.entity then return end
    drawHelp()

    local hit, hitCoords, normal, entityHit = performRaycast(Placement.distance)
    if not hit then
        Placement.isValid = false
        Placement.reason = 'invalid_surface'
        updatePreviewColor(false)
        return
    end

    Placement.surfaceEntity = entityHit
    Placement.surfaceNormal = normal

    local min, max = GetModelDimensions(Placement.model)
    local coords
    local rotation = vector3(0.0, 0.0, Placement.rotation)

    if entityHit and IsEntityAVehicle(entityHit) and Config.Trunk.enabled then
        coords, rotation = buildTrunkPreview(entityHit, hitCoords, min, max)
        if not coords then
            Placement.isValid = false
            updatePreviewColor(false)
            return
        end
        Placement.rotation = rotation.z
    else
        coords = calculatePlacementPosition(hitCoords, normal, min, max)
        Placement.vehicleNetId = nil
    end

    Placement.position = coords
    SetEntityCoordsNoOffset(Placement.entity, coords.x, coords.y, coords.z)
    SetEntityRotation(Placement.entity, rotation.x, rotation.y, rotation.z, 2, true)

    Placement.isValid = validatePlacement(coords)
    Placement.reason = Placement.isValid and nil or Placement.reason
    updatePreviewColor(Placement.isValid)
end

local function finishPlacement(confirm)
    if not Placement.active then return end
    if confirm and Placement.isValid and Placement.position then
        local payload = {
            item = Placement.item,
            metadata = Placement.metadata,
            model = Placement.model,
            coords = { x = Placement.position.x, y = Placement.position.y, z = Placement.position.z },
            rotation = Placement.surfaceEntity and { x = 0.0, y = 0.0, z = Placement.rotation } or { x = 0.0, y = 0.0, z = Placement.rotation },
            mode = Placement.dropMode,
            vehicleNetId = Placement.vehicleNetId
        }
        TriggerServerEvent('outlaw_placeables:confirmPlacement', payload)
    elseif not confirm and Placement.reason then
        notify(Placement.reason, Placement.reason, 'error')
    end
    destroyPreview()
    Placement = {
        active = false,
        item = nil,
        metadata = nil,
        model = nil,
        entity = nil,
        rotation = 0.0,
        distance = Config.Distance.max / 2.0,
        dropMode = 'place',
        isValid = false,
        reason = nil,
        position = nil,
        surfaceNormal = nil,
        surfaceEntity = nil,
        trunkInfo = nil,
        vehicleNetId = nil
    }
end

local function toggleDropMode()
    if Placement.dropMode == 'place' then
        Placement.dropMode = 'drop'
    elseif Placement.dropMode == 'drop' then
        Placement.dropMode = 'throw'
    else
        Placement.dropMode = 'place'
    end
end

local function startPlacementThread()
    if placementThread then return end
    placementThread = CreateThread(function()
        while Placement.active do
            updatePlacement()
            if Placement.active then
                local controls = Config.Controls
                DisableControlAction(0, controls.confirm, true)
                DisableControlAction(0, controls.cancel, true)
                DisableControlAction(0, controls.distanceIncrease, true)
                DisableControlAction(0, controls.distanceDecrease, true)
                DisableControlAction(0, controls.rotateLeft, true)
                DisableControlAction(0, controls.rotateRight, true)
                DisableControlAction(0, controls.snap, true)
                DisableControlAction(0, controls.toggleDrop, true)

                if IsDisabledControlJustPressed(0, controls.distanceIncrease) then
                    Placement.distance = math.min(Config.Distance.max, Placement.distance + Config.Preview.scrollStep)
                elseif IsDisabledControlJustPressed(0, controls.distanceDecrease) then
                    Placement.distance = math.max(Config.Distance.min, Placement.distance - Config.Preview.scrollStep)
                end

                if IsDisabledControlJustPressed(0, controls.rotateLeft) then
                    Placement.rotation = Placement.rotation - Config.Preview.rotateStep
                elseif IsDisabledControlJustPressed(0, controls.rotateRight) then
                    Placement.rotation = Placement.rotation + Config.Preview.rotateStep
                end

                if IsDisabledControlJustPressed(0, controls.snap) then
                    Placement.rotation = Utils.round(Placement.rotation / Config.Preview.snapAngle, 0) * Config.Preview.snapAngle
                end

                if IsDisabledControlJustPressed(0, controls.toggleDrop) then
                    toggleDropMode()
                end

                if IsDisabledControlJustPressed(0, controls.confirm) then
                    finishPlacement(true)
                elseif IsDisabledControlJustPressed(0, controls.cancel) then
                    finishPlacement(false)
                end
            end
            Wait(0)
        end
        placementThread = nil
    end)
end

function StartPlacement(item, metadata)
    if Placement.active then
        notify('rate_limited', 'Already placing an item', 'error')
        return
    end

    local model = getPlacementModel(item)
    if not model then
        notify('invalid_surface', 'No model available', 'error')
        return
    end

    model = requestModel(model)
    if not model then
        notify('invalid_surface', 'Model unavailable', 'error')
        return
    end

    Placement.active = true
    Placement.item = item
    Placement.metadata = metadata
    Placement.model = model
    Placement.rotation = 0.0
    Placement.distance = Config.Distance.max / 2.0
    Placement.dropMode = 'place'
    ensurePreviewEntity()
    startPlacementThread()
end

exports('StartPlacement', StartPlacement)

local function cancelPlacement()
    finishPlacement(false)
end

RegisterCommand(Config.Commands.cancel, cancelPlacement, false)

RegisterNetEvent('outlaw_placeables:startPlacement', function(item, metadata)
    StartPlacement(item, metadata)
end)

RegisterNetEvent('outlaw_placeables:cancelPlacement', function()
    cancelPlacement()
end)

local function trackObject(data)
    if not data or not data.netId then return end
    trackedObjects[data.netId] = data
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity and entity ~= 0 then
        trackedByEntity[entity] = data.netId
    end
    if data.isTrunk and data.vehicleNetId then
        trunkStates[data.vehicleNetId] = nil
    end
end

RegisterNetEvent('outlaw_placeables:objectSpawned', function(data)
    trackObject(data)
end)

RegisterNetEvent('outlaw_placeables:objectRemoved', function(netId)
    local data = trackedObjects[netId]
    if data then
        if data.isTrunk and data.vehicleNetId then
            trunkStates[data.vehicleNetId] = nil
        end
        trackedObjects[netId] = nil
    end
end)

RegisterNetEvent('outlaw_placeables:receiveTrunkState', function(netId, requestId, state)
    trunkStates[netId] = state
    if requestId and pendingRequests[requestId] then
        pendingRequests[requestId]:resolve(state)
        pendingRequests[requestId] = nil
    end
end)

local function applySettling(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end
    SetEntityCollision(entity, true, true)
    FreezeEntityPosition(entity, false)
    local start = GetGameTimer()
    while GetGameTimer() - start < 4000 do
        local vx, vy, vz = table.unpack(GetEntityVelocity(entity))
        local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
        if speed < 0.02 then
            break
        end
        Wait(50)
    end
    if Config.FreezePlacedObjects then
        FreezeEntityPosition(entity, true)
    end
end

RegisterNetEvent('outlaw_placeables:settleObject', function(netId)
    CreateThread(function()
        applySettling(netId)
    end)
end)

local function addTargetOptions(netId)
    if not exports or not exports.ox_target then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end
    exports.ox_target:addLocalEntity(entity, {
        {
            icon = 'fa-solid fa-box-open',
            label = Locale.t('target.pickup'),
            distance = Config.Target.pickupDistance,
            onSelect = function()
                TriggerServerEvent('outlaw_placeables:pickup', netId)
            end
        },
        {
            icon = 'fa-solid fa-eye',
            label = Locale.t('target.inspect'),
            distance = Config.Target.inspectDistance,
            onSelect = function()
                TriggerServerEvent('outlaw_placeables:inspect', netId)
            end
        },
        {
            icon = 'fa-solid fa-ban',
            label = Locale.t('target.remove'),
            distance = Config.Target.inspectDistance,
            onSelect = function()
                TriggerServerEvent('outlaw_placeables:remove', netId)
            end
        }
    })
end

RegisterNetEvent('outlaw_placeables:registerTarget', function(netId)
    addTargetOptions(netId)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    destroyPreview()
end)

RegisterCommand(Config.Commands.place, function(_, args)
    local item = args[1]
    if not item then
        local message = string.format(Locale.t('commands.usage_place', '/%s <itemName>'), Config.Commands.place)
        notify(nil, message, 'error')
        return
    end
    TriggerServerEvent('outlaw_placeables:commandPlace', item)
end, false)

RegisterNetEvent('outlaw_placeables:notify', function(key, fallback, type)
    notify(key, fallback, type)
end)

RegisterNetEvent('outlaw_placeables:testSpawn', function(data)
    trackObject(data)
end)

RegisterKeyMapping(Config.Commands.place, 'Start placing an item', 'keyboard', 'F6')
RegisterKeyMapping(Config.Commands.cancel, 'Cancel placement preview', 'keyboard', 'BACK')
