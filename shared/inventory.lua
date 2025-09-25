Inventory = {}

local providerName = (Config.InventoryProvider or 'standalone'):lower()
local provider

local function oxAvailable()
    local state = GetResourceState('ox_inventory')
    return state == 'started' or state == 'starting'
end

local function targetAvailable()
    local state = GetResourceState('ox_target')
    return state == 'started' or state == 'starting'
end

local function qbCore()
    local state = GetResourceState('qb-core')
    if state == 'started' or state == 'starting' then
        return exports['qb-core']:GetCoreObject()
    end
end

local providers = {}

providers['ox'] = function()
    if not oxAvailable() then return nil end
    local ox = exports.ox_inventory
    return {
        getItem = function(src, name)
            return ox:GetItem(src, name, nil, true)
        end,
        removeItem = function(src, name, count, metadata)
            return ox:RemoveItem(src, name, count or 1, metadata)
        end,
        addItem = function(src, name, count, metadata)
            return ox:AddItem(src, name, count or 1, metadata)
        end,
        onUse = function(name, cb)
            if not IsDuplicityVersion() then return end
            ox:RegisterUsableItem(name, function(data)
                cb(data.source, data.item.metadata or data.metadata, data.slot)
            end)
        end
    }
end

providers['qs'] = function()
    local state = GetResourceState('qs-inventory')
    if state ~= 'started' and state ~= 'starting' then return nil end
    local qs = exports['qs-inventory']
    return {
        getItem = function(src, name)
            return qs:GetItem(src, name)
        end,
        removeItem = function(src, name, count, metadata)
            return qs:RemoveItem(src, name, count or 1, metadata)
        end,
        addItem = function(src, name, count, metadata)
            return qs:AddItem(src, name, count or 1, metadata)
        end,
        onUse = function(name, cb)
            if not IsDuplicityVersion() then return end
            qs:CreateUsableItem(name, function(source, item)
                cb(source, item and item.info, item and item.slot)
            end)
        end
    }
end

providers['qb'] = function()
    local QBCore = qbCore()
    if not QBCore then return nil end
    return {
        getItem = function(src, name)
            local Player = QBCore.Functions.GetPlayer(src)
            if not Player then return nil end
            return Player.Functions.GetItemByName(name)
        end,
        removeItem = function(src, name, count, metadata)
            local Player = QBCore.Functions.GetPlayer(src)
            if not Player then return false end
            return Player.Functions.RemoveItem(name, count or 1, false, metadata)
        end,
        addItem = function(src, name, count, metadata)
            local Player = QBCore.Functions.GetPlayer(src)
            if not Player then return false end
            return Player.Functions.AddItem(name, count or 1, false, metadata, true)
        end,
        onUse = function(name, cb)
            if not IsDuplicityVersion() then return end
            QBCore.Functions.CreateUseableItem(name, function(source, item)
                cb(source, item and item.info, item and item.slot)
            end)
        end
    }
end

providers['standalone'] = function()
    return {
        getItem = function()
            return { count = 1 }
        end,
        removeItem = function()
            return true
        end,
        addItem = function()
            return true
        end,
        onUse = function() end
    }
end

local function ensureProvider()
    if provider then return provider end
    local factory = providers[providerName] or providers['standalone']
    provider = factory and factory() or providers['standalone']()
    if not provider then
        provider = providers['standalone']()
    end
    return provider
end

function Inventory.getProviderName()
    return providerName
end

function Inventory.getItem(src, name)
    return ensureProvider().getItem(src, name)
end

function Inventory.removeItem(src, name, count, metadata)
    return ensureProvider().removeItem(src, name, count, metadata)
end

function Inventory.addItem(src, name, count, metadata)
    return ensureProvider().addItem(src, name, count, metadata)
end

function Inventory.onUse(name, cb)
    return ensureProvider().onUse(name, cb)
end

function Inventory.supportsTarget()
    return targetAvailable()
end
