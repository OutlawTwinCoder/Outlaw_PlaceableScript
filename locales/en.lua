Locales = Locales or {}

Locales['en'] = {
    general = {
        resource = 'Placeable Items',
        no_model = 'This item cannot be placed because no prop model is configured.',
        invalid_item = 'You cannot place this item.',
        place_success = 'Item placed successfully.',
        remove_success = 'Item collected.',
        removing = 'Removing object...',
        press_collect = 'Press ~INPUT_PICKUP~ to collect'
    },
    validation = {
        too_far = 'You are too far away to place this object.',
        too_close = 'Move a little further away before placing this object.',
        stacking = 'Cannot place objects that close to each other.',
        trunk_full = 'This trunk is full.',
        trunk_only = 'This item can only be placed in a trunk.',
        invalid_surface = 'You cannot place this object here.',
        need_ground = 'Aim at a valid surface before placing.'
    },
    placement = {
        prompt = 'Use ~g~%s~s~ to confirm, ~r~%s~s~ to cancel.',
        drop_on = 'Drop mode enabled (object will remain dynamic).',
        drop_off = 'Drop mode disabled (object will be frozen).',
        trunk_slot = 'Slot %s/%s'
    },
    target = {
        collect = 'Collect',
        inspect = 'Inspect',
        remove = 'Remove (staff)'
    },
    inspect = {
        owner = 'Owner: %s',
        item = 'Item: %s'
    },
    commands = {
        missing_item = 'Usage: /place <item name>',
        unknown_item = 'Unknown item.',
        cancelled = 'Placement cancelled.',
        cleaned = 'All placeables removed.'
    }
}
