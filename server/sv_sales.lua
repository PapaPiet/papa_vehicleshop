--- Verkäufe: Direktkauf am Ausstellungsfahrzeug, NPC-Katalogkauf (mit oder ohne Lieferzeit),
--- Verkauf durch das Personal an einen Kunden (mit Rabatt, Provision, Finanzierung) und Kundenbestellungen.

VS = VS or {}
VS.Sales = VS.Sales or {}

local U = VS.U
local Sa = VS.Sales
local St = VS.Stock

local pendingOffers = {} -- offerId -> offer (staff sale waiting for the customer)
local nextOfferId = 0

-- Helpers -----------------------------------------------------------------------------------

local function record(shop, data)
    return MySQL.insert.await(
        ([[INSERT INTO %s (`shop_id`,`stock_id`,`plate`,`model`,`label`,`price`,`cost`,`buyer_id`,`buyer_name`,`seller_id`,`seller_name`,`method`,`channel`,`commission`,`created_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]]):format(VS.Db.t("sales")),
        {
            shop.id, data.stockId, data.plate, data.model, data.label, data.price, data.cost or 0, data.buyerId, data.buyerName,
            data.sellerId, data.sellerName, data.method, data.channel, data.commission or 0, U.now(),
        }
    )
end

--- Validates a wish plate. Returns the plate, or nil and an error.
function Sa.checkPlate(plate)
    local cfg = Config.purchase.customPlate or {}
    if not cfg.enabled then
        return nil, "custom_plate_disabled"
    end
    plate = U.normalizePlate(plate)
    if #plate < (cfg.minLength or 2) or #plate > (cfg.maxLength or 8) or not plate:match("^[A-Z0-9]+$") then
        return nil, "invalid_plate"
    end
    if PAPA.Functions.isVehiclePlateTaken(plate) then
        return nil, "plate_taken"
    end
    return plate
end

--- Hands the vehicle to the buyer: spawn at the handover point or put it into a garage.
local function deliver(buyerSrc, shop, plate, model, props, vtype)
    if Config.purchase.spawnAtHandover and shop.points.handover and buyerSrc then
        PAPA.Functions.setOwnedVehicleGarage(plate, nil, false)
        TriggerClientEvent("papa_vehicleshop:client:deliverVehicle", buyerSrc, {
            plate = plate, model = model, props = props, vtype = vtype, coords = shop.points.handover, shopLabel = shop.label,
        })
        return "handover"
    end
    PAPA.Functions.setOwnedVehicleGarage(plate, Config.purchase.garage or Config.delivery.releaseGarage, true)
    return "garage"
end

--- Money of a finished sale goes to the shop (minus commission for the seller).
local function bookSale(shop, amount, label, plate, actorName)
    if amount > 0 then
        VS.Account.add(shop, amount, "sale", T("ledger_sale", label, plate or ""), plate, actorName)
    end
end

local function contractDocument(shop, sale, buyerId)
    if VS.Documents and VS.Documents.contract then
        VS.Documents.contract(shop, sale, buyerId)
    end
end

-- Direct purchase at a display --------------------------------------------------------------

--- opts = { method = "bank"|"cash"|"finance", plate = "WISH", payWith = "bank"|"cash" }
function Sa.buyDisplay(actor, displayId, opts)
    opts = type(opts) == "table" and opts or {}
    local d = VS.Displays.get(displayId)
    if not d then
        return nil, "not_found"
    end
    local shop = VS.Shops.get(d.shopId)
    if not shop or not shop.active then
        return nil, "not_found"
    end
    local ped = GetPlayerPed(actor.src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > 15.0 then
        return nil, "too_far"
    end
    if d.kind == "showcase" then
        return Sa.buyShowcase(actor, shop, d, opts)
    end
    local s = d.stockId and St.get(d.stockId)
    if not s or s.status ~= "display" or s.displayId ~= d.id then
        return nil, "not_available"
    end
    if s.reservedFor and s.reservedFor ~= actor.id then
        return nil, "reserved"
    end
    if s.price <= 0 then
        return nil, "not_for_sale"
    end
    if shop.ownerId == actor.id then
        return nil, "own_vehicle"
    end
    return Sa.execute(shop, s, {
        buyer = actor,
        price = s.price,
        method = opts.method,
        payWith = opts.payWith,
        channel = "display",
    })
end

--- Executes a stock sale. data = { buyer (actor), price, method, payWith, channel, seller (actor|nil) }
function Sa.execute(shop, s, data)
    local buyer = data.buyer
    local price = math.floor(data.price)
    local method = U.oneOf(data.method, { "bank", "cash", "finance" }, "bank")
    local payWith = data.payWith == "cash" and "cash" or "bank"
    if method ~= "finance" and not U.oneOf(method, Config.purchase.methods, nil) then
        return nil, "invalid_method"
    end
    local finance = nil
    local due = price
    if method == "finance" then
        local plan, err = VS.Finance.plan(shop, price)
        if not plan then
            return nil, err
        end
        finance = plan
        due = plan.downPayment
    end
    -- Owner check: the framework must still list the shop owner as owner
    local owner = s.plate and PAPA.Functions.getVehicleOwner(s.plate)
    if not owner or owner ~= shop.ownerId then
        return nil, "ownership_mismatch"
    end
    local ok, err = VS.Account.playerPay(buyer.src, method == "cash" and "cash" or payWith, due)
    if not ok then
        return nil, err
    end
    if not PAPA.Functions.transferVehicleOwnership(s.plate, buyer.id) then
        VS.Account.playerReceive(buyer.src, method == "cash" and "cash" or payWith, due)
        return nil, "transfer_failed"
    end
    -- Commission for the seller (staff sales only)
    local commission = 0
    if data.seller and data.seller.id ~= buyer.id then
        commission = VS.round(price * (shop.settings.commissionPercent or 0) / 100)
    end
    bookSale(shop, due, s.label, s.plate, data.seller and data.seller.name or buyer.name)
    if commission > 0 then
        local paid = VS.Account.remove(shop, commission, "commission", T("ledger_commission", data.seller.name, s.label), s.plate, data.seller.name)
        if paid then
            VS.Account.playerReceive(data.seller.src, "bank", commission)
            VS.Notify.player(data.seller.src, T("notify_commission", U.formatMoney(commission, shop.settings.currency)), "success")
        else
            commission = 0
        end
    end
    if s.displayId then
        local d = VS.Displays.get(s.displayId)
        if d and d.stockId == s.id then
            VS.Displays.setStock(d, nil)
        end
        s.displayId = nil
    end
    VS.Logistics.clearActive(s.id, false)
    s.status = "sold"
    s.soldAt = U.now()
    s.reservedFor, s.reservedName = nil, nil
    St.save(s)
    local saleId = record(shop, {
        stockId = s.id, plate = s.plate, model = s.model, label = s.label, price = price, cost = s.cost,
        buyerId = buyer.id, buyerName = buyer.name, sellerId = data.seller and data.seller.id, sellerName = data.seller and data.seller.name,
        method = method, channel = data.channel or "display", commission = commission,
    })
    if finance then
        VS.Finance.create(shop, {
            saleId = saleId, plate = s.plate, label = s.label, buyerId = buyer.id, buyerName = buyer.name, plan = finance,
        })
    end
    local where = deliver(buyer.src, shop, s.plate, s.model, s.props, s.vtype)
    VS.audit(shop.id, data.seller or buyer, "sale", s.plate, { price = price, method = method, buyer = buyer.name })
    VS.Notify.staff(shop, T("notify_sold", s.label, U.formatMoney(price, shop.settings.currency), buyer.name), "success")
    contractDocument(shop, { id = saleId, label = s.label, plate = s.plate, model = s.model, price = price, method = method, buyerName = buyer.name, sellerName = data.seller and data.seller.name or nil, finance = finance }, buyer.id)
    VS.Sync.changed(shop)
    return { saleId = saleId, plate = s.plate, label = s.label, price = price, delivered = where, finance = finance }
end

-- NPC catalog purchase ----------------------------------------------------------------------

--- Buys a catalog model from the NPC (showcase display or NPC catalog menu).
function Sa.buyCatalog(actor, shop, model, opts)
    opts = type(opts) == "table" and opts or {}
    if not VS.Shops.npcActive(shop) then
        return nil, "npc_not_available"
    end
    local entry = VS.Catalog.get(model)
    if not entry or not VS.Catalog.allowedForShop(shop, entry) then
        return nil, "not_in_catalog"
    end
    local price = VS.Sync.showcasePrice(shop, entry)
    local plate = nil
    local plateFee = 0
    if opts.plate and opts.plate ~= "" then
        local err
        plate, err = Sa.checkPlate(opts.plate)
        if not plate then
            return nil, err
        end
        plateFee = tonumber(Config.purchase.customPlate.price) or 0
    end
    local method = U.oneOf(opts.method, { "bank", "cash", "finance" }, "bank")
    local payWith = opts.payWith == "cash" and "cash" or "bank"
    local finance, due = nil, price
    if method == "finance" then
        -- NPC shops finance too; the rates are then booked without a shop account
        local plan, err = VS.Finance.plan(shop, price)
        if not plan then
            return nil, err
        end
        finance, due = plan, plan.downPayment
    elseif not U.oneOf(method, Config.purchase.methods, nil) then
        return nil, "invalid_method"
    end
    local ok, err = VS.Account.playerPay(actor.src, method == "cash" and "cash" or payWith, due + plateFee)
    if not ok then
        return nil, err
    end
    local color = U.int(opts.color, 0, 160, nil)
    local props = color and { color1 = color, color2 = color } or {}
    -- Mixed shop: the NPC sells on behalf of the shop, the shop keeps the margin over the wholesale price
    if shop.type == "mixed" then
        local margin = due - St.wholesale(shop, entry)
        if margin > 0 then
            VS.Account.add(shop, margin, "npc_sale", T("ledger_npc_sale", entry.label), entry.model, nil)
        end
    end
    local minutes = shop.settings.npcDelivery and VS.Catalog.minutes(entry) or 0
    if minutes > 0 then
        local id = MySQL.insert.await(
            ([[INSERT INTO %s (`shop_id`,`buyer_id`,`buyer_name`,`model`,`label`,`vtype`,`price`,`plate`,`color`,`status`,`eta`,`created_at`)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]]):format(VS.Db.t("customer_orders")),
            { shop.id, actor.id, actor.name, entry.model, entry.label, entry.vtype, price, plate, color, "transit", U.now() + minutes * 60000, U.now() }
        )
        local saleId = record(shop, {
            plate = plate, model = entry.model, label = entry.label, price = price, buyerId = actor.id, buyerName = actor.name,
            method = method, channel = "npc_order",
        })
        if finance then
            -- The plate is only known at collection; the plan is linked by the order
            VS.Finance.create(shop, { saleId = saleId, plate = plate or ("ORDER-" .. tostring(id)), label = entry.label, buyerId = actor.id, buyerName = actor.name, plan = finance })
        end
        VS.audit(shop.id, actor, "sale.order", entry.model, { price = price, order = id })
        return { ordered = true, orderId = id, minutes = minutes, label = entry.label, price = price, finance = finance }
    end
    local newPlate = PAPA.Functions.addOwnedVehicle(actor.id, entry.model, plate, props, nil, entry.vtype)
    if not newPlate then
        VS.Account.playerReceive(actor.src, method == "cash" and "cash" or payWith, due + plateFee)
        return nil, "vehicle_create_failed"
    end
    local saleId = record(shop, {
        plate = newPlate, model = entry.model, label = entry.label, price = price, buyerId = actor.id, buyerName = actor.name,
        method = method, channel = "npc",
    })
    if finance then
        VS.Finance.create(shop, { saleId = saleId, plate = newPlate, label = entry.label, buyerId = actor.id, buyerName = actor.name, plan = finance })
    end
    local where = deliver(actor.src, shop, newPlate, entry.model, props, entry.vtype)
    VS.audit(shop.id, actor, "sale.npc", newPlate, { price = price, model = entry.model })
    contractDocument(shop, { id = saleId, label = entry.label, plate = newPlate, model = entry.model, price = price, method = method, buyerName = actor.name, finance = finance }, actor.id)
    if shop.type == "mixed" then
        VS.Sync.changed(shop)
    end
    return { saleId = saleId, plate = newPlate, label = entry.label, price = price, delivered = where, finance = finance }
end

function Sa.buyShowcase(actor, shop, d, opts)
    if not d.showcaseModel then
        return nil, "not_available"
    end
    return Sa.buyCatalog(actor, shop, d.showcaseModel, opts)
end

--- NPC catalog of a shop (for the customer menu).
function Sa.npcCatalog(shop)
    local out = {}
    if not VS.Shops.npcActive(shop) then
        return out
    end
    for _, e in ipairs(VS.Catalog.forShop(shop)) do
        out[#out + 1] = {
            model = e.model, label = e.label, brand = e.brand, category = e.category, vtype = e.vtype,
            price = VS.Sync.showcasePrice(shop, e),
            minutes = shop.settings.npcDelivery and VS.Catalog.minutes(e) or 0,
        }
    end
    return out
end

-- Customer orders (NPC with delivery time) --------------------------------------------------

local function orderFromRow(r)
    return {
        id = tonumber(r.id), shopId = tonumber(r.shop_id), buyerId = r.buyer_id, buyerName = r.buyer_name, model = r.model,
        label = r.label, vtype = r.vtype, price = tonumber(r.price) or 0, plate = r.plate, color = tonumber(r.color),
        status = r.status, eta = tonumber(r.eta) or 0, createdAt = tonumber(r.created_at) or 0,
    }
end

function Sa.ordersOf(identifier)
    local out = {}
    for _, r in ipairs(MySQL.query.await(
        ("SELECT * FROM %s WHERE `buyer_id` = ? AND `status` IN ('transit','ready') ORDER BY `id` DESC"):format(VS.Db.t("customer_orders")),
        { identifier }
    ) or {}) do
        out[#out + 1] = orderFromRow(r)
    end
    return out
end

function Sa.collectOrder(actor, orderId)
    local r = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("customer_orders")), { tonumber(orderId) or -1 })
    if not r then
        return nil, "not_found"
    end
    local o = orderFromRow(r)
    if o.buyerId ~= actor.id then
        return nil, "not_found"
    end
    if o.status ~= "ready" then
        return nil, "order_not_ready"
    end
    local shop = VS.Shops.get(o.shopId)
    if not shop then
        return nil, "not_found"
    end
    local props = o.color and { color1 = o.color, color2 = o.color } or {}
    if o.plate and PAPA.Functions.isVehiclePlateTaken(o.plate) then
        o.plate = nil
    end
    local plate = PAPA.Functions.addOwnedVehicle(actor.id, o.model, o.plate, props, nil, o.vtype)
    if not plate then
        return nil, "vehicle_create_failed"
    end
    MySQL.update.await(
        ("UPDATE %s SET `status` = 'collected', `plate` = ?, `collected_at` = ? WHERE `id` = ?"):format(VS.Db.t("customer_orders")),
        { plate, U.now(), o.id }
    )
    MySQL.update.await(
        ("UPDATE %s SET `plate` = ? WHERE `plate` = ? AND `buyer_id` = ?"):format(VS.Db.t("finances")),
        { plate, "ORDER-" .. tostring(o.id), actor.id }
    )
    local where = deliver(actor.src, shop, plate, o.model, props, o.vtype)
    VS.audit(shop.id, actor, "order.collect", plate)
    return { plate = plate, label = o.label, delivered = where }
end

CreateThread(function()
    while true do
        Wait(30000)
        if VS.Db.ready then
            local rows = MySQL.query.await(
                ("SELECT * FROM %s WHERE `status` = 'transit' AND `eta` <= ?"):format(VS.Db.t("customer_orders")), { U.now() }
            ) or {}
            for _, r in ipairs(rows) do
                local o = orderFromRow(r)
                MySQL.update.await(("UPDATE %s SET `status` = 'ready' WHERE `id` = ?"):format(VS.Db.t("customer_orders")), { o.id })
                local shop = VS.Shops.get(o.shopId)
                VS.Notify.identifier(o.buyerId, shop and shop.label or T("app_name"), T("notify_order_ready", o.label, shop and shop.label or "-"), "success")
            end
        end
    end
end)

-- Staff sale to a customer ------------------------------------------------------------------

--- Staff offers a stock vehicle to an online player. The customer confirms in a dialog.
function Sa.offer(actor, shop, input)
    if type(input) ~= "table" then
        return nil, "invalid"
    end
    local s = St.get(input.stockId)
    if not s or s.shopId ~= shop.id or (s.status ~= "storage" and s.status ~= "display") then
        return nil, "not_available"
    end
    local target = tonumber(input.targetSrc)
    local targetActor = target and VS.Access.actor(target)
    if not targetActor then
        return nil, "customer_offline"
    end
    if targetActor.id == shop.ownerId then
        return nil, "own_vehicle"
    end
    local price = U.int(input.price, 1, 2000000000, s.price)
    if s.price > 0 and price < s.price then
        local discount = (s.price - price) / s.price * 100
        if not VS.Access.can(actor, shop, "discount") then
            return nil, "no_permission_discount"
        end
        if discount > (shop.settings.maxDiscountPercent or 0) + 0.001 and not VS.Access.isBoss(actor, shop) then
            return nil, "discount_too_high"
        end
    end
    local methods = { "bank", "cash" }
    if input.allowFinance ~= false and shop.settings.finance.enabled and price >= (Config.finance.minPrice or 0) then
        methods[#methods + 1] = "finance"
    end
    nextOfferId = nextOfferId + 1
    local offer = {
        id = nextOfferId, shopId = shop.id, stockId = s.id, price = price, seller = actor, buyerSrc = target,
        buyerId = targetActor.id, expiresAt = GetGameTimer() + 120000,
    }
    pendingOffers[offer.id] = offer
    local plan = VS.Finance.plan(shop, price)
    TriggerClientEvent("papa_vehicleshop:client:saleOffer", target, {
        offerId = offer.id, shopLabel = shop.label, label = s.label, plate = s.plate, price = price, listPrice = s.price,
        seller = actor.name, methods = methods, currency = shop.settings.currency, condition = s.condition,
        finance = plan,
    })
    VS.audit(shop.id, actor, "sale.offer", s.id, { price = price, customer = targetActor.name })
    return { offerId = offer.id, customer = targetActor.name }
end

--- Customer answers an offer.
function Sa.answerOffer(buyer, offerId, accept, method, payWith)
    local offer = pendingOffers[tonumber(offerId) or -1]
    if not offer or offer.buyerSrc ~= buyer.src then
        return nil, "offer_expired"
    end
    pendingOffers[offer.id] = nil
    if GetGameTimer() > offer.expiresAt then
        return nil, "offer_expired"
    end
    local shop = VS.Shops.get(offer.shopId)
    if not accept then
        VS.Notify.player(offer.seller.src, T("notify_offer_declined", buyer.name), "error")
        return { declined = true }
    end
    local s = St.get(offer.stockId)
    if not shop or not s or (s.status ~= "storage" and s.status ~= "display") then
        return nil, "not_available"
    end
    local result, err = Sa.execute(shop, s, {
        buyer = buyer, price = offer.price, method = method, payWith = payWith, channel = "staff", seller = offer.seller,
    })
    if not result then
        VS.Notify.player(offer.seller.src, T("notify_offer_failed", buyer.name, T("err_" .. tostring(err))), "error")
        return nil, err
    end
    VS.Notify.player(offer.seller.src, T("notify_offer_accepted", buyer.name, s.label), "success")
    return result
end

-- Lists for the dashboard -------------------------------------------------------------------

function Sa.list(shop, limit, offset)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?"):format(VS.Db.t("sales")),
        { shop.id, U.int(limit, 1, 200, 50), U.int(offset, 0, 1000000, 0) }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, stockId = r.stock_id, plate = r.plate, model = r.model, label = r.label, price = tonumber(r.price) or 0,
            cost = tonumber(r.cost) or 0, buyerName = r.buyer_name, sellerName = r.seller_name, method = r.method,
            channel = r.channel, commission = tonumber(r.commission) or 0, createdAt = tonumber(r.created_at) or 0,
        }
    end
    return out
end

--- Revenue per day for the last n days (for the dashboard chart).
function Sa.daily(shop, days)
    days = U.int(days, 1, 90, 14)
    local since = U.now() - days * 86400000
    local rows = MySQL.query.await(
        ("SELECT `price`, `cost`, `created_at` FROM %s WHERE `shop_id` = ? AND `created_at` >= ?"):format(VS.Db.t("sales")),
        { shop.id, since }
    ) or {}
    local buckets = {}
    for i = days - 1, 0, -1 do
        local key = os.date("%Y-%m-%d", math.floor((U.now() - i * 86400000) / 1000))
        buckets[#buckets + 1] = { day = key, revenue = 0, profit = 0, count = 0 }
    end
    local index = {}
    for i, b in ipairs(buckets) do
        index[b.day] = i
    end
    for _, r in ipairs(rows) do
        local key = os.date("%Y-%m-%d", math.floor((tonumber(r.created_at) or 0) / 1000))
        local b = buckets[index[key] or 0]
        if b then
            local price, cost = tonumber(r.price) or 0, tonumber(r.cost) or 0
            b.revenue = b.revenue + price
            b.profit = b.profit + (cost > 0 and (price - cost) or 0)
            b.count = b.count + 1
        end
    end
    return buckets
end

AddEventHandler("playerDropped", function()
    local src = source
    for id, offer in pairs(pendingOffers) do
        if offer.buyerSrc == src or offer.seller.src == src then
            pendingOffers[id] = nil
        end
    end
end)
