local controls = Config.Controls or {}
local previewConfig = Config.Preview or {}
local distances = Config.Distances or {}
local antiStack = Config.AntiStacking or {}
local trunkConfig = Config.Trunk or {}
local freezePlaced = Config.FreezePlacedObjects ~= false

local placements = {}
local placementByNet = {}
local currentPreview
local previewThread
local promptThread
local lib = rawget(_G, 'lib')
local targetResource = Config.Target and Config.Target.resource or 'ox_target'
local targetEnabled = Config.Target and Config.Target.enabled and Inventory.supportsTarget()

---------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------
local function notify(message, type)
    if lib and lib.notify then
        lib.notify({ title = Locale.get('general.resource'), description = message, type = type or 'inform' })
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('outlaw_placeables:notify', function(message, type)
    notify(message, type)
end)

local function draw3DText(coords, text)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 210)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

local function deletePreviewEntity(preview)
    if preview and preview.entity and DoesEntityExist(preview.entity) then
        DeleteEntity(preview.entity)
    end
end

local function cleanPreview()
    if previewThread then
        previewThread = nil
    end

    if currentPreview then
        deletePreviewEntity(currentPreview)
    end

    currentPreview = nil
end

local function getModelFromItem(itemName, meta)
    local itemConfig = Config.Items and Config.Items[itemName]
    if itemConfig and itemConfig.models and #itemConfig.models > 0 then
        return itemConfig.models[math.random(#itemConfig.models)], itemConfig
    end

    if Config.MakeEverythingPlaceable and Config.MakeEverythingPlaceable.enabled then
        return Config.MakeEverythingPlaceable.fallbackModel, {
            allowDrop = true,
            allowTrunk = true,
            trunkSize = { x = 0.5, y = 0.5, z = 0.5 },
            interactDistance = 2.0
        }
    end

    return nil, itemConfig
end

local function ensureModelLoaded(model)
    if type(model) == 'string' then
        model = joaat(model)
    end

    if model == 0 or not IsModelValid(model) then
        return nil
    end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
    return model
end

local function setPreviewAlpha(entity, valid)
    if not entity or entity == 0 then return end
    local alpha = valid and (previewConfig.alphaValid or 180) or (previewConfig.alphaInvalid or 120)
    SetEntityAlpha(entity, alpha, false)
    SetEntityCollision(entity, false, false)
end

local function getCamDirection()
    local rot = GetGameplayCamRot(2)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosX = math.cos(rotX)
    return vector3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
end

local function createPreviewEntity(modelHash)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local entity = CreateObject(modelHash, coords.x, coords.y, coords.z + 0.5, false, false, false)

    SetEntityAlpha(entity, 0, false)
    SetEntityCompletelyDisableCollision(entity, true, true)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetEntityVisible(entity, true, false)

    return entity
end

local function transformPoint(matrix, offset)
    local right, forward, up, position = table.unpack(matrix)
    return vector3(
        position.x + right.x * offset.x + forward.x * offset.y + up.x * offset.z,
        position.y + right.y * offset.x + forward.y * offset.y + up.y * offset.z,
        position.z + right.z * offset.x + forward.z * offset.y + up.z * offset.z
    )
end

local function getEntityMatrix(entity)
    local rightX, rightY, rightZ, forwardX, forwardY, forwardZ, upX, upY, upZ, posX, posY, posZ = GetEntityMatrix(entity)
    local right = vector3(rightX, rightY, rightZ)
    local forward = vector3(forwardX, forwardY, forwardZ)
    local up = vector3(upX, upY, upZ)
    local position = vector3(posX, posY, posZ)
    return { right, forward, up, position }
end

local function getTrunkBoneCoords(vehicle)
    if not trunkConfig.attachBones then return nil end
    for _, name in ipairs(trunkConfig.attachBones) do
        local index = GetEntityBoneIndexByName(vehicle, name)
        if index ~= -1 then
            return GetWorldPositionOfEntityBone(vehicle, index)
        end
    end
    return nil
end

local function computeTrunkSlot(vehicle, preview)
    local itemConfig = preview.itemConfig or {}
    local size = itemConfig.trunkSize or { x = 0.5, y = 0.5, z = 0.5 }
    local minDims, maxDims = GetModelDimensions(GetEntityModel(vehicle))
    local width = maxDims.x - minDims.x
    local depth = maxDims.y - minDims.y
    local cols = math.max(1, math.floor(width / size.x))
    local rows = math.max(1, math.floor(depth / size.y))
    local class = GetVehicleClass(vehicle)
    local capacity = trunkConfig.classCapacity and trunkConfig.classCapacity[class] or trunkConfig.defaultCapacity or (cols * rows)
    local totalSlots = math.min(cols * rows, capacity)

    local matrix = getEntityMatrix(vehicle)
    local baseBone = getTrunkBoneCoords(vehicle)
    local baseOffset

    if baseBone then
        local vehPos = GetEntityCoords(vehicle)
        local right, forward, up, position = table.unpack(matrix)
        local diff = baseBone - position
        local offsetX = diff.x * right.x + diff.y * right.y + diff.z * right.z
        local offsetY = diff.x * forward.x + diff.y * forward.y + diff.z * forward.z
        local offsetZ = diff.x * up.x + diff.y * up.y + diff.z * up.z
        baseOffset = vector3(offsetX, offsetY, offsetZ)
    else
        baseOffset = vector3(0.0, minDims.y, minDims.z)
    end

    local taken = {}
    for _, placement in pairs(placements) do
        local trunk = placement.trunk
        if trunk and trunk.vehicle == NetworkGetNetworkIdFromEntity(vehicle) then
            taken[trunk.slot] = true
        end
    end

    local startX = -(math.min(cols, totalSlots) * size.x) / 2 + size.x / 2
    local slot = nil
    local slotOffset = nil

    local slotIndex = 0
    for row = 1, rows do
        for col = 1, cols do
            slotIndex = slotIndex + 1
            if slotIndex > totalSlots then break end
            if not taken[slotIndex] then
                slot = slotIndex
                slotOffset = vector3(startX + (col - 1) * size.x, baseOffset.y + size.y * (row - 0.5), baseOffset.z + size.z / 2)
                break
            end
        end
        if slot then break end
    end

    if not slot or not slotOffset then
        return nil, Locale.get('validation.trunk_full')
    end

    local target = transformPoint(matrix, slotOffset)
    local rotation = vector3(0.0, 0.0, GetEntityHeading(vehicle))

    preview.trunkData = {
        vehicle = NetworkGetNetworkIdFromEntity(vehicle),
        slot = slot,
        capacity = totalSlots,
        size = size
    }

    return target, rotation
end

local function isTooCloseToPlayer(coords)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local dist = #(coords - pedCoords)
    if distances.minFromPed and dist < distances.minFromPed then
        return true
    end
    return false
end

local function violatesStacking(coords)
    if not antiStack.enabled then return false end
    for _, placement in pairs(placements) do
        if placement.coords then
            local distXY = #(vector2(coords.x, coords.y) - vector2(placement.coords.x, placement.coords.y))
            local heightDiff = math.abs(coords.z - placement.coords.z)
            if distXY < (antiStack.minSeparation or 0.3) and heightDiff < (antiStack.heightTolerance or 0.5) then
                return true
            end
        end
    end
    return false
end

local function updatePreviewPlacement(preview)
    if not preview or not preview.entity then return end

    local ped = PlayerPedId()
    local camCoord = GetGameplayCamCoord()
    local camDir = getCamDirection()
    local distance = preview.distance
    local target = camCoord + camDir * distance

    local rayEnd = target
    local shape = StartShapeTestCapsule(camCoord.x, camCoord.y, camCoord.z, rayEnd.x, rayEnd.y, rayEnd.z, 0.3, 1 | 2 | 4 | 8, ped, 7)
    local _, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(shape)

    preview.hitCoords = hitCoords
    preview.hitNormal = surfaceNormal
    preview.hitEntity = entityHit
    preview.isTrunk = false
    preview.trunkData = nil

    if hit ~= 1 then
        preview.valid = false
        return
    end

    local coords = hitCoords
    local rotation = vector3(0.0, 0.0, preview.rotation)
    local surfaceType = 'world'

    if entityHit and entityHit ~= 0 then
        if IsEntityAVehicle(entityHit) and trunkConfig.enabled and (preview.itemConfig and preview.itemConfig.allowTrunk) then
            local targetCoords, rot = computeTrunkSlot(entityHit, preview)
            if not targetCoords then
                preview.valid = false
                notify(rot or Locale.get('validation.trunk_full'), 'error')
                return
            end
            coords = targetCoords
            rotation = rot
            surfaceType = 'trunk'
            preview.isTrunk = true
        else
            local normal = surfaceNormal
            local heading = math.deg(math.atan2(normal.x, normal.y))
            rotation = vector3(0.0, 0.0, heading + 180.0)
        end
    end

    local mins, maxs = GetModelDimensions(preview.model)
    local height = maxs.z - mins.z
    local offset = mins.z

    if not preview.isTrunk then
        coords = coords + vector3(0.0, 0.0, (height / 2.0) - offset)
    end

    if isTooCloseToPlayer(coords) then
        preview.valid = false
        preview.invalidReason = Locale.get('validation.too_close')
    elseif surfaceType == 'world' and violatesStacking(coords) then
        preview.valid = false
        preview.invalidReason = Locale.get('validation.stacking')
    else
        preview.valid = true
        preview.invalidReason = nil
    end

    SetEntityCoordsNoOffset(preview.entity, coords.x, coords.y, coords.z)
    SetEntityRotation(preview.entity, rotation.x, rotation.y, rotation.z, 2, true)
    setPreviewAlpha(preview.entity, preview.valid)
    preview.coords = coords
    preview.rotation = rotation
    preview.surfaceType = surfaceType
end

local function sendPlacement(preview)
    if not preview or not preview.valid then return end
    local coords = preview.coords
    local rotation = preview.rotation
    local dropMode = preview.dropMode and preview.itemConfig and (preview.itemConfig.allowDrop or preview.itemConfig.allowThrow)
    local throwVelocity
    if dropMode and preview.itemConfig and preview.itemConfig.allowThrow then
        local ped = PlayerPedId()
        local forward = GetEntityForwardVector(ped)
        local speed = GetEntitySpeed(ped) + 2.0
        throwVelocity = {
            x = forward.x * speed,
            y = forward.y * speed,
            z = forward.z * speed + 1.5
        }
    end

    TriggerServerEvent('outlaw_placeables:place', {
        model = preview.modelName,
        item = preview.itemName,
        metadata = preview.metadata,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        rotation = { x = rotation.x, y = rotation.y, z = rotation.z },
        dropMode = dropMode,
        freeze = not dropMode and freezePlaced,
        trunk = preview.trunkData,
        surface = preview.surfaceType,
        throwVelocity = throwVelocity
    })

    notify(Locale.get('general.place_success'))
end

local function handlePreview()
    while currentPreview do
        Wait(0)
        local preview = currentPreview
        if not preview or not DoesEntityExist(preview.entity) then
            cleanPreview()
            break
        end

        if IsPedInAnyVehicle(PlayerPedId(), false) then
            cleanPreview()
            break
        end

        if IsControlPressed(0, controls.distIncrease or 241) then
            preview.distance = math.min(distances.max or 10.0, preview.distance + (previewConfig.distanceStep or 0.25))
        elseif IsControlPressed(0, controls.distDecrease or 242) then
            preview.distance = math.max(distances.min or 0.5, preview.distance - (previewConfig.distanceStep or 0.25))
        end

        if IsControlJustPressed(0, controls.rotateLeft or 44) then
            preview.rotation = preview.rotation - (previewConfig.rotateStep or 5.0)
        elseif IsControlJustPressed(0, controls.rotateRight or 38) then
            preview.rotation = preview.rotation + (previewConfig.rotateStep or 5.0)
        end

        if IsControlJustPressed(0, controls.rotateSnap or 45) then
            local snap = previewConfig.rotateSnap or 90.0
            preview.rotation = math.floor((preview.rotation + snap / 2) / snap) * snap
        end

        if preview.itemConfig and preview.itemConfig.allowDrop then
            if IsControlJustPressed(0, controls.toggleDrop or 47) then
                preview.dropMode = not preview.dropMode
                if preview.dropMode then
                    notify(Locale.get('placement.drop_on'))
                else
                    notify(Locale.get('placement.drop_off'))
                end
            end
        end

        updatePreviewPlacement(preview)
        if preview.invalidReason and preview.invalidReason ~= preview.lastInvalid then
            notify(preview.invalidReason, 'error')
            preview.lastInvalid = preview.invalidReason
        end

        if IsControlJustPressed(0, controls.confirm or 24) then
            if preview.valid then
                sendPlacement(preview)
                cleanPreview()
                break
            else
                notify(preview.invalidReason or Locale.get('validation.invalid_surface'), 'error')
            end
        elseif IsControlJustPressed(0, controls.cancel or 25) then
            notify(Locale.get('commands.cancelled'), 'inform')
            cleanPreview()
            break
        end
    end
end

local function startPreview(itemName, metadata)
    if currentPreview then
        cleanPreview()
    end

    local modelName, itemConfig = getModelFromItem(itemName, metadata)
    if not modelName then
        notify(Locale.get('general.no_model'), 'error')
        return
    end

    local modelHash = ensureModelLoaded(modelName)
    if not modelHash then
        notify(Locale.get('general.invalid_item'), 'error')
        return
    end

    local entity = createPreviewEntity(modelHash)
    local preview = {
        entity = entity,
        itemName = itemName,
        metadata = metadata,
        itemConfig = itemConfig,
        model = modelHash,
        modelName = modelName,
        rotation = GetEntityHeading(PlayerPedId()),
        distance = math.max(distances.min or 0.5, 2.5),
        dropMode = false
    }

    currentPreview = preview
    previewThread = CreateThread(handlePreview)

    if Config.HelpText then
        local confirmKey = '~INPUT_ATTACK~'
        local cancelKey = '~INPUT_AIM~'
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(string.format(Locale.get('placement.prompt'), confirmKey, cancelKey))
        EndTextCommandDisplayHelp(0, false, true, -1)
    end
end

RegisterNetEvent('outlaw_placeables:startPlacement', function(itemName, metadata)
    startPreview(itemName, metadata)
end)

RegisterNetEvent('outlaw_placeables:cancelPlacement', function()
    cleanPreview()
end)

---------------------------------------------------------------------
-- Placement tracking & prompts
---------------------------------------------------------------------
local function attachTarget(placement)
    if not targetEnabled then return end
    if not placement.entity or not DoesEntityExist(placement.entity) then return end

    local interactDistance = placement.interactDistance or 2.0
    local collectLabel = Locale.get('target.collect')
    local inspectLabel = Locale.get('target.inspect')
    local removeLabel = Locale.get('target.remove')

    local options = {
        {
            name = ('outlaw_placeables:collect:%s'):format(placement.id),
            label = collectLabel,
            icon = 'fa-solid fa-hand',
            distance = interactDistance,
            onSelect = function()
                TriggerServerEvent('outlaw_placeables:pickup', placement.id)
            end
        },
        {
            name = ('outlaw_placeables:inspect:%s'):format(placement.id),
            label = inspectLabel,
            icon = 'fa-solid fa-circle-info',
            distance = interactDistance,
            onSelect = function()
                notify(string.format(Locale.get('inspect.item'), placement.item or 'unknown'))
                if placement.owner then
                    notify(string.format(Locale.get('inspect.owner'), placement.owner))
                end
            end
        }
    }

    if Config.Security and Config.Security.allowStaffRemoveAll then
        options[#options + 1] = {
            name = ('outlaw_placeables:remove:%s'):format(placement.id),
            label = removeLabel,
            icon = 'fa-solid fa-ban',
            distance = interactDistance,
            onSelect = function()
                TriggerServerEvent('outlaw_placeables:remove', placement.id)
            end
        }
    end

    local success, err = pcall(function()
        placement.targetId = exports[targetResource]:addLocalEntity(placement.entity, options)
    end)
    if not success then
        print(('outlaw_placeables: unable to register ox_target for placement %s: %s'):format(placement.id, err))
    end
end

local function detachTarget(placement)
    if not targetEnabled then return end
    if not placement.targetId then return end

    local success, err = pcall(function()
        exports[targetResource]:removeLocalEntity(placement.targetId)
    end)

    if not success then
        print(('outlaw_placeables: failed to remove target for placement %s: %s'):format(placement.id, err))
    end

    placement.targetId = nil
end

local function trackPlacement(data)
    if data.coords then
        data.coords = vector3(data.coords.x, data.coords.y, data.coords.z)
    end
    if data.rotation then
        data.rotation = vector3(data.rotation.x or 0.0, data.rotation.y or 0.0, data.rotation.z or 0.0)
    end
    placements[data.id] = data
    if data.netId then
        placementByNet[data.netId] = data
    end

    CreateThread(function()
        while data.netId and not NetworkDoesEntityExistWithNetworkId(data.netId) do
            Wait(50)
        end
        if not data.netId then return end
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        data.entity = entity
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, false)
            FreezeEntityPosition(entity, data.freeze)
            attachTarget(data)
        end
    end)
end

local function untrackPlacement(id)
    local placement = placements[id]
    if not placement then return end

    detachTarget(placement)
    placements[id] = nil
    if placement.netId then
        placementByNet[placement.netId] = nil
    end
end

RegisterNetEvent('outlaw_placeables:placementCreated', function(data)
    trackPlacement(data)
end)

RegisterNetEvent('outlaw_placeables:placementRemoved', function(id)
    untrackPlacement(id)
end)

RegisterNetEvent('outlaw_placeables:syncPlacements', function(all)
    for id in pairs(placements) do
        untrackPlacement(id)
    end
    if type(all) ~= 'table' then return end
    for _, data in ipairs(all) do
        trackPlacement(data)
    end
end)

---------------------------------------------------------------------
-- 3D prompt fallback
---------------------------------------------------------------------
local function promptLoop()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local closest, closestDist
        for _, placement in pairs(placements) do
            if placement.entity and DoesEntityExist(placement.entity) then
                local pos = GetEntityCoords(placement.entity)
                local dist = #(coords - pos)
                local interactDistance = placement.interactDistance or 2.0
                if dist <= interactDistance + 0.3 and (not closestDist or dist < closestDist) then
                    closest = placement
                    closestDist = dist
                end
            end
        end

        if closest and (not targetEnabled) then
            local pos = GetEntityCoords(closest.entity)
            draw3DText(pos + vector3(0.0, 0.0, 0.2), Locale.get('general.press_collect'))
            if IsControlJustPressed(0, controls.collect or 38) then
                TriggerServerEvent('outlaw_placeables:pickup', closest.id)
                Wait(250)
            end
        else
            Wait(150)
        end
    end
end

if not targetEnabled then
    promptThread = CreateThread(promptLoop)
end

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------
local commands = Config.Commands or {}

RegisterCommand(commands.place or 'place', function(_, args)
    local item = args[1]
    if not item then
        notify(Locale.get('commands.missing_item'), 'error')
        return
    end
    TriggerServerEvent('outlaw_placeables:commandPlace', item)
end, false)

RegisterCommand(commands.cancel or 'place_cancel', function()
    cleanPreview()
    notify(Locale.get('commands.cancelled'))
end, false)

RegisterCommand(commands.removeNear or 'place_remove_near', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist
    for _, placement in pairs(placements) do
        if placement.entity and DoesEntityExist(placement.entity) then
            local pos = GetEntityCoords(placement.entity)
            local dist = #(coords - pos)
            if not closestDist or dist < closestDist then
                closest = placement
                closestDist = dist
            end
        end
    end
    if closest then
        TriggerServerEvent('outlaw_placeables:pickup', closest.id)
    else
        notify(Locale.get('validation.need_ground'), 'error')
    end
end, false)

RegisterCommand(commands.cleanupAll or 'place_cleanup_all', function()
    TriggerServerEvent('outlaw_placeables:cleanupAll')
end, false)

RegisterKeyMapping(commands.place or 'place', 'Start placeable placement', 'keyboard', 'G')
RegisterKeyMapping(commands.cancel or 'place_cancel', 'Cancel placeable placement', 'keyboard', 'BACK')
RegisterKeyMapping(commands.removeNear or 'place_remove_near', 'Remove nearby placement', 'keyboard', 'H')

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('outlaw_placeables:requestSync')
end)
