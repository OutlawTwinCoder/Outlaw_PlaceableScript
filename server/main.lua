local antiStack = Config.AntiStacking or {}
local distances = Config.Distances or {}
local trunkConfig = Config.Trunk or {}
local persistenceConfig = Config.Persistence or {}
local freezePlaced = Config.FreezePlacedObjects ~= false

local placements = {}
local placementByNet = {}
local trunkSlots = {}
local placementId = 0
local lib = rawget(_G, 'lib')

local function nextPlacementId()
    placementId = placementId + 1
    return placementId
end

local function vectorFromTable(data)
    return vector3(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0)
end

local function tableFromVector(vec)
    return { x = vec.x, y = vec.y, z = vec.z }
end

local function getIdentifier(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local identifier = GetPlayerIdentifier(src, i)
        if identifier and identifier ~= '' then
            return identifier
        end
    end
    return tostring(src)
end

local function ensureModelLoaded(model)
    local modelHash = model
    if type(model) == 'string' then
        modelHash = joaat(model)
    end
    if modelHash == 0 or not IsModelValid(modelHash) then
        return nil
    end
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do
            Wait(0)
        end
    end
    return modelHash
end

local function getItemConfig(itemName)
    if Config.Items and Config.Items[itemName] then
        return Config.Items[itemName]
    end
    if Config.MakeEverythingPlaceable and Config.MakeEverythingPlaceable.enabled then
        return {
            models = { Config.MakeEverythingPlaceable.fallbackModel },
            allowDrop = true,
            allowTrunk = true,
            persistent = persistenceConfig.default,
            interactDistance = 2.0
        }
    end
    return nil
end

local function isModelAllowedForItem(itemName, modelName)
    local cfg = Config.Items and Config.Items[itemName]
    if cfg and cfg.models then
        for _, m in ipairs(cfg.models) do
            if m == modelName then
                return true
            end
        end
        return false
    end
    if Config.MakeEverythingPlaceable and Config.MakeEverythingPlaceable.enabled then
        return modelName == Config.MakeEverythingPlaceable.fallbackModel
    end
    return false
end

local function checkStacking(coords)
    if not antiStack.enabled then return true end
    for _, placement in pairs(placements) do
        local pos = placement.coords
        if pos then
            local distXY = #(vector2(pos.x, pos.y) - vector2(coords.x, coords.y))
            local heightDiff = math.abs(pos.z - coords.z)
            if distXY < (antiStack.minSeparation or 0.3) and heightDiff < (antiStack.heightTolerance or 0.5) then
                return false
            end
        end
    end
    return true
end

local function isWithinDistance(pedCoords, coords)
    local dist = #(pedCoords - coords)
    if distances.max and dist > distances.max + 1.0 then
        return false
    end
    if distances.min and dist < distances.min - 0.3 then
        return false
    end
    return true
end

local function reserveTrunkSlot(vehicleNetId, slot, info)
    local entry = trunkSlots[vehicleNetId]
    if not entry then
        entry = { capacity = info.capacity or 0, items = {} }
        trunkSlots[vehicleNetId] = entry
    elseif info.capacity and info.capacity > 0 and entry.capacity == 0 then
        entry.capacity = info.capacity
    end
    entry.items[slot] = true
end

local function releaseTrunkSlot(vehicleNetId, slot)
    if not trunkSlots[vehicleNetId] then return end
    trunkSlots[vehicleNetId].items[slot] = nil
    if next(trunkSlots[vehicleNetId].items) == nil then
        trunkSlots[vehicleNetId] = nil
    end
end

local function addPlacement(data)
    placements[data.id] = data
    if data.netId then
        placementByNet[data.netId] = data
    end
    if data.trunk and data.trunk.vehicle and data.trunk.slot then
        reserveTrunkSlot(data.trunk.vehicle, data.trunk.slot, data.trunk)
    end
end

local function removePlacement(id)
    local placement = placements[id]
    if not placement then return end

    if placement.entity and DoesEntityExist(placement.entity) then
        DeleteEntity(placement.entity)
    elseif placement.netId and NetworkDoesEntityExistWithNetworkId(placement.netId) then
        local entity = NetworkGetEntityFromNetworkId(placement.netId)
        if entity and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end

    if placement.netId then
        placementByNet[placement.netId] = nil
    end

    if placement.trunk and placement.trunk.vehicle and placement.trunk.slot then
        releaseTrunkSlot(placement.trunk.vehicle, placement.trunk.slot)
    end

    placements[id] = nil
    TriggerClientEvent('outlaw_placeables:placementRemoved', -1, id)
end

local function spawnPlacement(data, src)
    local modelHash = ensureModelLoaded(data.model)
    if not modelHash then
        return nil, 'model'
    end

    local coords = vectorFromTable(data.coords)
    local rotation = vectorFromTable(data.rotation)

    local entity = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, true, true, false)
    if not entity or entity == 0 then
        return nil, 'entity'
    end

    SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, true)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHasGravity(entity, true)
    SetEntityAsMissionEntity(entity, true, true)

    ActivatePhysics(entity)
    FreezeEntityPosition(entity, false)

    if data.throwVelocity then
        SetEntityVelocity(entity, data.throwVelocity.x or 0.0, data.throwVelocity.y or 0.0, data.throwVelocity.z or 0.0)
    end

    if not (data.trunk and data.trunk.vehicle) then
        PlaceObjectOnGroundProperly(entity)
        Wait(10)
        PlaceObjectOnGroundProperly(entity)
    end

    local start = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() - start < 1500 do
        Wait(50)
    end

    local function settle()
        local settleStart = GetGameTimer()
        while GetGameTimer() - settleStart < 1500 do
            local vx, vy, vz = table.unpack(GetEntityVelocity(entity))
            if (vx * vx + vy * vy + vz * vz) <= 0.0025 then
                break
            end
            Wait(50)
        end
    end

    if not data.dropMode then
        settle()
        if data.freeze ~= false and freezePlaced then
            FreezeEntityPosition(entity, true)
        end
    end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)

    local placement = {
        id = data.id,
        netId = netId,
        entity = entity,
        model = data.model,
        item = data.item,
        coords = coords,
        rotation = rotation,
        owner = data.owner,
        source = src,
        trunk = data.trunk,
        metadata = data.metadata,
        freeze = not data.dropMode and data.freeze ~= false,
        interactDistance = data.interactDistance,
        persistent = data.persistent,
        dbId = data.dbId
    }

    addPlacement(placement)

    TriggerClientEvent('outlaw_placeables:placementCreated', -1, {
        id = placement.id,
        netId = placement.netId,
        item = placement.item,
        coords = tableFromVector(placement.coords),
        rotation = tableFromVector(placement.rotation),
        trunk = placement.trunk,
        owner = placement.owner,
        metadata = placement.metadata,
        interactDistance = placement.interactDistance,
        freeze = placement.freeze
    })

    return placement
end

local function serializePlacements()
    local list = {}
    for _, placement in pairs(placements) do
        list[#list + 1] = {
            id = placement.id,
            netId = placement.netId,
            item = placement.item,
            coords = tableFromVector(placement.coords),
            rotation = tableFromVector(placement.rotation),
            trunk = placement.trunk,
            owner = placement.owner,
            metadata = placement.metadata,
            interactDistance = placement.interactDistance,
            freeze = placement.freeze
        }
    end
    return list
end

---------------------------------------------------------------------
-- Persistence helpers
---------------------------------------------------------------------
local MySQL = rawget(_G, 'MySQL')
local function dbInsertPlacement(data, cb)
    if not persistenceConfig.enabled then
        if cb then cb(nil) end
        return
    end

    local payload = {
        model = data.model,
        item = data.item,
        coords = json.encode(data.coords),
        rotation = json.encode(data.rotation),
        isTrunk = data.trunk and data.trunk.vehicle and 1 or 0,
        trunkId = data.trunk and data.trunk.vehicle or nil,
        trunkSlot = data.trunk and data.trunk.slot or nil,
        owner = data.owner,
        metadata = data.metadata and json.encode(data.metadata) or nil
    }

    if exports and exports.oxmysql then
        exports.oxmysql:insert('INSERT INTO outlaw_placeables (model, item, coords, rotation, isTrunk, trunkId, trunkSlot, owner, metadata) VALUES (:model, :item, :coords, :rotation, :isTrunk, :trunkId, :trunkSlot, :owner, :metadata)', payload, cb)
    elseif MySQL and MySQL.Async and MySQL.Async.insert then
        MySQL.Async.insert('INSERT INTO outlaw_placeables (model, item, coords, rotation, isTrunk, trunkId, trunkSlot, owner, metadata) VALUES (@model, @item, @coords, @rotation, @isTrunk, @trunkId, @trunkSlot, @owner, @metadata)', payload, cb)
    else
        if cb then cb(nil) end
    end
end

local function dbDeletePlacement(id)
    if not persistenceConfig.enabled then return end
    local params = { id = id }
    if exports and exports.oxmysql then
        exports.oxmysql:execute('DELETE FROM outlaw_placeables WHERE id = :id', params)
    elseif MySQL and MySQL.Async and MySQL.Async.execute then
        MySQL.Async.execute('DELETE FROM outlaw_placeables WHERE id = @id', params)
    end
end

local function loadPersistedPlacements()
    if not persistenceConfig.enabled then return end
    local function handle(rows)
        if not rows then return end
        for _, row in ipairs(rows) do
            local coords = json.decode(row.coords)
            local rotation = json.decode(row.rotation)
            local trunk
            if row.isTrunk == 1 and row.trunkId then
                trunk = {
                    vehicle = tonumber(row.trunkId),
                    slot = row.trunkSlot and tonumber(row.trunkSlot) or nil,
                    capacity = trunkConfig.defaultCapacity or 0
                }
            end
            local id = nextPlacementId()
            local placement = {
                id = id,
                model = row.model,
                item = row.item,
                coords = vectorFromTable(coords),
                rotation = vectorFromTable(rotation),
                owner = row.owner,
                trunk = trunk,
                metadata = row.metadata and json.decode(row.metadata) or nil,
                persistent = true,
                dbId = row.id,
                interactDistance = (Config.Items[row.item] and Config.Items[row.item].interactDistance) or 2.0
            }
            local spawned = spawnPlacement(placement, 0)
            if spawned then
                spawned.dbId = row.id
            end
        end
    end

    if exports and exports.oxmysql then
        exports.oxmysql:execute('SELECT * FROM outlaw_placeables', {}, handle)
    elseif MySQL and MySQL.Async and MySQL.Async.fetchAll then
        MySQL.Async.fetchAll('SELECT * FROM outlaw_placeables', {}, handle)
    end
end

---------------------------------------------------------------------
-- Placement flow
---------------------------------------------------------------------
local function canCleanupAll(source)
    if not Config.Security or not Config.Security.allowStaffRemoveAll then
        return false
    end
    local ace = Config.Security.staffAce or 'command.place_cleanup_all'
    return IsPlayerAceAllowed(source, ace)
end

local function handlePlacementRequest(source, data)
    if type(data) ~= 'table' then return end
    local itemName = data.item
    if not itemName then return end

    local itemConfig = getItemConfig(itemName)
    if not itemConfig then
        Locale.notify(source, Locale.get('general.invalid_item'), 'error')
        return
    end

    if not isModelAllowedForItem(itemName, data.model) then
        Locale.notify(source, Locale.get('general.invalid_item'), 'error')
        return
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local pedCoords = GetEntityCoords(ped)
    local coords = vectorFromTable(data.coords)

    if data.trunk then
        data.trunk.vehicle = data.trunk.vehicle and tonumber(data.trunk.vehicle) or nil
        data.trunk.slot = data.trunk.slot and math.floor(tonumber(data.trunk.slot)) or nil
    end

    if not isWithinDistance(pedCoords, coords) then
        Locale.notify(source, Locale.get('validation.too_far'), 'error')
        return
    end

    if not checkStacking(coords) and not (data.trunk and data.trunk.vehicle) then
        Locale.notify(source, Locale.get('validation.stacking'), 'error')
        return
    end

    if data.trunk and data.trunk.vehicle then
        local vehicleNetId = data.trunk.vehicle
        local slot = data.trunk.slot
        trunkSlots[vehicleNetId] = trunkSlots[vehicleNetId] or { capacity = data.trunk.capacity or 0, items = {} }
        if data.trunk.capacity and data.trunk.capacity > 0 then
            trunkSlots[vehicleNetId].capacity = data.trunk.capacity
        end
        if trunkSlots[vehicleNetId].items[slot] then
            Locale.notify(source, Locale.get('validation.trunk_full'), 'error')
            return
        end
        local maxCapacity = trunkSlots[vehicleNetId].capacity
        if maxCapacity > 0 and slot > maxCapacity then
            Locale.notify(source, Locale.get('validation.trunk_full'), 'error')
            return
        end
    elseif itemConfig.allowTrunk == false and data.surface == 'trunk' then
        Locale.notify(source, Locale.get('validation.trunk_only'), 'error')
        return
    end

    local inventoryItem = Inventory.getItem(source, itemName)
    if not inventoryItem then
        Locale.notify(source, Locale.get('general.invalid_item'), 'error')
        return
    end

    if not Inventory.removeItem(source, itemName, 1, data.metadata) then
        Locale.notify(source, Locale.get('general.invalid_item'), 'error')
        return
    end

    local id = nextPlacementId()
    local owner = getIdentifier(source)
    local persistent = (persistenceConfig.enabled and (persistenceConfig.default or itemConfig.persistent)) or false

    local placementData = {
        id = id,
        model = data.model,
        item = itemName,
        coords = tableFromVector(coords),
        rotation = tableFromVector(vectorFromTable(data.rotation)),
        metadata = data.metadata,
        owner = owner,
        trunk = data.trunk,
        dropMode = data.dropMode,
        freeze = data.freeze,
        interactDistance = itemConfig.interactDistance or 2.0,
        persistent = persistent
    }

    local function finalize(dbId)
        placementData.dbId = dbId
        spawnPlacement(placementData, source)
    end

    if persistent then
        dbInsertPlacement(placementData, function(id)
            placementData.dbId = id
            finalize(id)
        end)
    else
        finalize(nil)
    end
end

RegisterNetEvent('outlaw_placeables:place', function(data)
    local src = source
    handlePlacementRequest(src, data)
end)

RegisterNetEvent('outlaw_placeables:pickup', function(id)
    local src = source
    local placement = placements[id]
    if not placement then return end

    if placement.owner ~= getIdentifier(src) and not canCleanupAll(src) then
        return
    end

    Inventory.addItem(src, placement.item, 1, placement.metadata)
    if placement.persistent and placement.dbId then
        dbDeletePlacement(placement.dbId)
    end
    removePlacement(id)
    Locale.notify(src, Locale.get('general.remove_success'))
end)

RegisterNetEvent('outlaw_placeables:remove', function(id)
    local src = source
    if not canCleanupAll(src) then return end
    local placement = placements[id]
    if not placement then return end

    if placement.persistent and placement.dbId then
        dbDeletePlacement(placement.dbId)
    end
    removePlacement(id)
end)

RegisterNetEvent('outlaw_placeables:cleanupAll', function()
    local src = source
    if not canCleanupAll(src) then return end
    for id in pairs(placements) do
        removePlacement(id)
    end
    Locale.notify(src, Locale.get('commands.cleaned'))
end)

RegisterNetEvent('outlaw_placeables:commandPlace', function(item)
    local src = source
    if not item then
        Locale.notify(src, Locale.get('commands.missing_item'), 'error')
        return
    end
    local cfg = getItemConfig(item)
    if not cfg then
        Locale.notify(src, Locale.get('commands.unknown_item'), 'error')
        return
    end
    local hasItem = Inventory.getItem(src, item)
    if not hasItem then
        Locale.notify(src, Locale.get('general.invalid_item'), 'error')
        return
    end
    TriggerClientEvent('outlaw_placeables:startPlacement', src, item)
end)

RegisterNetEvent('outlaw_placeables:requestSync', function()
    local src = source
    TriggerClientEvent('outlaw_placeables:syncPlacements', src, serializePlacements())
end)

AddEventHandler('playerDropped', function()
    -- placeholder for cleanup if required later
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    loadPersistedPlacements()
    for itemName in pairs(Config.Items or {}) do
        Inventory.onUse(itemName, function(src, metadata)
            TriggerClientEvent('outlaw_placeables:startPlacement', src, itemName, metadata)
        end)
    end
end)

if lib and lib.callback then
    lib.callback.register('outlaw_placeables:getPlacements', function()
        return serializePlacements()
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, placement in pairs(placements) do
        if placement.persistent then
            -- leave entity for respawn
        else
            if placement.entity and DoesEntityExist(placement.entity) then
                DeleteEntity(placement.entity)
            end
        end
    end
end)
