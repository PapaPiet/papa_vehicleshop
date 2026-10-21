--- Öffentlicher Weltzustand für alle Clients: Autohäuser (Punkte, Blip, NPC aktiv), Ausstellungsplätze mit
--- Fahrzeug und Preis, Lieferorte. Vollständig beim Beitritt, danach einzelne Änderungen.

VS = VS or {}
VS.Sync = VS.Sync or {}

local U = VS.U
local Sy = VS.Sync

local function publicShop(shop)
    local s = shop.settings
    return {
        id = shop.id,
        label = shop.label,
        type = shop.type,
        job = shop.job,
        ownerId = shop.ownerId,
        active = shop.active,
        points = shop.points,
        npcActive = VS.Shops.npcActive(shop),
        currency = s.currency,
        blip = s.blip,
        npcModel = s.npcModel,
        dropoffRadius = s.dropoffRadius,
        testDrive = s.testDrive.enabled,
        finance = s.finance.enabled,
        tradeIn = s.tradeIn.enabled,
    }
end

--- Price a customer pays for a showcase model in this shop right now.
function Sy.showcasePrice(shop, entry)
    if not entry then
        return 0
    end
    return VS.round(entry.price * VS.Shops.npcMultiplier(shop))
end

local function publicDisplay(d)
    local shop = VS.Shops.get(d.shopId)
    if not shop then
        return nil
    end
    local out = {
        id = d.id,
        shopId = d.shopId,
        label = d.label,
        x = d.x, y = d.y, z = d.z, h = d.h,
        types = d.types,
        sign = d.sign,
        kind = d.kind,
        turntable = d.turntable,
    }
    if d.kind == "stock" and d.stockId then
        local st = VS.Stock and VS.Stock.get(d.stockId)
        if st and (st.status == "display" or st.status == "testdrive" or st.status == "reserved") then
            local entry = VS.Catalog.get(st.model)
            out.vehicle = {
                stockId = st.id,
                model = st.model,
                label = st.label,
                brand = entry and entry.brand or "",
                plate = st.plate,
                vtype = st.vtype,
                props = st.props,
                condition = st.condition,
                price = st.price,
                status = st.status,
                note = st.note,
                reserved = st.reservedFor ~= nil,
            }
        end
    elseif d.kind == "showcase" and d.showcaseModel then
        local entry = VS.Catalog.get(d.showcaseModel)
        if entry and VS.Catalog.allowedForShop(shop, entry) then
            out.showcase = {
                model = entry.model,
                label = entry.label,
                brand = entry.brand,
                vtype = entry.vtype,
                price = Sy.showcasePrice(shop, entry),
                minutes = shop.settings.npcDelivery and VS.Catalog.minutes(entry) or 0,
                color = d.showcaseColor,
                available = VS.Shops.npcActive(shop),
            }
        end
    end
    return out
end

local function publicPoint(p)
    return {
        id = p.id,
        label = p.label,
        types = p.types,
        interact = p.interact,
        npc = p.npc,
        blip = p.blip,
        enabled = p.enabled,
    }
end

local function payload()
    local shops, displays, points = {}, {}, {}
    for _, shop in ipairs(VS.Shops.all()) do
        shops[#shops + 1] = publicShop(shop)
    end
    for _, d in ipairs(VS.Displays.all()) do
        local pd = publicDisplay(d)
        if pd then
            displays[#displays + 1] = pd
        end
    end
    for _, p in ipairs(VS.Points.all()) do
        points[#points + 1] = publicPoint(p)
    end
    return { shops = shops, displays = displays, points = points, boards = Config.contracts.boards or {} }
end

function Sy.full(target)
    if not VS.Db.ready then
        return
    end
    TriggerLatentClientEvent("papa_vehicleshop:client:sync", target or -1, 200000, payload())
end

function Sy.shop(shopId)
    local shop = VS.Shops.get(shopId)
    if not shop then
        return
    end
    TriggerClientEvent("papa_vehicleshop:client:shop", -1, publicShop(shop))
    -- Showcase prices depend on the NPC state of the shop
    for _, d in ipairs(VS.Displays.forShop(shop.id)) do
        if d.kind == "showcase" then
            Sy.display(d.id)
        end
    end
end

function Sy.removeShop(shopId)
    TriggerClientEvent("papa_vehicleshop:client:removeShop", -1, shopId)
end

function Sy.display(displayId)
    local d = VS.Displays.get(displayId)
    if not d then
        return
    end
    local pd = publicDisplay(d)
    if pd then
        TriggerClientEvent("papa_vehicleshop:client:display", -1, pd)
    end
end

function Sy.removeDisplay(displayId)
    TriggerClientEvent("papa_vehicleshop:client:removeDisplay", -1, displayId)
end

function Sy.points()
    local list = {}
    for _, p in ipairs(VS.Points.all()) do
        list[#list + 1] = publicPoint(p)
    end
    TriggerClientEvent("papa_vehicleshop:client:points", -1, list)
end

--- Tells open dashboards of the shop to refresh (balance, lists).
function Sy.balance(shop)
    for _, src in ipairs(VS.Access.onlineStaff(shop)) do
        TriggerClientEvent("papa_vehicleshop:client:shopChanged", src, shop.id)
    end
end

Sy.changed = Sy.balance

RegisterNetEvent("papa_vehicleshop:server:requestSync", function()
    Sy.full(source)
end)

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    -- Clients that were already connected (resource restart) get the state once everything is loaded
    SetTimeout(1500, function()
        Sy.full(-1)
    end)
end)
