fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Outlaw_Placeable'
author 'Outlaw Scripts'
version '2.0.0'
description 'Flexible placeable props with preview, trunk placement and persistence.'

files {
    'stream/*.ytyp',
    'stream/*.ydr'
}

data_file 'DLC_ITYP_REQUEST' 'stream/prop_bzzz_drugs_coke.ytyp'

shared_scripts {
    'config.lua',
    'locales/*.lua',
    'shared/*.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/persistence.lua',
    'server/trunk.lua',
    'server/inventory.lua',
    'server/main.lua'
}

dependencies {
    -- optional dependencies: ox_lib, ox_inventory, ox_target
}
