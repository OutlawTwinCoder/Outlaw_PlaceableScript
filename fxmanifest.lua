fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Outlaw_Placeable'
author 'Outlaw'
version '2.0.0'
description 'Advanced placeable items with preview, trunk handling, persistence and inventory integrations.'

files {
    'stream/*.ytyp',
    'stream/*.ydr',
    'sql/outlaw_placeable.sql'
}

data_file 'DLC_ITYP_REQUEST' 'stream/prop_bzzz_drugs_coke.ytyp'

shared_scripts {
    'config.lua',
    'locales/*.lua',
    'NativeProps/*.lua',
    'shared/locale.lua',
    'shared/inventory.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

optional_dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'qs-inventory',
    'qb-inventory'
}
