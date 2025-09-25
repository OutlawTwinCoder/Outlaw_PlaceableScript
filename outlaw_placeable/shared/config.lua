Config = {}

Config.Locale = 'en'

Config.Distance = {
    min = 1.0,
    max = 10.0,
    default = 3.0,
    scroll = true
}

Config.RotationStep = 5.0
Config.MinPedDistance = 1.0
Config.MinSurfaceNormalZ = 0.55
Config.ForwardMode = 'camera' -- 'camera' or 'ped'

Config.Controls = {
    confirm = 24,      -- INPUT_ATTACK (LMB)
    cancel = 25,       -- INPUT_AIM (RMB)
    rotateLeft = 44,   -- INPUT_COVER (Q)
    rotateRight = 38,  -- INPUT_PICKUP (E)
    toggleForwardMode = 47, -- INPUT_DETONATE (G)
    distanceIncrease = 17,  -- INPUT_WEAPON_WHEEL_NEXT
    distanceDecrease = 16   -- INPUT_WEAPON_WHEEL_PREV
}

Config.Preview = {
    minAlpha = 120,
    maxAlpha = 255,
    blockedAlpha = 80,
    updateInterval = 0
}

Config.Settle = {
    lockMs = 150,
    settleDelay = 200,
    epsilon = 0.05,
    maxAttempts = 2,
    failZ = -50.0
}

Config.PersistenceMode = 'volatile' -- 'volatile', 'kvp', 'database'

Config.Placeables = {
    -- Example entries. Add your own items here.
    ['placeable_crate'] = {
        model = `prop_tool_box_04`,
        pickup = true,
        locale = {
            en = 'Utility Crate',
            fr = 'Caisse utilitaire'
        }
    },
    ['placeable_cone'] = {
        model = `prop_roadcone02a`,
        pickup = true,
        rotationStep = 15.0,
        distance = { min = 0.5, max = 6.0, default = 2.0 },
        locale = {
            en = 'Road Cone',
            fr = 'Cône de signalisation'
        }
    }
}

Config.Locales = {
    en = {
        placing = 'Placing %s',
        invalidSurface = 'You cannot place this item here.',
        tooClose = 'Move a little further away.',
        missingItem = 'You no longer have this item.',
        busy = 'You are already placing an item.',
        confirm = 'Confirm placement',
        cancel = 'Cancel placement'
    },
    fr = {
        placing = 'Placement de %s',
        invalidSurface = 'Impossible de placer cet objet ici.',
        tooClose = 'Reculez un peu.',
        missingItem = "Vous n'avez plus cet objet.",
        busy = 'Vous placez déjà un objet.',
        confirm = 'Valider le placement',
        cancel = 'Annuler le placement'
    }
}

Config.Callbacks = {
    OnPreviewStart = nil,
    OnPreviewEnd = nil,
    OnPlaced = nil,
    OnPickup = nil
}

function Config.GetText(key)
    local locale = Config.Locales[Config.Locale] or Config.Locales.en
    return locale[key] or key
end

function Config.GetItemLabel(name)
    local entry = Config.Placeables[name]
    if not entry then return name end

    if type(entry.locale) == 'table' then
        return entry.locale[Config.Locale] or entry.locale.en or name
    end

    return entry.label or name
end
