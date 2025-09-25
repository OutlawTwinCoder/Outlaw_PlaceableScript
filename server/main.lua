local Config = Config
local Locale = Locale
local Utils = Utils
local Inventory = Inventory
local Persistence = Persistence
local Trunk = Trunk

local placedObjects = {}
local byDbId = {}
local objectIdCounter = 0
local rateLimits = {}

local function nextObjectId()
    objectIdCounter = objectIdCounter + 1
    return objectIdCounter
end

local function notify(source, key, default, type)
    if source == 0 then
        Utils.log(default or key or 'notification')
    else
        TriggerClientEvent('outlaw_placeables:notify', source, key, default, type)
    end
end

local function getIdentifier(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier and identifier ~= '' then
            return identifier
        end
    end
    return ('player:%s'):format(src)
end

local function isModelAllowed(itemConfig, model)
    if not model then return false end
    if Config.BlacklistModels then
        for _, blocked in ipairs(Config.BlacklistModels) do
            if blocked == model then
                return false
            end
        end
    end
    if itemConfig and itemConfig.model then
        return itemConfig.model == model
    end
    return Config.MakeEverythingPlaceable.enabled and Config.MakeEverythingPlaceable.fallbackModel == model
end

local function getItemConfig(name)
    return Config.Placeables[name]
end

local function validateDistance(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pedCoords = GetEntityCoords(ped)
    local dist = #(coords - pedCoords)
    if dist > Config.Distance.max + 2.0 then
        return false
    end
    if dist < Config.Distance.minFromPed - 0.5 then
        return false
    end
    return true
end

local function checkStacking(coords)
    if not Config.AntiStacking.enabled then return true end
    local minSep = Config.AntiStacking.minSeparation or 0.25
    for _, obj in pairs(placedObjects) do
        if obj.coords and #(coords - obj.coords) < minSep then
            return false
        end
    end
    return true
end

local function registerObject(data)
    placedObjects[data.netId] = data
    if data.dbId then
        byDbId[data.dbId] = data
    end
    TriggerClientEvent('outlaw_placeables:objectSpawned', -1, {
        netId = data.netId,
        item = data.item,
        coords = data.coords,
        owner = data.owner,
        metadata = data.metadata,
        isTrunk = data.isTrunk,
        vehicleNetId = data.vehicleNetId
    })
    TriggerClientEvent('outlaw_placeables:settleObject', -1, data.netId)
    TriggerClientEvent('outlaw_placeables:registerTarget', -1, data.netId)
end

local function removeObject(data, reason)
    if not data then return end
    if data.entity and DoesEntityExist(data.entity) then
        DeleteEntity(data.entity)
    end
    if data.netId then
        TriggerClientEvent('outlaw_placeables:objectRemoved', -1, data.netId)
    end
    if data.dbId then
        Persistence.remove(data.dbId)
        byDbId[data.dbId] = nil
    end
    if data.isTrunk and data.vehicleNetId then
        Trunk.release(data.vehicleNetId, data.trunkSlot)
    end
    placedObjects[data.netId] = nil
end

local function spawnObject(source, payload, itemConfig)
    local coords = vector3(payload.coords.x, payload.coords.y, payload.coords.z)
    local rotation = vector3(payload.rotation.x or 0.0, payload.rotation.y or 0.0, payload.rotation.z or 0.0)

    if not validateDistance(source, coords) then
        notify(source, 'out_of_range', 'Out of range', 'error')
        return
    end
    if not payload.isTrunk and not checkStacking(coords) then
        notify(source, 'stacking_blocked', 'Too close to another object', 'error')
        return
    end

    if not HasModelLoaded(payload.model) then
        RequestModel(payload.model)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(payload.model) do
            Wait(50)
            if GetGameTimer() > timeout then break end
        end
    end
    local entity = CreateObject(payload.model, coords.x, coords.y, coords.z, true, true, false)
    if not entity or entity == 0 then
        if payload.isTrunk and payload.vehicleNetId and payload.trunkSlot then
            Trunk.release(payload.vehicleNetId, payload.trunkSlot)
        end
        notify(source, 'invalid_surface', 'Failed to create object', 'error')
        return
    end

    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, true)
    if not payload.isTrunk then
        PlaceObjectOnGroundProperly(entity)
    end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    local attempts = 0
    while netId == 0 and attempts < 20 do
        Wait(50)
        netId = NetworkGetNetworkIdFromEntity(entity)
        attempts = attempts + 1
    end
    if netId == 0 then
        if payload.isTrunk and payload.vehicleNetId and payload.trunkSlot then
            Trunk.release(payload.vehicleNetId, payload.trunkSlot)
        end
        DeleteEntity(entity)
        notify(source, 'invalid_surface', 'Failed to network object', 'error')
        return
    end
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)

    if payload.mode == 'throw' then
        local force = Config.Throwing.force or 7.5
        local ped = GetPlayerPed(source)
        if DoesEntityExist(ped) then
            local forward = GetEntityForwardVector(ped)
            ApplyForceToEntity(entity, 1, forward.x * force, forward.y * force, (Config.Throwing.upwardBias or 0.25) * force, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        end
    elseif payload.mode == 'drop' then
        FreezeEntityPosition(entity, false)
    else
        FreezeEntityPosition(entity, Config.FreezePlacedObjects)
    end

    local objectId = nextObjectId()
    local owner = getIdentifier(source)
    local data = {
        objectId = objectId,
        netId = netId,
        entity = entity,
        model = payload.model,
        coords = coords,
        rotation = rotation,
        item = payload.item,
        metadata = payload.metadata,
        owner = owner,
        isTrunk = payload.isTrunk,
        vehicleNetId = payload.vehicleNetId,
        trunkSlot = payload.trunkSlot,
        persistent = itemConfig and itemConfig.persistent or Config.Persistence.enabled,
        trunkData = payload.trunkData
    }

    if data.persistent then
        local meta = data.metadata or {}
        if payload.trunkData then
            meta.__trunk = payload.trunkData
        end
        data.metadata = meta
        data.dbId = Persistence.save({
            model = payload.model,
            coords = coords,
            rotation = rotation,
            owner = owner,
            metadata = meta,
            isTrunk = payload.isTrunk,
            persistent = data.persistent
        })
    end

    registerObject(data)
    Utils.log('Spawned object %s for %s', tostring(netId), owner)
end

local function ensureRate(src, key, interval)
    rateLimits[src] = rateLimits[src] or {}
    local now = GetGameTimer()
    local last = rateLimits[src][key] or 0
    if now - last < interval then
        return false
    end
    rateLimits[src][key] = now
    return true
end

RegisterNetEvent('outlaw_placeables:confirmPlacement', function(payload)
    local src = source
    if not payload or not payload.item or not payload.coords or not payload.model then return end
    if not ensureRate(src, 'place', Config.RateLimits.placementCooldown) then
        notify(src, 'rate_limited', 'Please slow down', 'error')
        return
    end

    local itemConfig = getItemConfig(payload.item)
    if not isModelAllowed(itemConfig, payload.model) then
        notify(src, 'invalid_surface', 'Model not allowed', 'error')
        return
    end
    if not IsModelValid(payload.model) then
        notify(src, 'invalid_surface', 'Invalid model', 'error')
        return
    end

    local item = Inventory.getItem(src, payload.item)
    if not item then
        notify(src, 'no_item', 'Missing item', 'error')
        return
    end

    if payload.vehicleNetId then
        local vehicleEntity = NetworkGetEntityFromNetworkId(payload.vehicleNetId)
        if not vehicleEntity or vehicleEntity == 0 then
            notify(src, 'invalid_surface', 'Vehicle missing', 'error')
            return
        end
        if not IsModelValid(payload.model) then
            notify(src, 'invalid_surface', 'Invalid model', 'error')
            return
        end
        local min, max = GetModelDimensions(payload.model)
        local dims = {
            x = math.abs(max.x - min.x),
            y = math.abs(max.y - min.y),
            z = math.abs(max.z - min.z),
            hash = payload.trunkHash or string.format('%.2f:%.2f:%.2f', math.abs(max.x - min.x), math.abs(max.y - min.y), math.abs(max.z - min.z))
        }
        local slot, cell = Trunk.reserve(payload.vehicleNetId, dims, nil)
        if not slot or not cell then
            notify(src, 'trunk_full', 'Trunk full', 'error')
            return
        end
        payload.coords = { x = cell.x, y = cell.y, z = cell.z }
        payload.rotation = { x = 0.0, y = 0.0, z = cell.w }
        payload.isTrunk = true
        payload.trunkSlot = slot
        payload.trunkData = {
            plate = GetVehicleNumberPlateText(vehicleEntity),
            vehicleModel = GetEntityModel(vehicleEntity)
        }
    else
        payload.isTrunk = false
    end

    if not Inventory.removeItem(src, payload.item, 1, payload.metadata) then
        if payload.isTrunk and payload.vehicleNetId and payload.trunkSlot then
            Trunk.release(payload.vehicleNetId, payload.trunkSlot)
        end
        notify(src, 'no_item', 'Failed to remove item', 'error')
        return
    end

    spawnObject(src, payload, itemConfig)
    notify(src, 'placed', 'Item placed', 'success')
end)

RegisterNetEvent('outlaw_placeables:pickup', function(netId)
    local src = source
    if not ensureRate(src, 'pickup', Config.RateLimits.pickupCooldown) then
        notify(src, 'rate_limited', 'Please slow down', 'error')
        return
    end
    local data = placedObjects[netId]
    if not data then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pedCoords = GetEntityCoords(ped)
    if #(data.coords - pedCoords) > Config.Target.pickupDistance + 1.0 then
        notify(src, 'out_of_range', 'Too far', 'error')
        return
    end
    if data.owner ~= getIdentifier(src) and not Utils.hasAce(src, Config.StaffPermissions.removeAny) then
        notify(src, 'pickup_denied', 'You cannot pick this up', 'error')
        return
    end

    Inventory.addItem(src, data.item, 1, data.metadata)
    removeObject(data, 'pickup')
    notify(src, 'picked_up', 'Collected', 'success')
end)

RegisterNetEvent('outlaw_placeables:remove', function(netId)
    local src = source
    local data = placedObjects[netId]
    if not data then return end
    if not Utils.hasAce(src, Config.StaffPermissions.removeAny) then
        notify(src, 'pickup_denied', 'Insufficient permissions', 'error')
        return
    end
    removeObject(data, 'admin-remove')
    notify(src, 'removed', 'Removed', 'success')
end)

RegisterNetEvent('outlaw_placeables:inspect', function(netId)
    local src = source
    local data = placedObjects[netId]
    if not data then return end
    local owner = data.owner or 'unknown'
    local message = string.format(Locale.t('menu.owner', 'Owner: %s'), owner)
    notify(src, nil, message, 'inform')
end)

RegisterNetEvent('outlaw_placeables:requestTrunkState', function(netId, requestId, dims)
    local state = Trunk.fetch(netId, dims or { x = 0.5, y = 0.5, z = 0.5, hash = 'default' })
    TriggerClientEvent('outlaw_placeables:receiveTrunkState', source, netId, requestId, state)
end)

RegisterNetEvent('outlaw_placeables:commandPlace', function(item)
    local src = source
    if not item then return end
    local info = getItemConfig(item)
    if not info and not Config.MakeEverythingPlaceable.enabled then
        notify(src, 'no_item', 'Item not configured', 'error')
        return
    end
    local has = Inventory.getItem(src, item)
    if not has then
        notify(src, 'no_item', 'Missing item', 'error')
        return
    end
    TriggerClientEvent('outlaw_placeables:startPlacement', src, item, has.metadata)
end)

RegisterCommand(Config.Commands.cleanupAll, function(source)
    if source ~= 0 and not Utils.hasAce(source, Config.StaffPermissions.cleanup) then
        notify(source, 'pickup_denied', 'No permission', 'error')
        return
    end
    for _, data in pairs(placedObjects) do
        removeObject(data, 'cleanup')
    end
    TriggerClientEvent('outlaw_placeables:notify', source, 'commands.cleanup_done', 'Cleanup complete', 'inform')
end, true)

RegisterCommand(Config.Commands.removeNear, function(source)
    if source == 0 then return end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local pedCoords = GetEntityCoords(ped)
    for netId, data in pairs(placedObjects) do
        if #(data.coords - pedCoords) < 5.0 then
            if data.owner == getIdentifier(source) or Utils.hasAce(source, Config.StaffPermissions.removeAny) then
                removeObject(data, 'remove-near')
            end
        end
    end
end)

local function loadPersistence()
    if not Persistence.enabled() then return end
    if Config.Persistence.cleanupDays and Config.Persistence.cleanupDays > 0 then
        Persistence.purge(Config.Persistence.cleanupDays)
    end
    local rows = Persistence.load()
    for _, row in ipairs(rows) do
        local entity = CreateObject(row.model, row.x, row.y, row.z, true, true, false)
        if entity and entity ~= 0 then
            SetEntityCoordsNoOffset(entity, row.x, row.y, row.z, false, false, false)
            SetEntityRotation(entity, row.rx, row.ry, row.rz, 2, true)
            FreezeEntityPosition(entity, Config.FreezePlacedObjects)
            local netId = NetworkGetNetworkIdFromEntity(entity)
            local data = {
                objectId = nextObjectId(),
                netId = netId,
                entity = entity,
                model = row.model,
                coords = vector3(row.x, row.y, row.z),
                rotation = vector3(row.rx, row.ry, row.rz),
                item = nil,
                metadata = row.meta and json.decode(row.meta) or nil,
                owner = row.owner,
                dbId = row.id,
                isTrunk = row.is_trunk == 1,
                vehicleNetId = nil,
                trunkSlot = nil,
                persistent = true
            }
            registerObject(data)
        end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    loadPersistence()
    for itemName, _ in pairs(Config.Placeables) do
        Inventory.onUse(itemName, function(src, metadata)
            TriggerClientEvent('outlaw_placeables:startPlacement', src, itemName, metadata)
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    rateLimits[src] = nil
end)

RegisterCommand(Config.Testing.command, function(source)
    if source ~= 0 and not Utils.hasAce(source, Config.StaffPermissions.cleanup) then
        notify(source, 'pickup_denied', 'No permission', 'error')
        return
    end
    local ped = GetPlayerPed(source)
    local origin = ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 72.0)
    for i = 1, Config.Testing.count do
        local offset = vector3(math.random(-5, 5), math.random(-5, 5), 0.0)
        local coords = origin + offset
        local model = Config.MakeEverythingPlaceable.fallbackModel or `prop_tool_bench02`
        local entity = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
        if entity and entity ~= 0 then
            PlaceObjectOnGroundProperly(entity)
            FreezeEntityPosition(entity, Config.FreezePlacedObjects)
            local netId = NetworkGetNetworkIdFromEntity(entity)
            local data = {
                objectId = nextObjectId(),
                netId = netId,
                entity = entity,
                model = model,
                coords = coords,
                rotation = vector3(0.0, 0.0, 0.0),
                item = 'test',
                metadata = nil,
                owner = 'test',
                persistent = false
            }
            registerObject(data)
        end
    end
    Utils.log('Generated %d test objects', Config.Testing.count)
end, true)
