Locale = {}
Locale._lang = Config.Locale or 'en'

local function getLocale(lang)
    if Locales and Locales[lang] then
        return Locales[lang]
    end
    return Locales and Locales['en'] or {}
end

local function resolve(localeTable, key)
    local value = localeTable
    for segment in string.gmatch(key, '[^%.]+') do
        if type(value) ~= 'table' then return nil end
        value = value[segment]
    end
    return value
end

function Locale.set(lang)
    if lang and Locales and Locales[lang] then
        Locale._lang = lang
    end
end

function Locale.get(key, replacements)
    local lang = Locale._lang
    local localeTable = getLocale(lang)
    local value = resolve(localeTable, key)

    if value == nil and lang ~= 'en' then
        value = resolve(getLocale('en'), key)
    end

    if type(value) == 'table' then
        return value
    end

    if type(value) ~= 'string' then
        return key
    end

    if replacements then
        for k, v in pairs(replacements) do
            value = value:gsub('%%{' .. k .. '}', tostring(v))
        end
    end

    return value
end

function Locale.notify(src, message, notifType)
    if type(src) == 'table' then
        message, notifType = src.message, src.type
        src = src.source
    end

    if IsDuplicityVersion() then
        TriggerClientEvent('outlaw_placeables:notify', src, message, notifType)
    else
        TriggerEvent('outlaw_placeables:notify', message, notifType)
    end
end
