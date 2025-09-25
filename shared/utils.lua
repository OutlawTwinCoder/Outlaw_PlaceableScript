local Utils = {}

local logEnabled = Config.Logging and Config.Logging.enabled
local prefix = (Config.Logging and Config.Logging.prefix) or '[Outlaw_Placeable]'

function Utils.debug(message, ...)
    if not Config.Debug then return end
    print(('[DEBUG] %s %s'):format(prefix, message:format(...)))
end

function Utils.log(message, ...)
    if not logEnabled then return end
    print(('%s %s'):format(prefix, message:format(...)))
end

function Utils.vector3(v)
    if type(v) == 'vector3' then return v end
    if type(v) == 'table' then
        return vector3(v.x or v[1] or 0.0, v.y or v[2] or 0.0, v.z or v[3] or 0.0)
    end
    return vector3(0.0, 0.0, 0.0)
end

function Utils.round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor(value * power + 0.5) / power
end

function Utils.hasAce(src, ace)
    if not ace then return false end
    if IsPlayerAceAllowed(src, ace) then return true end
    return false
end

_G.Utils = Utils
return Utils
