--- Registrierung bei papa_os_core: Autohaus-Dashboard als App (für alle Jobs mit Autohaus) und der
--- Admin-Bereich "Autohäuser" im OS-Admin. Ohne papa_os_core passiert hier nichts.

local res = GetCurrentResourceName()
local U = VS.U

local function register()
    if Config.os.enabled == false then
        return true
    end
    if GetResourceState("papa_os_core") ~= "started" then
        return false
    end
    if not VS.Db.ready then
        return false
    end
    local core = U.core()
    local jobs = VS.Shops.jobs()
    core:RegisterEmbeddedComputerApp({
        id = Config.os.appId,
        name = T("app_name"),
        kind = "app",
        iconPath = Config.os.iconPath or "icon.png",
        allowedJobs = jobs,
        phone = Config.os.phone ~= false,
        defaultApp = Config.os.defaultApp == true,
        nuiEmbed = { resource = res, path = "ui/dist/index.html" },
    })
    core:RegisterEmbeddedAppConfig(Config.os.appId, {
        allowedJobs = jobs,
        appDescription = T("app_description"),
        storeCategory = Config.os.storeCategory or "work",
    })
    local panel = Config.os.adminPanel or {}
    if panel.enabled ~= false and U.coreHasExport("RegisterAdminPanel") then
        core:RegisterAdminPanel({
            id = panel.id or (res .. ":admin"),
            label = T("admin_panel_label"),
            icon = panel.icon or "car",
            path = "ui/dist/admin.html",
            group = panel.group or "manage",
            order = panel.order or 45,
            description = T("admin_panel_description"),
        })
    end
    TriggerClientEvent("papa_os_core:client:refreshBootApps", -1)
    return true
end

AddEventHandler("onResourceStart", function(started)
    if started == "papa_os_core" then
        SetTimeout(1000, register)
    end
end)

--- New shop or job change: the app must be visible for the new job.
AddEventHandler("papa_vehicleshop:server:shopsChanged", function()
    register()
end)

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    CreateThread(function()
        local deadline = GetGameTimer() + 60000
        while GetGameTimer() < deadline do
            if register() then
                return
            end
            Wait(500)
        end
        if Config.os.enabled ~= false then
            print(("^3[%s] %s^0"):format(res, T("console_core_missing")))
        end
    end)
end)
