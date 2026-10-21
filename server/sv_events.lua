--- Callbacks für die Spielwelt (Menüs ohne Papa OS, Kunden, Abholung, Probefahrt). Alle Prüfungen laufen hier
--- auf dem Server; der Client zeigt nur an.

VS = VS or {}

local U = VS.U
local A = VS.Access

local lastCall = {} -- src -> GetGameTimer()

local function guard(src)
    local now = GetGameTimer()
    if lastCall[src] and now - lastCall[src] < 250 then
        return false
    end
    lastCall[src] = now
    return true
end

local function result(value, err)
    if value == nil or value == false then
        local code = tostring(err or "unknown")
        if type(TR("err_" .. code)) ~= "string" then
            code = "unknown"
        end
        return { ok = false, error = code, message = T("err_" .. code) }
    end
    return { ok = true, data = value }
end

--- Registers a callback that receives the actor. fn(actor, ...) -> value, err
local function register(name, fn, noGuard)
    lib.callback.register("papa_vehicleshop:" .. name, function(src, ...)
        if not noGuard and not guard(src) then
            return { ok = false, error = "rate_limited", message = T("err_rate_limited") }
        end
        if not VS.Db.ready then
            return result(nil, "db_not_ready")
        end
        local actor = A.actor(src)
        if not actor then
            return result(nil, "no_player")
        end
        return result(fn(actor, ...))
    end)
end

AddEventHandler("playerDropped", function()
    lastCall[source] = nil
end)

-- Same RPC as the Papa OS app, used by the menus without Papa OS -------------------------

lib.callback.register("papa_vehicleshop:rpc", function(src, data)
    if not guard(src) then
        return { ok = false, error = "rate_limited", message = T("err_rate_limited") }
    end
    return VS.Rpc.dispatch(src, data)
end)

--- Which shops the player works in and whether the player is admin (for client menus).
register("whoami", function(actor)
    local list = {}
    for _, shop in ipairs(A.shopsOf(actor)) do
        list[#list + 1] = { id = shop.id, label = shop.label, flags = A.flags(actor, shop) }
    end
    return { id = actor.id, name = actor.name, shops = list, isAdmin = actor.isAdmin }
end, true)

-- Customers -----------------------------------------------------------------------------

register("buyDisplay", function(actor, displayId, opts)
    return VS.Sales.buyDisplay(actor, displayId, opts)
end)

register("npcCatalog", function(actor, shopId)
    local shop = VS.Shops.get(shopId)
    if not shop then
        return nil, "not_found"
    end
    if not VS.Shops.npcActive(shop) then
        return nil, "npc_not_available"
    end
    return {
        shop = { id = shop.id, label = shop.label, currency = shop.settings.currency, finance = shop.settings.finance.enabled },
        vehicles = VS.Sales.npcCatalog(shop),
        methods = Config.purchase.methods,
        customPlate = Config.purchase.customPlate,
    }
end)

register("buyCatalog", function(actor, shopId, model, opts)
    local shop = VS.Shops.get(shopId)
    if not shop then
        return nil, "not_found"
    end
    local npc = shop.points.npc
    local ped = GetPlayerPed(actor.src)
    if not npc or ped == 0 or #(GetEntityCoords(ped) - vector3(npc.x, npc.y, npc.z)) > 15.0 then
        -- Showcase purchases go through buyDisplay; the catalog needs the NPC
        return nil, "too_far"
    end
    return VS.Sales.buyCatalog(actor, shop, model, opts)
end)

register("financePlan", function(actor, shopId, price)
    local shop = VS.Shops.get(shopId)
    if not shop then
        return nil, "not_found"
    end
    return VS.Finance.plan(shop, price)
end)

register("myOrders", function(actor)
    local list = VS.Sales.ordersOf(actor.id)
    for _, o in ipairs(list) do
        local shop = VS.Shops.get(o.shopId)
        o.shopLabel = shop and shop.label or "-"
    end
    return list
end, true)

register("collectOrder", function(actor, orderId)
    return VS.Sales.collectOrder(actor, orderId)
end)

register("myFinances", function(actor)
    return VS.Finance.forBuyer(actor.id)
end, true)

register("payOff", function(actor, financeId, payWith)
    return VS.Finance.payOff(actor, financeId, payWith)
end)

local staffCalls = {} -- src -> time

register("callStaff", function(actor, shopId)
    local shop = VS.Shops.get(shopId)
    if not shop or shop.type == "npc" then
        return nil, "not_found"
    end
    local now = GetGameTimer()
    if staffCalls[actor.src] and now - staffCalls[actor.src] < 120000 then
        return nil, "call_cooldown"
    end
    staffCalls[actor.src] = now
    local staff = A.onlineStaff(shop)
    if #staff == 0 then
        return nil, "no_staff_online"
    end
    VS.Notify.staff(shop, T("notify_customer_waiting", actor.name), "info")
    return { notified = #staff }
end)

register("answerOffer", function(actor, offerId, accept, method, payWith)
    return VS.Sales.answerOffer(actor, offerId, accept == true, method, payWith)
end)

register("tradeInRequest", function(actor, shopId, data)
    return VS.TradeIn.request(actor, shopId, data)
end)

register("tradeInAnswer", function(actor, tradeId, data)
    return VS.TradeIn.answer(actor, tradeId, data)
end)

-- Test drive ----------------------------------------------------------------------------

register("testDrive", function(actor, displayId, payWith)
    return VS.TestDrive.start(actor, displayId, payWith)
end)

RegisterNetEvent("papa_vehicleshop:server:testDriveSpawned", function(netId)
    VS.TestDrive.spawned(source, netId)
end)

register("testDriveFinish", function(actor, data)
    return VS.TestDrive.finish(actor.src, data)
end, true)

-- Logistics -----------------------------------------------------------------------------

register("pointMenu", function(actor, pointId)
    return VS.Logistics.pointMenu(actor, pointId)
end, true)

register("openContracts", function(actor)
    return { open = VS.Logistics.openContracts(nil), running = VS.Logistics.takenBy(actor.id) }
end, true)

register("acceptContract", function(actor, contractId)
    return VS.Logistics.acceptContract(actor, contractId)
end)

register("abandonContract", function(actor)
    return VS.Logistics.abandonContract(actor)
end)

register("pickup", function(actor, stockId)
    return VS.Logistics.pickup(actor, stockId)
end)

register("takeOut", function(actor, shopId, stockId)
    local shop = VS.Shops.get(shopId)
    if not shop or not A.can(actor, shop, "stockManage") then
        return nil, "no_permission"
    end
    return VS.Logistics.takeOut(actor, shop, stockId)
end)

RegisterNetEvent("papa_vehicleshop:server:vehicleSpawned", function(stockId, netId)
    local actor = A.actor(source)
    if actor then
        VS.Logistics.spawned(actor, tonumber(stockId), netId)
    end
end)

register("dropoff", function(actor, shopId, data)
    return VS.Logistics.dropoff(actor, shopId, data)
end)

register("displayFromWorld", function(actor, displayId, data)
    return VS.Logistics.displayFromWorld(actor, displayId, data)
end)

--- Stock vehicles of the shops the player works in that can go onto a display (for the menu at a spot).
register("displayCandidates", function(actor, displayId)
    local d = VS.Displays.get(displayId)
    if not d then
        return nil, "not_found"
    end
    local shop = VS.Shops.get(d.shopId)
    if not shop or not A.can(actor, shop, "displayManage") then
        return nil, "no_permission"
    end
    local out = {}
    for _, s in ipairs(VS.Stock.forShop(shop.id, { "storage" })) do
        if VS.typeAllowed(d.types, s.vtype) then
            out[#out + 1] = { id = s.id, label = s.label, plate = s.plate, price = s.price, vtype = s.vtype }
        end
    end
    local current = d.stockId and VS.Stock.get(d.stockId)
    return {
        shopId = shop.id,
        display = { id = d.id, label = d.label, types = d.types, kind = d.kind },
        current = current and VS.Stock.ACTIVE[current.status] and { id = current.id, label = current.label, plate = current.plate, price = current.price, status = current.status } or nil,
        candidates = out,
        currency = shop.settings.currency,
    }
end, true)
