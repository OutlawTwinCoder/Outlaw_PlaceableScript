Config = {}

Config.Locale = 'fr'

Config.Distances = {
    min = 0.6,
    max = 8.5,
    trunkMax = 2.5,
    minFromPed = 1.0
}

Config.Preview = {
    mode = 'camera',
    rotateStep = 5.0,
    rotateSnap = 90.0,
    distanceStep = 0.25,
    alphaValid = 190,
    alphaInvalid = 120
}

Config.Controls = {
    confirm = 24,         -- Mouse1
    cancel = 25,          -- Mouse2
    rotateLeft = 44,      -- Q
    rotateRight = 38,     -- E
    rotateSnap = 45,      -- R
    toggleDrop = 47,      -- G
    distIncrease = 241,   -- Wheel up
    distDecrease = 242,   -- Wheel down
    collect = 38          -- E
}

Config.MakeEverythingPlaceable = {
    enabled = false,
    fallbackModel = 'prop_tool_box_04a'
}

Config.AntiStacking = {
    enabled = true,
    minSeparation = 0.35,
    heightTolerance = 0.6
}

Config.FreezePlacedObjects = true

Config.Persistence = {
    enabled = false,
    default = false -- force persistence only for items flagged persistent
}

Config.InventoryProvider = 'ox' -- 'ox', 'qs', 'qb', 'standalone'

Config.Trunk = {
    enabled = true,
    defaultCapacity = 6,
    classCapacity = {
        [0] = 4, -- compact
        [1] = 6, -- sedan
        [2] = 6, -- suv
        [3] = 8, -- coupe
        [4] = 6, -- muscle
        [5] = 3, -- sports classic
        [6] = 3, -- sports
        [7] = 2, -- super
        [8] = 2, -- motorcycle
        [9] = 3, -- offroad
        [10] = 5, -- industrial
        [11] = 6, -- utility
        [12] = 5, -- van
        [13] = 2, -- cycles
        [14] = 4, -- boats
        [15] = 4, -- heli
        [16] = 8, -- plane
        [17] = 4, -- service
        [18] = 6, -- emergency
        [19] = 4, -- military
        [20] = 8, -- commercial
        [21] = 4  -- train
    },
    attachBones = {
        'boot', 'boot_dummy', 'seat_dside_f', 'seat_pside_f'
    }
}

Config.Items = {
    coke2 = {
        label = 'Paquet de coke',
        models = {
            'prop_bzzz_drugs_coke001',
            'prop_bzzz_drugs_coke002',
            'prop_bzzz_drugs_coke003'
        },
        icon = 'fa-solid fa-box',
        allowDrop = true,
        allowThrow = true,
        allowTrunk = true,
        persistent = true,
        interactDistance = 2.0,
        trunkSize = { x = 0.6, y = 0.4, z = 0.3 }
    }
}

Config.AttachmentBreak = {
    enabled = true,
    checkInterval = 300,
    minCollisionSpeed = 12.0,
    minSpeedDelta = 6.0,
    requireCollision = true,
    pitchLimit = 65.0,
    rollLimit = 80.0,
    upsideDownTime = 800
}

Config.HelpText = true

Config.Target = {
    enabled = true,
    resource = 'ox_target'
}

Config.Commands = {
    place = 'place',
    cancel = 'place_cancel',
    removeNear = 'place_remove_near',
    cleanupAll = 'place_cleanup_all'
}

Config.Security = {
    allowStaffRemoveAll = true,
    staffAce = 'command.place_cleanup_all'
}
