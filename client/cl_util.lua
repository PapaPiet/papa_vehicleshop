--- Client-Hilfen: Bridge, Modelle, Fahrzeuge, Menüs (papa_bridge), Callbacks, Hinweistexte.

VS = VS or {}
VS.U = VS.U or {}

PAPA = PAPA or exports["papa_bridge"]:getObjects()

local U = VS.U

--- Public world state from the server.
VS.world = VS.world or { shops = {}, displays = {}, points = {}, boards = {} }

function U.debug(...)
    if Config.Debug then
        print("^5[papa_vehicleshop]^0", ...)
    end
end

function U.notify(text, kind, duration)
    PAPA.Functions.Notify(text, duration or 5000, kind or "info")
end

function U.money(amount, currency)
    local n = math.floor((tonumber(amount) or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if out:sub(1, 1) == "." then
        out = out:sub(2)
    end
    return (n < 0 and "-" or "") .. out .. " " .. (currency or Config.shopDefaults.currency or "$")
end

function U.minutes(minutes)
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes >= 60 then
        local h = math.floor(minutes / 60)
        local m = minutes % 60
        if m == 0 then
            return T("time_hours", h)
        end
        return T("time_hours_minutes", h, m)
    end
    return T("time_minutes", minutes)
end

--- Server callback with error notification. Returns data or nil.
function U.call(name, ...)
    local res = lib.callback.await("papa_vehicleshop:" .. name, false, ...)
    if type(res) ~= "table" then
        U.notify(T("err_unknown"), "error")
        return nil
    end
    if not res.ok then
        U.notify(res.message or T("err_unknown"), "error")
        return nil
    end
    return res.data == nil and true or res.data
end

--- Same RPC as the Papa OS app (menus without Papa OS).
function U.rpc(action, payload)
    local body = payload or {}
    body.action = action
    local res = lib.callback.await("papa_vehicleshop:rpc", false, body)
    if type(res) ~= "table" then
        U.notify(T("err_unknown"), "error")
        return nil
    end
    if not res.ok then
        U.notify(res.message or T("err_unknown"), "error")
        return nil
    end
    return res.data == nil and true or res.data
end

-- Models and vehicles -----------------------------------------------------------------------

function U.loadModel(model)
    local hash = type(model) == "number" and model or joaat(model)
    if not IsModelInCdimage(hash) then
        return nil
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            return nil
        end
        Wait(10)
    end
    return hash
end

function U.modelExists(model)
    local hash = type(model) == "number" and model or joaat(model)
    return IsModelInCdimage(hash) and IsModelValid(hash)
end

--- Display name of a model ("Adder").
function U.modelLabel(model)
    local hash = type(model) == "number" and model or joaat(model)
    local display = GetDisplayNameFromVehicleModel(hash)
    local label = GetLabelText(display)
    if not label or label == "NULL" or label == "" then
        return display
    end
    return label
end

--- Spawn name of a vehicle entity (best effort: catalog lookup by hash, else display name).
function U.modelName(vehicle)
    local hash = GetEntityModel(vehicle)
    for _, d in pairs(VS.world.displays) do
        local v = d.vehicle or d.showcase
        if v and joaat(v.model) == hash then
            return v.model
        end
    end
    return GetDisplayNameFromVehicleModel(hash):lower()
end

function U.vehicleType(vehicle)
    return VS.typeFromClass(GetVehicleClass(vehicle))
end

function U.plate(vehicle)
    return (GetVehicleNumberPlateText(vehicle) or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

function U.getProps(vehicle)
    return lib.getVehicleProperties(vehicle) or {}
end

function U.condition(vehicle)
    return {
        engine = math.floor(GetVehicleEngineHealth(vehicle)),
        body = math.floor(GetVehicleBodyHealth(vehicle)),
        fuel = math.floor(GetVehicleFuelLevel(vehicle)),
        dirt = GetVehicleDirtLevel(vehicle),
        tank = math.floor(GetVehiclePetrolTankHealth(vehicle)),
    }
end

--- Applies props and the stored condition (damage stays visible).
function U.applyProps(vehicle, props, condition, plate)
    if type(props) == "table" and next(props) then
        lib.setVehicleProperties(vehicle, props)
    end
    if plate and plate ~= "" then
        SetVehicleNumberPlateText(vehicle, plate)
    end
    if type(condition) == "table" then
        if condition.engine then
            SetVehicleEngineHealth(vehicle, condition.engine + 0.0)
        end
        if condition.body then
            SetVehicleBodyHealth(vehicle, condition.body + 0.0)
        end
        if condition.tank then
            SetVehiclePetrolTankHealth(vehicle, condition.tank + 0.0)
        end
        if condition.dirt then
            SetVehicleDirtLevel(vehicle, condition.dirt + 0.0)
        end
        if condition.fuel then
            PAPA.Functions.setFuel(vehicle, condition.fuel + 0.0)
        end
    end
end

--- Spawns a vehicle. networked = true for vehicles players drive.
function U.spawnVehicle(model, coords, props, condition, plate, networked)
    local hash = U.loadModel(model)
    if not hash then
        U.notify(T("err_model_missing", tostring(model)), "error")
        return nil
    end
    local veh = CreateVehicle(hash, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, (coords.w or coords.h or 0.0) + 0.0, networked == true, false)
    if veh == 0 then
        return nil
    end
    SetModelAsNoLongerNeeded(hash)
    SetVehicleOnGroundProperly(veh)
    if networked then
        local deadline = GetGameTimer() + 3000
        while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < deadline do
            NetworkRegisterEntityAsNetworked(veh)
            Wait(0)
        end
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleHasBeenOwnedByPlayer(veh, true)
    end
    U.applyProps(veh, props, condition, plate)
    return veh
end

--- Spawns a drivable vehicle for the player, warps him in, gives keys. Returns entity, netId.
function U.spawnForPlayer(model, coords, props, condition, plate)
    local veh = U.spawnVehicle(model, coords, props, condition, plate, true)
    if not veh then
        return nil
    end
    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
    PAPA.Functions.giveVehicleKeys(veh)
    return veh, NetworkGetNetworkIdFromEntity(veh)
end

--- Removes a vehicle the player drives (after storing it).
function U.removeVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == vehicle then
        TaskLeaveVehicle(ped, vehicle, 0)
        local deadline = GetGameTimer() + 3000
        while IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < deadline do
            Wait(50)
        end
    end
    PAPA.Functions.removeVehicleKeys(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
end

--- Vehicle data sent to the server (store, display, trade-in).
function U.vehicleData(vehicle)
    return {
        plate = U.plate(vehicle),
        model = U.modelName(vehicle),
        label = U.modelLabel(GetEntityModel(vehicle)),
        vtype = U.vehicleType(vehicle),
        props = U.getProps(vehicle),
        condition = U.condition(vehicle),
        netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil,
    }
end

--- Current player position (vector4), vehicle position when sitting in one.
function U.myPosition()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = veh ~= 0 and veh or ped
    local c = GetEntityCoords(ent)
    local z = c.z
    if veh == 0 then
        z = z - 1.0
    end
    return { x = c.x, y = c.y, z = z, w = GetEntityHeading(ent) }, veh ~= 0 and veh or nil
end

-- Help text and keys ------------------------------------------------------------------------

local interactKey = nil

function U.keyId()
    if not interactKey then
        interactKey = PAPA.Functions.ConvertKeyToId(Config.interactKey) or 38
    end
    return interactKey
end

function U.help(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function U.pressed()
    return IsControlJustReleased(0, U.keyId())
end

function U.drawText2D(text, x, y, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.45, scale or 0.45)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

-- Menus (papa_bridge) -----------------------------------------------------------------------

local menuCounter = 0

--- Opens a list menu. options: { label, description, icon, args, disabled, values, defaultIndex }
--- onPick(args, scrollIndex) on confirm, onBack() on ESC.
function U.menu(title, options, onPick, onBack)
    menuCounter = menuCounter + 1
    local id = ("papa_vs_menu_%d"):format(menuCounter)
    if #options == 0 then
        options = { { label = T("menu_empty"), disabled = true, args = { empty = true } } }
    end
    PAPA.Functions.addMenu(id, title, options, nil, nil, function(selected, scrollIndex, args)
        local opt = options[selected]
        if opt and opt.disabled then
            return
        end
        if onPick then
            onPick(args or (opt and opt.args) or {}, scrollIndex, selected)
        end
    end, function()
        if onBack then
            onBack()
        end
    end)
    PAPA.Functions.showMenu(id)
end

function U.input(title, rows)
    return PAPA.Functions.inputDialog(title, rows)
end

function U.confirm(header, content)
    return PAPA.Functions.alertDialog({ header = header, content = content, centered = true, cancel = true }) == "confirm"
end

--- Choice of payment method. Returns "bank" | "cash" | nil.
function U.choosePayment(methods, title)
    local options = {}
    for _, m in ipairs(methods or Config.purchase.methods) do
        if m ~= "finance" then
            options[#options + 1] = { label = T("method_" .. m), icon = m == "cash" and "money-bill" or "building-columns", args = { method = m } }
        end
    end
    local p = promise.new()
    U.menu(title or T("menu_payment"), options, function(args)
        p:resolve(args.method)
    end, function()
        p:resolve(nil)
    end)
    return Citizen.Await(p)
end

-- World state from the server -----------------------------------------------------------------

function VS.shop(id)
    return VS.world.shops[tonumber(id) or -1]
end

RegisterNetEvent("papa_vehicleshop:client:sync", function(data)
    local shops, displays = {}, {}
    for _, s in ipairs(data.shops or {}) do
        shops[s.id] = s
    end
    for _, d in ipairs(data.displays or {}) do
        displays[d.id] = d
    end
    VS.world.shops = shops
    VS.world.displays = displays
    VS.world.points = data.points or {}
    VS.world.boards = data.boards or {}
    TriggerEvent("papa_vehicleshop:client:worldChanged", "all")
end)

RegisterNetEvent("papa_vehicleshop:client:shop", function(s)
    VS.world.shops[s.id] = s
    TriggerEvent("papa_vehicleshop:client:worldChanged", "shop", s.id)
end)

RegisterNetEvent("papa_vehicleshop:client:removeShop", function(id)
    VS.world.shops[id] = nil
    for did, d in pairs(VS.world.displays) do
        if d.shopId == id then
            VS.world.displays[did] = nil
            TriggerEvent("papa_vehicleshop:client:worldChanged", "display", did)
        end
    end
    TriggerEvent("papa_vehicleshop:client:worldChanged", "shop", id)
end)

RegisterNetEvent("papa_vehicleshop:client:display", function(d)
    VS.world.displays[d.id] = d
    TriggerEvent("papa_vehicleshop:client:worldChanged", "display", d.id)
end)

RegisterNetEvent("papa_vehicleshop:client:removeDisplay", function(id)
    VS.world.displays[id] = nil
    TriggerEvent("papa_vehicleshop:client:worldChanged", "display", id)
end)

RegisterNetEvent("papa_vehicleshop:client:points", function(list)
    VS.world.points = list or {}
    TriggerEvent("papa_vehicleshop:client:worldChanged", "points")
end)

-- Who am I (shops I work in, admin) ---------------------------------------------------------

VS.me = { shops = {}, isAdmin = false, loaded = false }

function VS.refreshMe()
    local res = lib.callback.await("papa_vehicleshop:whoami", false)
    if type(res) == "table" and res.ok and res.data then
        VS.me = res.data
        VS.me.loaded = true
        VS.me.byShop = {}
        for _, s in ipairs(VS.me.shops or {}) do
            VS.me.byShop[s.id] = s
        end
    end
    return VS.me
end

function VS.isStaff(shopId)
    return VS.me.byShop ~= nil and VS.me.byShop[shopId] ~= nil
end

function VS.can(shopId, key)
    local s = VS.me.byShop and VS.me.byShop[shopId]
    return s ~= nil and s.flags ~= nil and s.flags[key] == true
end

local function onReady()
    TriggerServerEvent("papa_vehicleshop:server:requestSync")
    VS.refreshMe()
end

AddEventHandler("papa_bridge:c:playerHasLoaded", function(ok)
    if ok then
        onReady()
    end
end)

RegisterNetEvent("papa_bridge:c:jobChanged", function()
    VS.refreshMe()
end)

local refreshQueued = false

AddEventHandler("papa_vehicleshop:client:worldChanged", function(kind)
    if (kind == "shop" or kind == "all") and not refreshQueued then
        -- Job/owner of a shop can change: refresh my permissions in the background (at most every 5 s)
        refreshQueued = true
        SetTimeout(5000, function()
            refreshQueued = false
            VS.refreshMe()
        end)
    end
end)

CreateThread(function()
    -- Resource restart while the player is already in the game
    Wait(1500)
    if PAPA.Functions.hasPlayerSpawned() then
        onReady()
    end
end)
