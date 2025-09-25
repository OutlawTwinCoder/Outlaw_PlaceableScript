local raycast = PlaceableRaycast
local physics = PlaceablePhysics

local previewState = {
    active = false
}

local function notify(message, messageType)
    if lib and lib.notify then
        lib.notify({
            description = message,
            type = messageType or 'inform'
        })
    else
        print(('[outlaw_placeable] %s'):format(message))
    end
end

local function loadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model)
        local attempts = 0
        while not HasModelLoaded(model) do
            attempts = attempts + 1
            if attempts > 100 then
                return false
            end
            Wait(0)
        end
    end

    return true
end

local function unloadModel(model)
    if HasModelLoaded(model) then
        SetModelAsNoLongerNeeded(model)
    end
end

local function resetPreview()
    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end

    if previewState.entity and DoesEntityExist(previewState.entity) then
        DeleteEntity(previewState.entity)
    end

    if previewState.model then
        unloadModel(previewState.model)
    end

    if Config.Callbacks.OnPreviewEnd then
        pcall(Config.Callbacks.OnPreviewEnd, previewState)
    end

    previewState = {
        active = false
    }
end

local function showPreviewHelp()
    if not (lib and lib.showTextUI) then return end

    local confirm = ('LMB - %s'):format(Config.GetText('confirm'))
    local cancel = ('RMB - %s'):format(Config.GetText('cancel'))
    local rotate = ('Q/E - %s'):format('Rotate')
    local scrollEnabled = Config.Distance.scroll
    if previewState and previewState.distanceConfig and previewState.distanceConfig.scroll ~= nil then
        scrollEnabled = previewState.distanceConfig.scroll
    end

    local distance = scrollEnabled and 'Scroll - Distance' or ''

    local title = previewState and previewState.label or 'Placeable'
    local lines = { ('%s'):format(title), confirm, cancel, rotate }
    if distance ~= '' then
        lines[#lines + 1] = distance
    end

    lib.showTextUI(table.concat(lines, '\n'), {
        position = 'right-center'
    })
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getDistanceConfig(entry)
    local defaults = Config.Distance
    if not entry or not entry.distance then
        return defaults
    end

    return {
        min = entry.distance.min or defaults.min,
        max = entry.distance.max or defaults.max,
        default = entry.distance.default or defaults.default,
        scroll = entry.distance.scroll ~= nil and entry.distance.scroll or defaults.scroll
    }
end

local function getRotationStep(entry)
    return entry and entry.rotationStep or Config.RotationStep
end

local function updatePreviewEntityAlpha(blocked)
    if not previewState.entity then return end

    local alpha = blocked and Config.Preview.blockedAlpha or Config.Preview.minAlpha
    SetEntityAlpha(previewState.entity, alpha, false)
end

local function ensurePreviewEntity()
    if previewState.entity and DoesEntityExist(previewState.entity) then
        return previewState.entity
    end

    if not loadModel(previewState.model) then
        notify('Failed to load model', 'error')
        resetPreview()
        return nil
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local entity = CreateObject(previewState.model, coords.x, coords.y, coords.z, false, false, false)

    if not entity or not DoesEntityExist(entity) then
        notify('Failed to create preview entity', 'error')
        resetPreview()
        return nil
    end

    SetEntityCollision(entity, false, false)
    SetEntityAlpha(entity, Config.Preview.minAlpha, false)
    SetEntityCompletelyDisableCollision(entity, true, true)
    SetEntityInvincible(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)

    previewState.entity = entity

    return entity
end

local function validateSurface(normal, entityHit)
    if not normal then return false end
    if normal.z < (previewState.surfaceNormalLimit or Config.MinSurfaceNormalZ) then
        return false
    end

    if entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        if IsEntityAVehicle(entityHit) then
            return false
        end
    end

    return true
end

local function handleControls()
    DisableControlAction(0, Config.Controls.confirm, true)
    DisableControlAction(0, Config.Controls.cancel, true)
    DisableControlAction(0, Config.Controls.rotateLeft, true)
    DisableControlAction(0, Config.Controls.rotateRight, true)
    DisableControlAction(0, Config.Controls.distanceIncrease, true)
    DisableControlAction(0, Config.Controls.distanceDecrease, true)
    DisablePlayerFiring(PlayerId(), true)

    if IsDisabledControlJustPressed(0, Config.Controls.rotateLeft) then
        previewState.heading = previewState.heading - previewState.rotationStep
    elseif IsDisabledControlJustPressed(0, Config.Controls.rotateRight) then
        previewState.heading = previewState.heading + previewState.rotationStep
    end

    if IsDisabledControlJustPressed(0, Config.Controls.toggleForwardMode) then
        previewState.forwardMode = previewState.forwardMode == 'camera' and 'ped' or 'camera'
        notify(('Preview mode: %s'):format(previewState.forwardMode))
    end

    local scrollEnabled = previewState.distanceConfig.scroll
    if scrollEnabled == nil then
        scrollEnabled = Config.Distance.scroll
    end

    if scrollEnabled then
        if IsDisabledControlPressed(0, Config.Controls.distanceIncrease) then
            previewState.distance = math.min(previewState.distance + 0.05, previewState.distanceConfig.max)
        elseif IsDisabledControlPressed(0, Config.Controls.distanceDecrease) then
            previewState.distance = math.max(previewState.distance - 0.05, previewState.distanceConfig.min)
        end
    end

    if IsDisabledControlJustPressed(0, Config.Controls.cancel) then
        if previewState.itemName then
            TriggerServerEvent('outlaw_placeable:previewCancelled', previewState.itemName)
        end
        resetPreview()
        return false
    end

    if IsDisabledControlJustPressed(0, Config.Controls.confirm) then
        if previewState.valid and not previewState.waitingUse then
            previewState.waitingUse = true
            exports.ox_inventory:useItem(previewState.itemData, function(success)
                previewState.waitingUse = false

                if not success then
                    notify(Config.GetText('missingItem'), 'error')
                    resetPreview()
                    return
                end

                previewState.confirmed = true
            end)
        elseif not previewState.valid then
            notify(Config.GetText('invalidSurface'), 'error')
        end
    end

    return true
end

local function computePlacement()
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    pedCoords = vector3(pedCoords.x, pedCoords.y, pedCoords.z)

    local distance = previewState.distance
    local useCamera = previewState.forwardMode == 'camera'
    local hit, coords, normal, entityHit

    if useCamera then
        hit, coords, normal, entityHit = raycast.FromCamera(distance, nil, ped)
    else
        hit, coords, normal, entityHit = raycast.FromPedForward(ped, distance, nil)
    end

    if not hit then
        coords = pedCoords + GetEntityForwardVector(ped) * distance
        coords = vector3(coords.x, coords.y, pedCoords.z)
        normal = vector3(0.0, 0.0, 1.0)
    end

    coords = vector3(coords.x, coords.y, coords.z)

    local snappedCoords, snappedNormal = physics.SnapToGround(coords, previewState.entity)
    normal = snappedNormal or normal
    coords = snappedCoords or coords

    local isValidSurface = validateSurface(normal, entityHit)
    local delta = coords - pedCoords
    local distanceToPed = math.sqrt((delta.x * delta.x) + (delta.y * delta.y) + (delta.z * delta.z))
    if distanceToPed < (previewState.minPedDistance or Config.MinPedDistance) then
        isValidSurface = false
        previewState.validationMessage = Config.GetText('tooClose')
    elseif not isValidSurface then
        previewState.validationMessage = Config.GetText('invalidSurface')
    else
        previewState.validationMessage = nil
    end

    previewState.valid = isValidSurface
    previewState.currentCoords = coords
    previewState.currentNormal = normal
    previewState.lastHitEntity = entityHit

    if isValidSurface then
        previewState.lastValidCoords = coords
        previewState.lastValidNormal = normal
    end

    return coords, normal
end

local function finalizePlacement()
    local previewEntity = previewState.entity
    local model = previewState.model
    local coords = previewState.lastValidCoords or previewState.currentCoords

    if previewEntity and DoesEntityExist(previewEntity) then
        DeleteEntity(previewEntity)
    end

    if not coords or not model then
        resetPreview()
        return
    end

    if not HasModelLoaded(model) and not loadModel(model) then
        notify('Failed to load model for placement.', 'error')
        resetPreview()
        return
    end

    local entity = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    if not entity or not DoesEntityExist(entity) then
        notify('Failed to create placed object.', 'error')
        resetPreview()
        return
    end

    SetEntityAlpha(entity, Config.Preview.maxAlpha, false)
    SetEntityCollision(entity, true, true)
    SetEntityCompletelyDisableCollision(entity, false, false)
    SetEntityInvincible(entity, false)
    SetEntityDynamic(entity, true)
    SetEntityAsMissionEntity(entity, true, true)

    physics.ApplyPlacement(entity, coords, previewState.heading)

    CreateThread(function()
        physics.SettleEntity(entity)
    end)

    if Config.Callbacks.OnPlaced then
        pcall(Config.Callbacks.OnPlaced, entity, previewState)
    end

    TriggerServerEvent('outlaw_placeable:placed', {
        item = previewState.itemName,
        coords = coords,
        heading = previewState.heading,
        model = model
    })

    previewState.entity = nil
    previewState.model = nil
    resetPreview()
    unloadModel(model)
end

local function previewLoop()
    if Config.Callbacks.OnPreviewStart then
        pcall(Config.Callbacks.OnPreviewStart, previewState)
    end

    while previewState.active do
        Wait(Config.Preview.updateInterval)

        if not ensurePreviewEntity() then
            break
        end

        if not handleControls() then
            break
        end

        local coords = previewState.currentCoords
        local normal = previewState.currentNormal

        coords, normal = computePlacement()

        if previewState.entity and DoesEntityExist(previewState.entity) and coords then
            SetEntityCoordsNoOffset(previewState.entity, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(previewState.entity, previewState.heading)
        end

        updatePreviewEntityAlpha(not previewState.valid)

        if previewState.confirmed and previewState.valid then
            finalizePlacement()
            break
        elseif previewState.confirmed and not previewState.valid then
            previewState.confirmed = false
        end

        Wait(0)
    end
end

local function startPreview(itemName, itemData, slot)
    if previewState.active then
        notify(Config.GetText('busy'), 'error')
        return false
    end

    local entry = Config.Placeables[itemName]
    if not entry then
        notify(('Item %s is not configured as placeable.'):format(itemName), 'error')
        return false
    end

    if not entry.model then
        notify(('Item %s is missing a model in the config.'):format(itemName), 'error')
        return false
    end

    local distanceConfig = getDistanceConfig(entry)

    previewState = {
        active = true,
        itemName = itemName,
        itemData = itemData,
        slot = slot,
        model = entry.model,
        heading = GetEntityHeading(PlayerPedId()),
        rotationStep = getRotationStep(entry),
        distanceConfig = distanceConfig,
        distance = clamp((entry.distance and entry.distance.default) or distanceConfig.default or Config.Distance.default, distanceConfig.min, distanceConfig.max),
        forwardMode = entry.forwardMode or Config.ForwardMode,
        minPedDistance = entry.minPedDistance or Config.MinPedDistance,
        surfaceNormalLimit = entry.minSurfaceNormalZ or Config.MinSurfaceNormalZ
    }

    previewState.label = Config.GetItemLabel(itemName)

    ensurePreviewEntity()
    showPreviewHelp()

    CreateThread(previewLoop)

    return true
end

exports('placeable_item', function(itemData, slot)
    local name = itemData and itemData.name or nil
    if not name then
        notify('Invalid item data received from ox_inventory.', 'error')
        return false
    end

    return startPreview(name, itemData, slot)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if previewState.active then
        resetPreview()
    end
end)

RegisterNetEvent('outlaw_placeable:cancelPreview', function()
    if previewState.active then
        resetPreview()
    end
end)
