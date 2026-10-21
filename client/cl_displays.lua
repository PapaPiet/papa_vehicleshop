--- Ausstellungsplätze: Fahrzeuge werden je Client lokal erzeugt (nicht vernetzt), mit allen gespeicherten
--- Eigenschaften und Schäden, abgeschlossen und eingefroren. Daneben das Preisschild mit Bildschirm.

VS = VS or {}

local U = VS.U
local Sg = VS.Sign

local spawned = {} -- displayId -> { vehicle, sign, key, heading }

local function damagePercent(condition)
    if type(condition) ~= "table" then
        return 0
    end
    local engine = 1 - (tonumber(condition.engine) or 1000) / 1000
    local body = 1 - (tonumber(condition.body) or 1000) / 1000
    return math.max(0, math.min(100, math.floor(math.max(engine, body) * 100 + 0.5)))
end

--- What should stand on the spot: { model, props, condition, plate } or nil.
local function wanted(d)
    if d.vehicle and d.vehicle.status ~= "testdrive" then
        return {
            model = d.vehicle.model,
            props = d.vehicle.props,
            condition = d.vehicle.condition,
            plate = d.vehicle.plate,
            key = ("s%d:%s:%s"):format(d.vehicle.stockId, d.vehicle.plate or "", json.encode(d.vehicle.condition or {})),
        }
    elseif d.showcase then
        local color = d.showcase.color
        return {
            model = d.showcase.model,
            props = color and { color1 = color, color2 = color } or nil,
            plate = "PAPA",
            key = ("c:%s:%s"):format(d.showcase.model, tostring(color)),
        }
    end
    return nil
end

local function signPayload(d)
    local shop = VS.shop(d.shopId)
    local currency = shop and shop.currency or Config.shopDefaults.currency
    local base = { shop = shop and shop.label or "", currency = currency, spot = d.label }
    if d.vehicle then
        local v = d.vehicle
        base.kind = "stock"
        base.label = v.label
        base.brand = v.brand
        base.price = v.price
        base.priceText = v.price > 0 and U.money(v.price, currency) or nil
        base.plate = v.plate
        base.vtype = v.vtype
        base.status = v.reserved and v.status == "display" and "reserved" or v.status
        base.note = v.note
        base.damage = damagePercent(v.condition)
        base.fuel = v.condition and v.condition.fuel or nil
        base.testDrive = shop and shop.testDrive or false
        base.finance = shop and shop.finance or false
    elseif d.showcase then
        local c = d.showcase
        base.kind = "showcase"
        base.label = c.label
        base.brand = c.brand
        base.price = c.price
        base.priceText = U.money(c.price, currency)
        base.vtype = c.vtype
        base.minutes = c.minutes
        base.deliveryText = c.minutes and c.minutes > 0 and U.minutes(c.minutes) or nil
        base.available = c.available
        base.finance = shop and shop.finance or false
    else
        base.kind = "empty"
    end
    return base
end

-- Spawning ----------------------------------------------------------------------------------

local function addVehicleTarget(displayId, vehicle)
    if not Config.useTarget then
        return
    end
    PAPA.Target.addLocalEntity(vehicle, {
        {
            name = "papa_vs_view",
            label = T("target_view_vehicle"),
            icon = "fas fa-car",
            distance = 3.5,
            onSelect = function()
                VS.openDisplayMenu(displayId)
            end,
        },
        {
            name = "papa_vs_manage_spot",
            label = T("target_manage_spot"),
            icon = "fas fa-screwdriver-wrench",
            distance = 3.5,
            canInteract = function()
                local d = VS.world.displays[displayId]
                return d ~= nil and VS.can(d.shopId, "displayManage")
            end,
            onSelect = function()
                VS.openDisplayStaffMenu(displayId)
            end,
        },
    }, 3.5)
end

local function despawnVehicle(entry)
    if entry.vehicle and DoesEntityExist(entry.vehicle) then
        if Config.useTarget then
            PAPA.Target.deleteLocalEntity(entry.vehicle)
        end
        DeleteEntity(entry.vehicle)
    end
    entry.vehicle = nil
    entry.key = nil
end

local function spawnVehicle(d, entry, want)
    local hash = U.loadModel(want.model)
    if not hash then
        return
    end
    local veh = CreateVehicle(hash, d.x, d.y, d.z, d.h, false, false)
    SetModelAsNoLongerNeeded(hash)
    if veh == 0 then
        return
    end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    U.applyProps(veh, want.props, want.condition, want.plate)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleCanBreak(veh, false)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    if Config.display.locked then
        SetVehicleDoorsLocked(veh, 2)
    end
    SetVehicleDirtLevel(veh, want.condition and tonumber(want.condition.dirt) or 0.0)
    entry.vehicle = veh
    entry.key = want.key
    entry.heading = d.h
    addVehicleTarget(d.id, veh)
end

local function despawn(id)
    local entry = spawned[id]
    if not entry then
        return
    end
    despawnVehicle(entry)
    Sg.despawn(entry.sign)
    Sg.release(id)
    spawned[id] = nil
end

local function syncDisplay(d, entry)
    local want = wanted(d)
    if not want then
        despawnVehicle(entry)
    elseif entry.key ~= want.key or not (entry.vehicle and DoesEntityExist(entry.vehicle)) then
        despawnVehicle(entry)
        spawnVehicle(d, entry, want)
    end
    local signKey = json.encode(d.sign or {}) .. d.x .. d.y .. d.h
    if Config.sign.enabled and d.sign and d.sign.enabled and (d.vehicle or d.showcase) then
        if entry.signKey ~= signKey then
            Sg.despawn(entry.sign)
            entry.sign = Sg.spawn(d)
            entry.signKey = signKey
        end
    elseif entry.sign then
        Sg.despawn(entry.sign)
        entry.sign = nil
        entry.signKey = nil
        Sg.release(d.id)
    end
end

AddEventHandler("papa_vehicleshop:client:worldChanged", function(kind, id)
    if kind == "display" then
        local d = VS.world.displays[id]
        if not d then
            despawn(id)
        elseif spawned[id] then
            -- Position changed: rebuild everything on the spot
            if spawned[id].pos and (spawned[id].pos.x ~= d.x or spawned[id].pos.y ~= d.y or spawned[id].pos.z ~= d.z or spawned[id].h ~= d.h) then
                despawn(id)
            else
                syncDisplay(d, spawned[id])
            end
        end
    elseif kind == "all" then
        for did in pairs(spawned) do
            despawn(did)
        end
    end
end)

-- Main loop ---------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local candidates = {}
        for id, d in pairs(VS.world.displays) do
            local dist = #(pos - vector3(d.x, d.y, d.z))
            if dist < Config.renderDistance then
                local entry = spawned[id]
                if not entry then
                    entry = { pos = vector3(d.x, d.y, d.z), h = d.h }
                    spawned[id] = entry
                end
                syncDisplay(d, entry)
                if entry.sign and dist < Config.signDistance then
                    candidates[#candidates + 1] = { id = id, dist = dist }
                end
            elseif dist > Config.renderDistance + 10.0 and spawned[id] then
                despawn(id)
            end
        end
        -- Screens for the nearest signs only
        table.sort(candidates, function(a, b)
            return a.dist < b.dist
        end)
        local keep = {}
        for i = 1, math.min(#candidates, Config.maxActiveSigns or 6) do
            keep[candidates[i].id] = true
        end
        for id in pairs(Sg.activeIds()) do
            if not keep[id] then
                Sg.release(id)
            end
        end
        for id in pairs(keep) do
            if Sg.ensureDui(id) then
                Sg.update(id, signPayload(VS.world.displays[id]))
            end
        end
        Wait(500)
    end
end)

--- Per frame: signs, turntables, help texts without target, drive-on display for staff.
CreateThread(function()
    while true do
        local active = Sg.activeIds()
        local any = next(active) ~= nil
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local inVeh = GetVehiclePedIsIn(ped, false)
        local nearDisplay, nearDist = nil, 999.0
        for id, entry in pairs(spawned) do
            local d = VS.world.displays[id]
            if d then
                if active[id] and entry.sign then
                    Sg.draw(id, entry.sign)
                end
                if d.turntable and entry.vehicle then
                    entry.heading = (entry.heading + (Config.display.turntableSpeed or 0.15)) % 360.0
                    SetEntityHeading(entry.vehicle, entry.heading)
                end
                local dist = #(pos - vector3(d.x, d.y, d.z))
                if dist < nearDist then
                    nearDisplay, nearDist = d, dist
                end
            end
        end
        if nearDisplay and nearDist < 4.0 then
            any = true
            local d = nearDisplay
            if inVeh ~= 0 then
                if not d.vehicle and d.kind == "stock" and VS.can(d.shopId, "displayManage") and GetPedInVehicleSeat(inVeh, -1) == ped then
                    U.help(T("help_display_here", Config.interactKey))
                    if U.pressed() then
                        VS.displayVehicleHere(d.id, inVeh)
                    end
                end
            elseif not Config.useTarget and nearDist < 3.5 then
                if d.vehicle or d.showcase then
                    U.help(T("help_view_vehicle", Config.interactKey))
                    if U.pressed() then
                        VS.openDisplayMenu(d.id)
                    end
                elseif VS.can(d.shopId, "displayManage") then
                    U.help(T("help_manage_spot", Config.interactKey))
                    if U.pressed() then
                        VS.openDisplayStaffMenu(d.id)
                    end
                end
            elseif Config.useTarget and not d.vehicle and not d.showcase and VS.can(d.shopId, "displayManage") and nearDist < 2.5 then
                U.help(T("help_manage_spot", Config.interactKey))
                if U.pressed() then
                    VS.openDisplayStaffMenu(d.id)
                end
            end
        end
        Wait(any and 0 or 300)
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then
        return
    end
    for id in pairs(spawned) do
        despawn(id)
    end
end)
