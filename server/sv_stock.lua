--- Bestand eines Autohauses. Jedes Fahrzeug ist (ab Ankunft) ein echtes Fahrzeug des Inhabers im Framework.
---
--- Status:
---   transit   bestellt, unterwegs (noch kein Framework-Fahrzeug)
---   waiting   angekommen, wartet am Hafen / Flugplatz auf Abholung
---   pickup    wird gerade gefahren (Abholung oder Transportauftrag)
---   storage   im Lager des Autohauses (Framework-Garage papa_vs_<id>)
---   display   steht auf einem Ausstellungsplatz
---   testdrive auf Probefahrt
---   out       vom Personal ausgefahren (z. B. in eine Garage gebracht)
---   sold      verkauft (Endzustand)
---   removed   aus dem Bestand genommen / verschrottet (Endzustand)

VS = VS or {}
VS.Stock = VS.Stock or {}

local U = VS.U
local St = VS.Stock

St.STATUS = { "transit", "waiting", "pickup", "storage", "display", "testdrive", "out", "sold", "removed" }
St.ACTIVE = { transit = true, waiting = true, pickup = true, storage = true, display = true, testdrive = true, out = true }

local cache = {} -- id -> row (active rows only)

local function fromRow(r)
    return {
        id = tonumber(r.id),
        shopId = tonumber(r.shop_id),
        plate = r.plate,
        model = r.model,
        label = r.label or r.model,
        vtype = VS.isType(r.vtype) and r.vtype or "car",
        status = r.status,
        displayId = tonumber(r.display_id),
        price = tonumber(r.price) or 0,
        cost = tonumber(r.cost) or 0,
        props = U.jsonDecode(r.props_json, {}),
        condition = U.jsonDecode(r.condition_json, {}),
        source = r.source,
        deliveryPoint = r.delivery_point,
        eta = tonumber(r.eta) or 0,
        arrivedAt = tonumber(r.arrived_at) or 0,
        orderedBy = r.ordered_by,
        reservedFor = r.reserved_for,
        reservedName = r.reserved_name,
        note = r.note,
        color = tonumber(r.color),
        createdAt = tonumber(r.created_at) or 0,
        updatedAt = tonumber(r.updated_at) or 0,
        soldAt = tonumber(r.sold_at) or 0,
    }
end

function St.load()
    cache = {}
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `status` NOT IN ('sold','removed')"):format(VS.Db.t("stock"))
    ) or {}
    for _, r in ipairs(rows) do
        local s = fromRow(r)
        cache[s.id] = s
    end
end

function St.get(id)
    id = tonumber(id)
    if not id then
        return nil
    end
    if cache[id] then
        return cache[id]
    end
    local r = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("stock")), { id })
    return r and fromRow(r) or nil
end

function St.byPlate(plate)
    plate = U.normalizePlate(plate)
    if plate == "" then
        return nil
    end
    for _, s in pairs(cache) do
        if s.plate and U.normalizePlate(s.plate) == plate then
            return s
        end
    end
    return nil
end

--- Active vehicles of a shop (optionally filtered by status list).
function St.forShop(shopId, statuses)
    local want = nil
    if type(statuses) == "table" and #statuses > 0 then
        want = {}
        for _, s in ipairs(statuses) do
            want[s] = true
        end
    end
    local out = {}
    for _, s in pairs(cache) do
        if s.shopId == shopId and (not want or want[s.status]) then
            out[#out + 1] = s
        end
    end
    table.sort(out, function(a, b)
        return a.id > b.id
    end)
    return out
end

function St.all()
    local out = {}
    for _, s in pairs(cache) do
        out[#out + 1] = s
    end
    return out
end

function St.counts(shopId)
    local out = { total = 0 }
    for _, s in pairs(cache) do
        if s.shopId == shopId then
            out[s.status] = (out[s.status] or 0) + 1
            out.total = out.total + 1
        end
    end
    return out
end

--- Persists a stock row (all mutable fields).
function St.save(s)
    s.updatedAt = U.now()
    MySQL.update.await(
        ([[UPDATE %s SET `plate`=?,`label`=?,`vtype`=?,`status`=?,`display_id`=?,`price`=?,`cost`=?,`props_json`=?,`condition_json`=?,
           `delivery_point`=?,`eta`=?,`arrived_at`=?,`reserved_for`=?,`reserved_name`=?,`note`=?,`updated_at`=?,`sold_at`=? WHERE `id`=?]])
            :format(VS.Db.t("stock")),
        {
            s.plate, s.label, s.vtype, s.status, s.displayId, s.price, s.cost, U.jsonEncode(s.props), U.jsonEncode(s.condition),
            s.deliveryPoint, s.eta, s.arrivedAt, s.reservedFor, s.reservedName, s.note, s.updatedAt, s.soldAt, s.id,
        }
    )
    if St.ACTIVE[s.status] then
        cache[s.id] = s
    else
        cache[s.id] = nil
    end
end

--- Creates a stock row and returns it.
function St.insert(data)
    local now = U.now()
    local id = MySQL.insert.await(
        ([[INSERT INTO %s (`shop_id`,`plate`,`model`,`label`,`vtype`,`status`,`display_id`,`price`,`cost`,`props_json`,`condition_json`,
           `source`,`delivery_point`,`eta`,`arrived_at`,`ordered_by`,`note`,`color`,`created_at`,`updated_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]]):format(VS.Db.t("stock")),
        {
            data.shopId, data.plate, data.model, data.label, data.vtype or "car", data.status, data.displayId, data.price or 0,
            data.cost or 0, U.jsonEncode(data.props or {}), U.jsonEncode(data.condition or {}), data.source or "order",
            data.deliveryPoint, data.eta or 0, data.arrivedAt or 0, data.orderedBy, data.note, data.color, now, now,
        }
    )
    if not id then
        return nil
    end
    local row = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("stock")), { id })
    local s = fromRow(row)
    if St.ACTIVE[s.status] then
        cache[s.id] = s
    end
    return s
end

--- Public view of a stock row for the dashboard.
function St.view(s)
    local display = s.displayId and VS.Displays.get(s.displayId)
    local point = s.deliveryPoint and VS.Points.get(s.deliveryPoint)
    return {
        id = s.id, plate = s.plate, model = s.model, label = s.label, vtype = s.vtype, status = s.status,
        displayId = s.displayId, displayLabel = display and display.label or nil,
        price = s.price, cost = s.cost, condition = s.condition, source = s.source,
        deliveryPoint = s.deliveryPoint, deliveryLabel = point and point.label or nil,
        eta = s.eta, arrivedAt = s.arrivedAt, orderedBy = s.orderedBy,
        reservedFor = s.reservedFor, reservedName = s.reservedName, note = s.note,
        createdAt = s.createdAt, updatedAt = s.updatedAt,
        brand = (VS.Catalog.get(s.model) or {}).brand,
        listPrice = (VS.Catalog.get(s.model) or {}).price,
        contract = VS.Logistics and VS.Logistics.contractForStock(s.id) or nil,
    }
end

-- Ordering ----------------------------------------------------------------------------------

local function jitter(minutes)
    local pct = tonumber(Config.delivery.jitterPercent) or 0
    if pct <= 0 then
        return minutes
    end
    local f = 1 + (math.random(-pct, pct) / 100)
    return math.max(1, minutes * f)
end

--- Wholesale price of a catalog entry for a shop.
function St.wholesale(shop, entry)
    return VS.round(entry.price * (shop.settings.wholesaleMultiplier or 0.72))
end

--- Orders vehicles from the manufacturer. input = { model, quantity, color, deliveryPoint, price, note }
function St.order(actor, shop, input)
    if type(input) ~= "table" then
        return nil, "invalid"
    end
    if not shop.ownerId then
        return nil, "no_owner"
    end
    local entry = VS.Catalog.get(input.model)
    if not entry or not VS.Catalog.allowedForShop(shop, entry) then
        return nil, "not_in_catalog"
    end
    local quantity = U.int(input.quantity, 1, 20, 1)
    local points = VS.Points.forType(shop, entry.vtype)
    if #points == 0 then
        return nil, "no_delivery_point"
    end
    local point = points[1]
    if input.deliveryPoint then
        point = nil
        for _, p in ipairs(points) do
            if p.id == input.deliveryPoint then
                point = p
            end
        end
        if not point then
            return nil, "invalid_delivery_point"
        end
    end
    local limit = tonumber(shop.settings.storageLimit) or 0
    if limit > 0 then
        local c = St.counts(shop.id)
        if c.total + quantity > limit then
            return nil, "storage_full"
        end
    end
    local unit = St.wholesale(shop, entry)
    local total = unit * quantity
    local ok, err = VS.Account.remove(shop, total, "order", T("ledger_order", quantity, entry.label), entry.model, actor.name)
    if not ok then
        return nil, err
    end
    local salePrice = U.int(input.price, 0, 2000000000, entry.price)
    local color = U.int(input.color, 0, 160, nil)
    local created = {}
    for _ = 1, quantity do
        local minutes = jitter(VS.Catalog.minutes(entry))
        local s = St.insert({
            shopId = shop.id,
            model = entry.model,
            label = entry.label,
            vtype = entry.vtype,
            status = "transit",
            price = salePrice,
            cost = unit,
            source = "order",
            deliveryPoint = point.id,
            eta = U.now() + math.floor(minutes * 60000),
            orderedBy = actor.name,
            note = U.optStr(input.note, 255),
            color = color,
            props = color and { color1 = color, color2 = color } or {},
        })
        if s then
            created[#created + 1] = s
        end
    end
    VS.audit(shop.id, actor, "stock.order", entry.model, { quantity = quantity, total = total, point = point.id })
    VS.Sync.changed(shop)
    return { count = #created, total = total, unit = unit, eta = created[1] and created[1].eta or 0 }
end

--- Cancels an order that has not arrived yet. The manufacturer keeps a cancellation fee.
St.CANCEL_FEE_PERCENT = 10

function St.cancelOrder(actor, shop, stockId)
    local s = St.get(stockId)
    if not s or s.shopId ~= shop.id then
        return nil, "not_found"
    end
    if s.status ~= "transit" then
        return nil, "invalid_status"
    end
    local refund = VS.round(s.cost * (100 - St.CANCEL_FEE_PERCENT) / 100)
    s.status = "removed"
    s.note = T("note_order_cancelled")
    St.save(s)
    VS.Account.add(shop, refund, "refund", T("ledger_order_cancelled", s.label), s.model, actor.name)
    VS.audit(shop.id, actor, "stock.cancel", s.id, { refund = refund })
    VS.Sync.changed(shop)
    return { refund = refund }
end

-- Arrival -----------------------------------------------------------------------------------

local function arrive(s)
    local shop = VS.Shops.get(s.shopId)
    if not shop then
        return
    end
    if not shop.ownerId then
        -- Without an owner the vehicle cannot exist in the framework; try again later
        if s.note ~= T("note_no_owner") then
            s.note = T("note_no_owner")
            St.save(s)
            VS.Notify.staff(shop, T("notify_no_owner"), "error")
        end
        return
    end
    local props = s.props or {}
    local plate = PAPA.Functions.addOwnedVehicle(shop.ownerId, s.model, nil, props, (Config.delivery.garagePrefix or "papa_vs_") .. "port_" .. tostring(s.deliveryPoint or ""), s.vtype)
    if not plate then
        print(("^1[papa_vehicleshop] %s^0"):format(T("console_vehicle_create_failed", s.model, tostring(s.id))))
        return
    end
    s.plate = plate
    s.status = "waiting"
    s.arrivedAt = U.now()
    St.save(s)
    local point = VS.Points.get(s.deliveryPoint)
    VS.Notify.staff(shop, T("notify_arrived", s.label, plate, point and point.label or "-"), "success")
    VS.Sync.changed(shop)
end

--- Storage fee at the delivery point once the free time is over.
function St.storageFee(s)
    local hours = tonumber(Config.delivery.freeStorageHours) or 0
    local perDay = tonumber(Config.delivery.storageFeePerDay) or 0
    if perDay <= 0 or s.arrivedAt <= 0 then
        return 0
    end
    local over = (U.now() - s.arrivedAt) - hours * 3600000
    if over <= 0 then
        return 0
    end
    return math.ceil(over / 86400000) * perDay
end

CreateThread(function()
    while true do
        Wait(20000)
        if VS.Db.ready then
            local now = U.now()
            for _, s in pairs(cache) do
                if s.status == "transit" and s.eta > 0 and s.eta <= now then
                    arrive(s)
                end
            end
        end
    end
end)

-- Storage, display, price -------------------------------------------------------------------

--- Saves props/condition (also into the framework row).
function St.capture(s, props, condition)
    if type(props) == "table" and next(props) then
        props.plate = s.plate
        s.props = props
        if s.plate then
            PAPA.Functions.updateOwnedVehicleProps(s.plate, props)
        end
    end
    if type(condition) == "table" then
        s.condition = {
            engine = U.num(condition.engine, 0, 1000, 1000, 0),
            body = U.num(condition.body, 0, 1000, 1000, 0),
            fuel = U.num(condition.fuel, 0, 100, 100, 0),
            dirt = U.num(condition.dirt, 0, 15, 0, 1),
            tank = U.num(condition.tank, -4000, 1000, 1000, 0),
        }
    end
end

--- Damage in percent (0 = like new) from the condition.
function St.damagePercent(s)
    local c = s.condition or {}
    local engine = 1 - (tonumber(c.engine) or 1000) / 1000
    local body = 1 - (tonumber(c.body) or 1000) / 1000
    return math.max(0, math.min(100, VS.round(math.max(engine, body) * 100)))
end

local function freeDisplay(s)
    if s.displayId then
        local d = VS.Displays.get(s.displayId)
        if d and d.stockId == s.id then
            VS.Displays.setStock(d, nil)
        end
        s.displayId = nil
    end
end

--- Puts a vehicle into the shop storage (framework garage of the shop, stored).
function St.toStorage(s, props, condition)
    local shop = VS.Shops.get(s.shopId)
    St.capture(s, props, condition)
    freeDisplay(s)
    s.status = "storage"
    St.save(s)
    if s.plate and shop then
        PAPA.Functions.setOwnedVehicleGarage(s.plate, VS.Shops.garage(shop), true)
    end
    if shop then
        VS.Sync.changed(shop)
    end
    return s
end

function St.toDisplay(actor, shop, s, displayId)
    local d = VS.Displays.get(displayId)
    if not d or d.shopId ~= shop.id then
        return nil, "not_found"
    end
    if d.kind ~= "stock" then
        return nil, "display_showcase"
    end
    if d.stockId and d.stockId ~= s.id then
        local other = St.get(d.stockId)
        if other and St.ACTIVE[other.status] and other.displayId == d.id then
            return nil, "display_occupied"
        end
    end
    if not VS.typeAllowed(d.types, s.vtype) then
        return nil, "type_not_allowed"
    end
    if s.status ~= "storage" and s.status ~= "display" then
        return nil, "invalid_status"
    end
    freeDisplay(s)
    s.status = "display"
    s.displayId = d.id
    St.save(s)
    VS.Displays.setStock(d, s.id)
    if s.plate then
        PAPA.Functions.setOwnedVehicleGarage(s.plate, VS.Shops.garage(shop), true)
    end
    VS.audit(shop.id, actor, "stock.display", s.id, { display = d.id })
    VS.Sync.changed(shop)
    return s
end

function St.fromDisplay(actor, shop, s)
    if s.status ~= "display" then
        return nil, "invalid_status"
    end
    St.toStorage(s)
    VS.audit(shop.id, actor, "stock.undisplay", s.id)
    return s
end

function St.setPrice(actor, shop, s, price, note)
    s.price = U.int(price, 0, 2000000000, s.price)
    if note ~= nil then
        s.note = U.optStr(note, 255)
    end
    St.save(s)
    if s.displayId then
        VS.Sync.display(s.displayId)
    end
    VS.audit(shop.id, actor, "stock.price", s.id, { price = s.price })
    VS.Sync.changed(shop)
    return s
end

--- Reserve for a customer (shown on the sign, direct purchase only by that customer).
function St.reserve(actor, shop, s, identifier, name)
    if identifier and identifier ~= "" then
        s.reservedFor = identifier
        s.reservedName = U.optStr(name, 96) or identifier
    else
        s.reservedFor, s.reservedName = nil, nil
    end
    St.save(s)
    if s.displayId then
        VS.Sync.display(s.displayId)
    end
    VS.audit(shop.id, actor, "stock.reserve", s.id, { for_ = s.reservedName })
    VS.Sync.changed(shop)
    return s
end

--- Takes a vehicle out of the shop's management.
--- mode "release": stays with the owner, goes to a normal garage. mode "scrap": deleted from the framework.
function St.remove(actor, shop, s, mode)
    if s.status ~= "storage" and s.status ~= "display" and s.status ~= "out" then
        return nil, "invalid_status"
    end
    freeDisplay(s)
    if mode == "scrap" then
        if s.plate then
            PAPA.Functions.deleteOwnedVehicle(s.plate)
        end
        s.note = T("note_scrapped")
    else
        if s.plate then
            PAPA.Functions.setOwnedVehicleGarage(s.plate, Config.delivery.releaseGarage, true)
        end
        s.note = T("note_released")
    end
    s.status = "removed"
    St.save(s)
    VS.audit(shop.id, actor, "stock.remove", s.id, { mode = mode })
    VS.Sync.changed(shop)
    return true
end

--- Registers a vehicle of the owner that is not in stock yet (driven to the shop / display spot).
function St.registerOwned(actor, shop, data)
    local plate = U.normalizePlate(data.plate)
    if plate == "" then
        return nil, "invalid"
    end
    local existing = St.byPlate(plate)
    if existing then
        return existing
    end
    local owned = PAPA.Functions.getOwnedVehicle(plate)
    if not owned or owned.owner ~= shop.ownerId then
        return nil, "not_owned_by_shop"
    end
    local model = U.str(data.model, 64):lower()
    if model == "" or model:match("^%-?%d+$") then
        model = owned.model ~= "" and not owned.model:match("^%-?%d+$") and owned.model:lower() or model
    end
    local entry = VS.Catalog.get(model)
    local s = St.insert({
        shopId = shop.id,
        plate = plate,
        model = model ~= "" and model or tostring(owned.modelHash),
        label = entry and entry.label or U.str(data.label, 96) ~= "" and U.str(data.label, 96) or model,
        vtype = VS.isType(data.vtype) and data.vtype or entry and entry.vtype or "car",
        status = "storage",
        price = entry and entry.price or 0,
        cost = 0,
        source = "garage",
        orderedBy = actor and actor.name or nil,
    })
    if not s then
        return nil, "db_error"
    end
    VS.audit(shop.id, actor, "stock.register", plate)
    return s
end

--- On start: vehicles that were on a test drive or being picked up when the server stopped go back.
local function recover()
    for _, s in pairs(cache) do
        if s.status == "testdrive" then
            s.status = s.displayId and "display" or "storage"
            St.save(s)
        elseif s.status == "pickup" then
            s.status = "waiting"
            St.save(s)
        end
    end
end

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    St.load()
    recover()
end)
