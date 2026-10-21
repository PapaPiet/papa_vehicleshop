fx_version 'cerulean'
game 'gta5'
lua54 'on'

name 'papa_vehicleshop'
author 'PapaPiet'
description 'Realistic vehicle shop system with Papa OS dealer dashboard (made by PapaPiet dont use without permission)'
version '1.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'papa_bridge',
}

-- FiveM prüft in `dependencies` keine Versionen, server/sv_dependency_check.lua meldet zu alte Abhängigkeiten.
papa_requires 'papa_bridge@1.6.14'

files {
    'icon.png',
    'html/sign.html',
    'ui/dist/index.html',
    'ui/dist/admin.html',
    'ui/dist/app.js',
    'ui/dist/admin.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'configs/config.lua',
    'configs/vehicles.lua',
    'locales/main.lua',
    'locales/translations/*.lua',
    'shared/sh_types.lua',
}

client_scripts {
    'client/cl_util.lua',
    'client/cl_world.lua',
    'client/cl_sign.lua',
    'client/cl_displays.lua',
    'client/cl_customer.lua',
    'client/cl_staff.lua',
    'client/cl_admin.lua',
    'client/cl_logistics.lua',
    'client/cl_testdrive.lua',
    'client/cl_nui.lua',
    'client/cl_debug_close_ui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_dependency_check.lua',
    'server/sv_util.lua',
    'server/sv_db.lua',
    'server/sv_catalog.lua',
    'server/sv_shops.lua',
    'server/sv_access.lua',
    'server/sv_account.lua',
    'server/sv_notify.lua',
    'server/sv_sync.lua',
    'server/sv_stock.lua',
    'server/sv_logistics.lua',
    'server/sv_sales.lua',
    'server/sv_finance.lua',
    'server/sv_tradein.lua',
    'server/sv_testdrive.lua',
    'server/sv_documents.lua',
    'server/sv_rpc.lua',
    'server/sv_events.lua',
    'server/sv_register.lua',
}
