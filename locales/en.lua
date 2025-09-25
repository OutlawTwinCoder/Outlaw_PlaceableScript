Locales = Locales or {}

Locales['en'] = {
    notify = {
        too_close = 'You are too close to place that.',
        out_of_range = 'You cannot reach that position.',
        stacking_blocked = 'Cannot place object: space is already occupied.',
        invalid_surface = 'This surface cannot hold that item.',
        trunk_full = 'The trunk is already at capacity.',
        no_item = 'You do not have that item.',
        placed = 'Item placed successfully.',
        pickup_denied = 'You cannot pick up this object.',
        picked_up = 'Item retrieved.',
        removed = 'Object removed.',
        rate_limited = 'Slow down!'
    },
    controls = 'Scroll: Distance | Q/E: Rotate | R: Snap | G: Drop/Throw | Enter: Confirm | Backspace: Cancel',
    commands = {
        usage_place = '/%s <itemName>',
        cleanup_done = 'All placeables have been cleaned up.'
    },
    target = {
        pickup = 'Pickup',
        inspect = 'Inspect',
        remove = 'Remove (Staff)'
    },
    menu = {
        title = 'Placeable',
        owner = 'Owner: %s',
        created = 'Placed: %s'
    }
}

return Locales['en']
