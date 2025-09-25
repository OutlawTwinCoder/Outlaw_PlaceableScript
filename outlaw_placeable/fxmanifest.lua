fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

name 'outlaw_placeable'
version '1.0.0'
description 'Placeable props with preview and physics settle'
author 'Outlaw Scripts'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/utils_raycast.lua',
    'client/utils_physics.lua',
    'client/placeable.lua'
}

server_scripts {
    'server/placeable.lua'
}

escrow_ignore {
    'stream/*.ydr'
}

dependencies {
    'ox_lib',
    'ox_inventory'
}

data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'

files {
    'stream/*.ytyp'
}

client_exports {
    'placeable_item'
}
