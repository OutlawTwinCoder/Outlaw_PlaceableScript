Config = {}

Config.Locale = 'en'
Config.Debug = false

Config.Distance = {
    min = 0.75,
    max = 8.5,
    minFromPed = 1.0,
    forwardBias = 0.3
}

Config.Preview = {
    mode = 'camera', -- camera | ped
    rotateStep = 5.0,
    snapAngle = 90.0,
    scrollStep = 0.2,
    allowDrop = true,
    allowThrow = true
}

Config.MakeEverythingPlaceable = {
    enabled = false,
    fallbackModel = `prop_tool_bench02`
}

Config.FreezePlacedObjects = true

Config.AntiStacking = {
    enabled = true,
    minSeparation = 0.35
}

Config.Throwing = {
    force = 7.5,
    upwardBias = 0.35
}

Config.Trunk = {
    enabled = true,
    cellPadding = 0.05,
    fallbackCapacity = 4,
    capacityByClass = {
        [0] = 2,  -- Compacts
        [1] = 3,  -- Sedans
        [2] = 4,  -- SUVs
        [3] = 4,  -- Coupes
        [4] = 4,  -- Muscle
        [5] = 3,  -- Sports Classics
        [6] = 3,  -- Sports
        [7] = 2,  -- Super
        [8] = 0,  -- Motorcycles
        [9] = 2,  -- Off-road
        [10] = 6, -- Industrial
        [11] = 6, -- Utility
        [12] = 6, -- Vans
        [17] = 6, -- Service
        [18] = 6, -- Emergency
        [20] = 6  -- Commercial
    }
}

Config.Persistence = {
    enabled = true,
    cleanupDays = 14
}

Config.InventoryProvider = 'ox' -- 'ox' | 'qs' | 'qb' | 'standalone'

Config.RateLimits = {
    placementCooldown = 1500,
    pickupCooldown = 1000
}

Config.Controls = {
    rotateLeft = 44,   -- Q
    rotateRight = 45,  -- E
    snap = 45,         -- R
    distanceIncrease = 15, -- Mouse wheel up
    distanceDecrease = 14, -- Mouse wheel down
    toggleDrop = 58,   -- G
    confirm = 38,      -- E
    cancel = 202       -- Backspace
}

Config.Testing = {
    command = 'place_testbatch',
    count = 50
}

Config.Placeables = {
    -- example item definition
    -- ['water'] = {
    --     model = `prop_ld_flow_bottle`,
    --     rotationOffset = vector3(0.0, 0.0, 0.0),
    --     allowDrop = true,
    --     allowThrow = true,
    --     persistent = false
    -- }
}

Config.BlacklistModels = {
    `prop_fnclink_03e`
}

Config.Target = {
    pickupDistance = 2.0,
    inspectDistance = 2.5
}

Config.Commands = {
    place = 'place',
    cancel = 'place_cancel',
    removeNear = 'place_remove_near',
    cleanupAll = 'place_cleanup_all'
}

Config.StaffPermissions = {
    cleanup = 'placeables.cleanup',
    removeAny = 'placeables.remove'
}

Config.Logging = {
    enabled = true,
    prefix = '[Outlaw_Placeable]'
}

return Config
