-- server/main.lua
-- Outlaw Placeables - serveur (ESX + ox_inventory)

local ESX = exports['es_extended'] and exports['es_extended']:getSharedObject() or nil

local ActivePlacements = {}  -- by src: { item=itemName, model=model, removed=true/false }
local Placed = {}            -- by id: { owner, item, model, coords/base/offset/heading, netId? }

local function ensureModelForItem(itemName)
    local cfg = Config.Placeables[itemName]
    if not cfg or not cfg.models or #cfg.models == 0 then return nil end
    return cfg.models[1]
end

local function notify(src, msg, typ)
    TriggerClientEvent('outlaw_placeables:notify', src, msg, typ or 'inform')
end

local function registerItems()
    if not ESX or not ESX.RegisterUsableItem then
        SetTimeout(500, registerItems)
        return
    end

    for itemName, data in pairs(Config.Placeables) do
        ESX.RegisterUsableItem(itemName, function(src, item)
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return end

            local ok = exports.ox_inventory:RemoveItem(src, itemName, 1)
            if not ok then
                notify(src, "Item manquant dans l'inventaire.", "error")
                return
            end

            local model = ensureModelForItem(itemName)
            if not model then
                notify(src, "Modèle non configuré pour cet item.", "error")
                exports.ox_inventory:AddItem(src, itemName, 1)
                return
            end

            ActivePlacements[src] = { item = itemName, model = model, removed = true }
            TriggerClientEvent('outlaw_placeables:startPlacement', src, itemName, model)
        end)
    end
end
CreateThread(registerItems)

RegisterNetEvent('outlaw_placeables:cancelPlacement', function(itemName)
    local src = source
    local act = ActivePlacements[src]
    if act and act.item == itemName and act.removed then
        exports.ox_inventory:AddItem(src, itemName, 1)
    end
    ActivePlacements[src] = nil
end)

RegisterNetEvent('outlaw_placeables:placeObject', function(itemName, placement, heading)
    local src = source
    local act = ActivePlacements[src]
    if not act or act.item ~= itemName then
        notify(src, "Placement expiré ou invalide.", "error")
        return
    end

    if type(placement) ~= 'table' or not placement.position or not placement.base then
        notify(src, "Données de placement invalides.", "error")
        exports.ox_inventory:AddItem(src, itemName, 1)
        ActivePlacements[src] = nil
        return
    end

    local id = ('pl_%d_%d'):format(src, GetGameTimer())
    local data = {
        id = id,
        owner = src,
        item = itemName,
        model = act.model,
        coords = placement.position,
        base = placement.base,
        offset = placement.offset or 0.0,
        heading = heading or 0.0,
        surface = (type(placement.surface) == 'table') and placement.surface or nil
    }
    Placed[id] = data
    ActivePlacements[src] = nil

    TriggerClientEvent('outlaw_placeables:spawnObject', -1, data)
end)

RegisterNetEvent('outlaw_placeables:registerObject', function(id, netId)
    local src = source
    local p = Placed[id]
    if p and p.owner == src then
        p.netId = netId
    end
end)

RegisterNetEvent('outlaw_placeables:pickup', function(netId, itemName)
    local src = source
    if not netId or not itemName then return end

    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 then
        DeleteEntity(ent)
    end

    local found
    for id, v in pairs(Placed) do
        if v.item == itemName and v.netId == netId then
            found = id
            break
        end
    end
    if found then Placed[found] = nil end

    if exports.ox_inventory:CanCarryItem(src, itemName, 1) then
        exports.ox_inventory:AddItem(src, itemName, 1)
        notify(src, "Objet ramassé.", "success")
    else
        notify(src, "Inventaire plein.", "error")
    end

    TriggerClientEvent('outlaw_placeables:removeObject', -1, netId)
end)

RegisterNetEvent('outlaw_placeables:requestPlacedObjects', function()
    local src = source
    for _, data in pairs(Placed) do
        TriggerClientEvent('outlaw_placeables:spawnObject', src, data)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    ActivePlacements[src] = nil
end)
