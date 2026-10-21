--- Inzahlungnahme / Ankauf: Ein Spieler bietet sein eigenes Fahrzeug an der Anlieferung eines Autohauses an.
--- Mit Personal: Anfrage im Dashboard, das Personal macht ein Angebot, der Kunde nimmt an oder lehnt ab.
--- Ohne Personal (NPC): sofortiges Angebot nach Katalogpreis und Zustand.

VS = VS or {}
VS.TradeIn = VS.TradeIn or {}

local U = VS.U
local Ti = VS.TradeIn

local runtime = {} -- tradeId -> { src, netId }

local function fromRow(r)
    return {
        id = tonumber(r.id), shopId = tonumber(r.shop_id), plate = r.plate, model = r.model, label = r.label, vtype = r.vtype,
        sellerId = r.seller_id, sellerName = r.seller_name, props = U.jsonDecode(r.props_json, {}),
        condition = U.jsonDecode(r.condition_json, {}), asking = tonumber(r.asking) or 0, offer = tonumber(r.offer) or 0,
        status = r.status, offeredBy = r.offered_by, createdAt = tonumber(r.created_at) or 0, expiresAt = tonumber(r.expires_at) or 0,
    }
end

local function get(id)
    local r = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("tradeins")), { tonumber(id) or -1 })
    return r and fromRow(r) or nil
end

local function setStatus(t, status, offer, offeredBy)
    MySQL.update.await(
        ("UPDATE %s SET `status` = ?, `offer` = ?, `offered_by` = ? WHERE `id` = ?"):format(VS.Db.t("tradeins")),
        { status, offer or t.offer, offeredBy or t.offeredBy, t.id }
    )
    t.status, t.offer, t.offeredBy = status, offer or t.offer, offeredBy or t.offeredBy
end

local function damagePercent(condition)
    return VS.Stock.damagePercent({ condition = condition })
end

--- NPC price for a vehicle.
function Ti.npcOffer(shop, model, condition)
    local entry = VS.Catalog.get(model)
    if not entry then
        return nil
    end
    local pct = shop.settings.tradeIn.npcPercent or Config.tradeIn.npcPercent or 45
    local damage = damagePercent(condition)
    local penalty = math.floor(damage / 10) * (Config.tradeIn.damagePenaltyPer10 or 4)
    return math.max(0, VS.round(entry.price * math.max(0, pct - penalty) / 100))
end

local function sanitizeVehicle(data)
    return {
        plate = U.normalizePlate(data.plate),
        model = U.str(data.model, 64):lower(),
        label = U.str(data.label, 96),
        vtype = VS.isType(data.vtype) and data.vtype or "car",
        props = type(data.props) == "table" and data.props or {},
        condition = type(data.condition) == "table" and data.condition or {},
        asking = U.int(data.asking, 0, 2000000000, 0),
        netId = tonumber(data.netId),
    }
end

--- Customer offers his vehicle. Returns { mode = "npc", offer } or { mode = "staff", tradeId }.
function Ti.request(actor, shopId, data)
    local shop = VS.Shops.get(shopId)
    if not shop or not shop.active or not shop.settings.tradeIn.enabled then
        return nil, "tradein_disabled"
    end
    if type(data) ~= "table" then
        return nil, "invalid"
    end
    local v = sanitizeVehicle(data)
    if v.plate == "" then
        return nil, "invalid"
    end
    local drop = shop.points.dropoff
    local ped = GetPlayerPed(actor.src)
    if not drop or ped == 0 or #(GetEntityCoords(ped) - vector3(drop.x, drop.y, drop.z)) > (shop.settings.dropoffRadius or 7.0) + 4.0 then
        return nil, "too_far"
    end
    if PAPA.Functions.getVehicleOwner(v.plate) ~= actor.id then
        return nil, "not_your_vehicle"
    end
    local financed = MySQL.query.await(
        ("SELECT `id` FROM %s WHERE `plate` = ? AND `status` IN ('active','defaulted') LIMIT 1"):format(VS.Db.t("finances")), { v.plate }
    ) or {}
    if #financed > 0 then
        return nil, "vehicle_financed"
    end
    local owned = PAPA.Functions.getOwnedVehicle(v.plate)
    if owned and owned.model ~= "" and not owned.model:match("^%-?%d+$") then
        v.model = owned.model:lower()
    end
    local entry = VS.Catalog.get(v.model)
    if entry then
        v.label = entry.label
        v.vtype = entry.vtype
    end
    if v.label == "" then
        v.label = v.model
    end
    local npc = VS.Shops.npcActive(shop)
    if npc then
        if Config.tradeIn.npcRequiresCatalog and not entry then
            return nil, "tradein_not_in_catalog"
        end
        local offer = Ti.npcOffer(shop, v.model, v.condition)
        if not offer or offer <= 0 then
            return nil, "tradein_not_in_catalog"
        end
        local id = MySQL.insert.await(
            ([[INSERT INTO %s (`shop_id`,`plate`,`model`,`label`,`vtype`,`seller_id`,`seller_name`,`props_json`,`condition_json`,`asking`,`offer`,`status`,`offered_by`,`created_at`,`expires_at`)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,'offered',?,?,?)]]):format(VS.Db.t("tradeins")),
            { shop.id, v.plate, v.model, v.label, v.vtype, actor.id, actor.name, U.jsonEncode(v.props), U.jsonEncode(v.condition), v.asking, offer, "NPC", U.now(), U.now() + 120000 }
        )
        runtime[id] = { src = actor.src, netId = v.netId }
        return { mode = "npc", tradeId = id, offer = offer, label = v.label, damage = damagePercent(v.condition), currency = shop.settings.currency }
    end
    if shop.type == "npc" then
        return nil, "tradein_disabled"
    end
    local minutes = tonumber(Config.tradeIn.requestMinutes) or 10
    local id = MySQL.insert.await(
        ([[INSERT INTO %s (`shop_id`,`plate`,`model`,`label`,`vtype`,`seller_id`,`seller_name`,`props_json`,`condition_json`,`asking`,`status`,`created_at`,`expires_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?,'open',?,?)]]):format(VS.Db.t("tradeins")),
        { shop.id, v.plate, v.model, v.label, v.vtype, actor.id, actor.name, U.jsonEncode(v.props), U.jsonEncode(v.condition), v.asking, U.now(), U.now() + minutes * 60000 }
    )
    runtime[id] = { src = actor.src, netId = v.netId }
    VS.Notify.staff(shop, T("notify_tradein_request", actor.name, v.label, U.formatMoney(v.asking, shop.settings.currency)), "info")
    VS.Sync.changed(shop)
    return { mode = "staff", tradeId = id, label = v.label, minutes = minutes }
end

function Ti.listOpen(shop)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `shop_id` = ? AND `status` IN ('open','offered') AND `expires_at` > ? ORDER BY `id` DESC"):format(VS.Db.t("tradeins")),
        { shop.id, U.now() }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local t = fromRow(r)
        local entry = VS.Catalog.get(t.model)
        t.listPrice = entry and entry.price or nil
        t.damage = damagePercent(t.condition)
        t.suggestion = Ti.npcOffer(shop, t.model, t.condition)
        t.props = nil
        out[#out + 1] = t
    end
    return out
end

--- Staff makes an offer; the customer gets a dialog.
function Ti.makeOffer(actor, shop, tradeId, amount)
    local t = get(tradeId)
    if not t or t.shopId ~= shop.id or t.status ~= "open" or t.expiresAt < U.now() then
        return nil, "not_found"
    end
    amount = U.int(amount, 1, 2000000000, 0)
    if amount <= 0 then
        return nil, "invalid_amount"
    end
    if VS.Account.balance(shop) < amount then
        return nil, "insufficient_funds"
    end
    local r = runtime[t.id]
    local src = r and r.src or PAPA.Functions.getPlayerSourceByCitizenId(t.sellerId)
    if not src then
        return nil, "customer_offline"
    end
    setStatus(t, "offered", amount, actor.name)
    TriggerClientEvent("papa_vehicleshop:client:tradeInOffer", src, {
        tradeId = t.id, shopLabel = shop.label, label = t.label, plate = t.plate, offer = amount, by = actor.name, currency = shop.settings.currency,
    })
    VS.audit(shop.id, actor, "tradein.offer", t.plate, { offer = amount })
    VS.Sync.changed(shop)
    return true
end

function Ti.decline(actor, shop, tradeId)
    local t = get(tradeId)
    if not t or t.shopId ~= shop.id or (t.status ~= "open" and t.status ~= "offered") then
        return nil, "not_found"
    end
    setStatus(t, "declined")
    local r = runtime[t.id]
    if r and r.src then
        VS.Notify.player(r.src, T("notify_tradein_declined", shop.label), "error")
    end
    runtime[t.id] = nil
    VS.Sync.changed(shop)
    return true
end

--- Customer answers the offer. The vehicle must still be at the drop-off.
--- data = { accept, props, condition } (fresh state from the client)
function Ti.answer(actor, tradeId, data)
    local t = get(tradeId)
    if not t or t.sellerId ~= actor.id or t.status ~= "offered" then
        return nil, "offer_expired"
    end
    local shop = VS.Shops.get(t.shopId)
    if not shop then
        return nil, "not_found"
    end
    data = type(data) == "table" and data or {}
    if not data.accept then
        setStatus(t, "declined")
        runtime[t.id] = nil
        if t.offeredBy ~= "NPC" then
            VS.Notify.staff(shop, T("notify_tradein_customer_declined", actor.name, t.label), "error")
        end
        VS.Sync.changed(shop)
        return { declined = true }
    end
    if t.offeredBy == "NPC" and t.expiresAt < U.now() then
        return nil, "offer_expired"
    end
    if PAPA.Functions.getVehicleOwner(t.plate) ~= actor.id then
        return nil, "not_your_vehicle"
    end
    local npc = t.offeredBy == "NPC"
    if not npc or (shop.type == "mixed" and shop.ownerId) then
        -- Bought for the shop: the shop pays and the vehicle becomes stock of the owner
        if not shop.ownerId then
            return nil, "no_owner"
        end
        local ok, err = VS.Account.remove(shop, t.offer, "tradein", T("ledger_tradein", t.label, t.plate), t.plate, t.offeredBy)
        if not ok then
            return nil, err
        end
        if not PAPA.Functions.transferVehicleOwnership(t.plate, shop.ownerId) then
            VS.Account.add(shop, t.offer, "refund", T("ledger_tradein_failed", t.plate), t.plate, nil)
            return nil, "transfer_failed"
        end
        local s = VS.Stock.insert({
            shopId = shop.id, plate = t.plate, model = t.model, label = t.label, vtype = t.vtype, status = "storage",
            price = (VS.Catalog.get(t.model) or {}).price or VS.round(t.offer * 1.3), cost = t.offer, source = "tradein",
            orderedBy = t.offeredBy, props = data.props or t.props, condition = data.condition or t.condition,
        })
        if s then
            VS.Stock.toStorage(s, data.props, data.condition)
        end
    else
        -- Pure NPC shop: the vehicle leaves the game (scrap dealer)
        PAPA.Functions.deleteOwnedVehicle(t.plate)
    end
    VS.Account.playerReceive(actor.src, "bank", t.offer)
    setStatus(t, "accepted")
    local r = runtime[t.id]
    runtime[t.id] = nil
    VS.audit(shop.id, actor, "tradein.accept", t.plate, { offer = t.offer, by = t.offeredBy })
    if not npc then
        VS.Notify.staff(shop, T("notify_tradein_accepted", actor.name, t.label), "success")
    end
    VS.Sync.changed(shop)
    return { accepted = true, offer = t.offer, netId = r and r.netId or nil }
end

AddEventHandler("playerDropped", function()
    local src = source
    for id, r in pairs(runtime) do
        if r.src == src then
            runtime[id] = nil
        end
    end
end)
