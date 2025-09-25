-- config.lua
Config = {}

-- Distances
Config.MaxPlacementDistance = 8.0
Config.MinPlacementDistance = 0.8
Config.MinDistanceFromPed  = 1.0      -- utilisé seulement en mode 'ped'
Config.ForwardBiasMeters   = 5.0      -- pousse un peu plus en avant (caméra)

-- Rotation par pas (en degrés) avec Q/E
Config.RotateStep = 5.0

-- Geler l'objet après la pose
Config.FreezePlacedObjects = true

-- Mode d'aperçu: 'camera' = centre de la caméra (souris), 'ped' = devant le joueur
Config.PreviewForward = 'camera'  -- on pilote à la souris

-- Molette de distance
Config.DistanceScroll = true

-- Configuration globale pour le comportement des objets attachés aux entités (ex: véhicules)
Config.AttachmentBreak = {
    enabled = true,          -- mettre false pour désactiver complètement la logique de détachement
    checkInterval = 300,     -- intervalle (ms) entre deux vérifications
    minCollisionSpeed = 12.0,-- vitesse (m/s) minimale avant de considérer un choc
    minSpeedDelta = 6.0,     -- variation de vitesse requise pour détacher après un choc
    minVectorSpeedDelta = 8.0,-- variation vectorielle (changement de direction) minimale avant détachement
    requireCollision = true, -- nécessite HasEntityCollidedWithAnything avant de détacher sur variation de vitesse
    pitchLimit = 65.0,       -- angle (°) de tangage maximum avant détachement
    rollLimit = 80.0,        -- angle (°) de roulis maximum avant détachement
    upsideDownTime = 800,    -- durée (ms) à l'envers avant détachement
}

-- Touches
Config.Controls = {
    confirm = 24,       -- LMB
    cancel = 25,        -- RMB
    rotateLeft = 44,    -- Q
    rotateRight = 38,   -- E
    distIncrease = 241, -- MWUP
    distDecrease = 242, -- MWDOWN
    pickup = 38         -- E
}

-- Items plaçables
Config.Placeables = {
    coke2 = {
        label = 'Paquet de coke',
        models = {
            'prop_bzzz_drugs_coke001',
            'prop_bzzz_drugs_coke002',
            'prop_bzzz_drugs_coke003'
        },
        icon = 'fa-solid fa-box',
        interactDistance = 2.0,
        pickupLabel = 'Ramasser le paquet',
    },
}

-- Les props natifs supplémentaires peuvent être déclarés dans NativeProps/*.lua
