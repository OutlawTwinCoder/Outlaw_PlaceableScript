local Locale = {}

Locales = Locales or {}
local locales = Locales
local activeLocale = Config and Config.Locale or 'en'

local function resolveLocale()
    if not Config or not Config.Locale then
        return 'en'
    end
    if locales[Config.Locale] then
        return Config.Locale
    end
    return 'en'
end

activeLocale = resolveLocale()

local function fetch(path)
    local scope = locales[activeLocale]
    for segment in string.gmatch(path, '([^%.]+)') do
        if not scope then return nil end
        scope = scope[segment]
    end
    return scope
end

function Locale.t(path, fallback)
    local text = fetch(path)
    if text then return text end
    return fallback or path
end

_G.Locale = Locale
return Locale
