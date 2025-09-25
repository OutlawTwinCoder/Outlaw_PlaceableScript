fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Outlaw_PlableScript'
author 'Outlaw — placeables without DB'
version '1.2.2'
description 'Camera-centered preview with pure camera-ray scrolling (no ped clamp), snap-to-ground.'

shared_scripts {
    'config.lua',
    'NativeProps/*.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@ox_lib/init.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target'
}
