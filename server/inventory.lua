local Inventory = {}
local Utils = Utils

local providerName = Config.InventoryProvider
local providers = {}

local function oxInventory()
    if GetResourceState('ox_inventory') ~= 'started' then return nil end
    local ox = exports.ox_inventory
    local impl = {}

    function impl.getItem(src, name)
        return ox:GetItem(src, name, nil, true)
    end

    function impl.removeItem(src, name, count, metadata)
        return ox:RemoveItem(src, name, count or 1, metadata)
    end

    function impl.addItem(src, name, count, metadata)
        return ox:AddItem(src, name, count or 1, metadata)
    end

    function impl.onUse(name, cb)
        ox:RegisterUsableItem(name, function(data, slot)
            cb(data.source, data.metadata, slot)
        end)
    end

    return impl
end

local function qsInventory()
    if GetResourceState('qs-inventory') ~= 'started' then return nil end
    local qs = exports['qs-inventory']
    local impl = {}

    function impl.getItem(src, name)
        local item = qs:GetItem(src, name)
        if item and item.amount and item.amount > 0 then
            return item
        end
    end

    function impl.removeItem(src, name, count, metadata)
        return qs:RemoveItem(src, name, count or 1)
    end

    function impl.addItem(src, name, count, metadata)
        return qs:AddItem(src, name, count or 1, metadata)
    end

    function impl.onUse(name, cb)
        qs:RegisterUseItem(name, function(source, item)
            cb(source, item and item.info, item and item.slot)
        end)
    end

    return impl
end

local function qbInventory()
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local QBCore = exports['qb-core']:GetCoreObject()
    if not QBCore then return nil end
    local impl = {}

    function impl.getItem(src, name)
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return nil end
        return player.Functions.GetItemByName(name)
    end

    function impl.removeItem(src, name, count, metadata)
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.RemoveItem(name, count or 1)
    end

    function impl.addItem(src, name, count, metadata)
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.AddItem(name, count or 1, nil, metadata)
    end

    function impl.onUse(name, cb)
        QBCore.Functions.CreateUseableItem(name, function(source, item)
            cb(source, item and item.info, item and item.slot)
        end)
    end

    return impl
end

local function standalone()
    local impl = { store = {} }

    function impl.getItem(src, name)
        impl.store[src] = impl.store[src] or {}
        local entry = impl.store[src][name]
        if entry and entry.count > 0 then
            return { count = entry.count, metadata = entry.metadata }
        end
    end

    function impl.removeItem(src, name, count, metadata)
        impl.store[src] = impl.store[src] or {}
        local entry = impl.store[src][name]
        if entry and entry.count >= (count or 1) then
            entry.count = entry.count - (count or 1)
            return true
        end
        return false
    end

    function impl.addItem(src, name, count, metadata)
        impl.store[src] = impl.store[src] or {}
        local entry = impl.store[src][name]
        if not entry then
            impl.store[src][name] = { count = count or 1, metadata = metadata }
        else
            entry.count = entry.count + (count or 1)
        end
        return true
    end

    function impl.onUse(name, cb)
        RegisterCommand('use_' .. name, function(source)
            local item = impl.getItem(source, name)
            if item then
                cb(source, item.metadata, nil)
            end
        end, false)
    end

    return impl
end

providers.ox = oxInventory
providers.qs = qsInventory
providers.qb = qbInventory
providers.standalone = standalone

local active = providers[providerName] and providers[providerName]() or nil
if not active then
    Utils.log('Inventory provider %s unavailable, falling back to standalone', providerName)
    active = standalone()
end

function Inventory.getItem(src, name)
    if not active or not name then return nil end
    return active.getItem(src, name)
end

function Inventory.removeItem(src, name, count, metadata)
    if not active then return false end
    return active.removeItem(src, name, count, metadata)
end

function Inventory.addItem(src, name, count, metadata)
    if not active then return false end
    return active.addItem(src, name, count, metadata)
end

function Inventory.onUse(name, cb)
    if not active or not cb then return end
    if active.onUse then
        active.onUse(name, cb)
    end
end

_G.Inventory = Inventory
return Inventory
