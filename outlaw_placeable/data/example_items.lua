local exampleItems = {
    placeable_crate = {
        label = 'Utility Crate',
        weight = 1000,
        stack = false,
        description = 'Example placeable crate. Use to preview and place a crate prop.',
        client = {
            export = 'outlaw_placeable.placeable_item',
            buttons = {
                {
                    label = 'Place',
                    action = function(slot)
                        if slot then
                            exports.ox_inventory:useItem(slot)
                        end
                    end
                }
            }
        }
    },
    placeable_cone = {
        label = 'Road Cone',
        weight = 200,
        stack = true,
        description = 'Placeable road cone with rotation preview.',
        client = {
            export = 'outlaw_placeable.placeable_item'
        }
    }
}

return exampleItems
