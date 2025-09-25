local Persistence = {}
local Utils = Utils

local enabled = Config.Persistence and Config.Persistence.enabled

local function isReady()
    return enabled and MySQL ~= nil
end

function Persistence.enabled()
    return isReady()
end

function Persistence.save(data)
    if not isReady() or not data.persistent then return nil end
    local insertId = MySQL.Sync.insert('INSERT INTO outlaw_placeables (model, x, y, z, rx, ry, rz, is_trunk, owner, meta) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        data.model,
        data.coords.x,
        data.coords.y,
        data.coords.z,
        data.rotation.x,
        data.rotation.y,
        data.rotation.z,
        data.isTrunk and 1 or 0,
        data.owner,
        json.encode(data.metadata or {})
    })
    return insertId
end

function Persistence.remove(id)
    if not isReady() or not id then return end
    MySQL.Async.execute('DELETE FROM outlaw_placeables WHERE id = ?', { id })
end

function Persistence.load()
    if not isReady() then return {} end
    local rows = MySQL.Sync.fetchAll('SELECT * FROM outlaw_placeables ORDER BY created_at ASC', {})
    return rows or {}
end

function Persistence.purge(days)
    if not isReady() or not days or days <= 0 then return end
    MySQL.Async.execute(('DELETE FROM outlaw_placeables WHERE created_at < NOW() - INTERVAL %d DAY'):format(days))
end

_G.Persistence = Persistence
return Persistence
