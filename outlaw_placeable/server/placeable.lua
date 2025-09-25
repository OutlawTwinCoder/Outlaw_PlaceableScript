local placements = {}

local function vectorToTable(vec)
    if not vec then return nil end
    return { x = vec.x + 0.0, y = vec.y + 0.0, z = vec.z + 0.0 }
end

local function log(message, ...)
    local text = ('[outlaw_placeable] ' .. message):format(...)
    print(text)
end

RegisterNetEvent('outlaw_placeable:placed', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end

    local coords = payload.coords
    if type(coords) == 'vector3' then
        coords = vectorToTable(coords)
    elseif type(coords) == 'table' then
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
    end

    local entry = {
        player = src,
        item = payload.item,
        heading = payload.heading or 0.0,
        model = payload.model,
        coords = coords,
        time = os.time()
    }

    placements[#placements + 1] = entry

    local playerName = GetPlayerName(src) or ('Player %s'):format(src)
    if coords then
        log('%s placed %s at %.2f %.2f %.2f', playerName, payload.item or 'unknown', coords.x, coords.y, coords.z)
    else
        log('%s placed %s', playerName, payload.item or 'unknown')
    end
end)

RegisterNetEvent('outlaw_placeable:previewCancelled', function(item)
    local src = source
    local playerName = GetPlayerName(src) or ('Player %s'):format(src)
    log('%s cancelled placing %s', playerName, item or 'unknown')
end)

exports('getPlacements', function()
    return placements
end)
