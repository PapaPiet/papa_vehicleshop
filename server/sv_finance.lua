--- Finanzierung: Anzahlung beim Kauf, Raten in festen Abständen (echte Minuten) vom Bankkonto,
--- verpasste Raten, Rückholung durch das Autohaus und vorzeitige Ablösung.

VS = VS or {}
VS.Finance = VS.Finance or {}

local U = VS.U
local F = VS.Finance

--- Plan for a price in a shop. Returns nil and an error when financing is not possible.
function F.plan(shop, price)
    local cfg = shop and shop.settings.finance
    if not cfg or not cfg.enabled then
        return nil, "finance_disabled"
    end
    price = math.floor(tonumber(price) or 0)
    if price < (Config.finance.minPrice or 0) then
        return nil, "finance_min_price"
    end
    local down = VS.round(price * (cfg.downPaymentPercent or 0) / 100)
    local financed = price - down
    local interest = VS.round(financed * (cfg.interestPercent or 0) / 100)
    local total = financed + interest
    local installments = math.max(1, cfg.installments or 1)
    local rate = math.ceil(total / installments)
    return {
        price = price,
        downPayment = down,
        financed = financed,
        interest = interest,
        total = total,
        installments = installments,
        rate = rate,
        intervalMinutes = cfg.intervalMinutes or 60,
    }
end

local function fromRow(r)
    return {
        id = tonumber(r.id), shopId = tonumber(r.shop_id), saleId = tonumber(r.sale_id), plate = r.plate, label = r.label,
        buyerId = r.buyer_id, buyerName = r.buyer_name, total = tonumber(r.total) or 0, paid = tonumber(r.paid) or 0,
        rate = tonumber(r.rate) or 0, ratesLeft = tonumber(r.rates_left) or 0, intervalMin = tonumber(r.interval_min) or 60,
        nextDueAt = tonumber(r.next_due_at) or 0, missed = tonumber(r.missed) or 0, status = r.status,
        createdAt = tonumber(r.created_at) or 0, updatedAt = tonumber(r.updated_at) or 0,
    }
end

local function save(f)
    f.updatedAt = U.now()
    MySQL.update.await(
        ([[UPDATE %s SET `plate`=?,`paid`=?,`rates_left`=?,`next_due_at`=?,`missed`=?,`status`=?,`updated_at`=? WHERE `id`=?]]):format(VS.Db.t("finances")),
        { f.plate, f.paid, f.ratesLeft, f.nextDueAt, f.missed, f.status, f.updatedAt, f.id }
    )
end

function F.get(id)
    local r = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("finances")), { tonumber(id) or -1 })
    return r and fromRow(r) or nil
end

function F.create(shop, data)
    local plan = data.plan
    local now = U.now()
    MySQL.insert.await(
        ([[INSERT INTO %s (`shop_id`,`sale_id`,`plate`,`label`,`buyer_id`,`buyer_name`,`total`,`paid`,`rate`,`rates_left`,`interval_min`,`next_due_at`,`missed`,`status`,`created_at`,`updated_at`)
           VALUES (?,?,?,?,?,?,?,0,?,?,?,?,0,'active',?,?)]]):format(VS.Db.t("finances")),
        {
            shop.id, data.saleId, data.plate, data.label, data.buyerId, data.buyerName, plan.total, plan.rate, plan.installments,
            plan.intervalMinutes, now + plan.intervalMinutes * 60000, now, now,
        }
    )
end

function F.forShop(shop, statuses)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `shop_id` = ? ORDER BY FIELD(`status`,'defaulted','active','paid','repossessed'), `next_due_at` ASC LIMIT 200"):format(VS.Db.t("finances")),
        { shop.id }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local f = fromRow(r)
        if not statuses or U.oneOf(f.status, statuses, nil) then
            out[#out + 1] = f
        end
    end
    return out
end

function F.forBuyer(identifier)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `buyer_id` = ? AND `status` IN ('active','defaulted') ORDER BY `id` DESC"):format(VS.Db.t("finances")),
        { identifier }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local f = fromRow(r)
        local shop = VS.Shops.get(f.shopId)
        f.shopLabel = shop and shop.label or "-"
        f.remaining = math.max(0, f.total - f.paid)
        out[#out + 1] = f
    end
    return out
end

local function credit(f, amount, text)
    local shop = VS.Shops.get(f.shopId)
    if shop and shop.type ~= "npc" then
        VS.Account.add(shop, amount, "finance", text, f.plate, f.buyerName)
    end
end

--- Takes one rate from the buyer (online: bank, offline: framework DB).
local function charge(f)
    local amount = math.min(f.rate, math.max(0, f.total - f.paid))
    if amount <= 0 then
        return true
    end
    local src = PAPA.Functions.getPlayerSourceByCitizenId(f.buyerId)
    local ok = false
    if src then
        ok = VS.Account.playerPay(src, "bank", amount)
        if ok then
            VS.Notify.player(src, T("notify_rate_paid", f.label, U.formatMoney(amount)), "info")
        else
            VS.Notify.player(src, T("notify_rate_missed", f.label), "error")
        end
    else
        local snap = PAPA.Functions.getOfflinePlayerSnapshot(f.buyerId)
        if snap and snap.money and (tonumber(snap.money.bank) or 0) >= amount then
            ok = PAPA.Functions.changeOfflinePlayerMoney(f.buyerId, "bank", -amount) == true
        end
    end
    if ok then
        f.paid = f.paid + amount
        f.ratesLeft = math.max(0, f.ratesLeft - 1)
        credit(f, amount, T("ledger_rate", f.label, f.plate or ""))
    end
    return ok
end

local function tick()
    local now = U.now()
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `status` IN ('active','defaulted') AND `next_due_at` <= ? LIMIT 100"):format(VS.Db.t("finances")),
        { now }
    ) or {}
    for _, r in ipairs(rows) do
        local f = fromRow(r)
        local ok = charge(f)
        if not ok then
            f.missed = f.missed + 1
        end
        f.nextDueAt = now + f.intervalMin * 60000
        if f.paid >= f.total then
            f.status = "paid"
            VS.Notify.identifier(f.buyerId, T("finance_title"), T("notify_finance_paid", f.label), "success")
        elseif f.missed >= (Config.finance.maxMissed or 3) and f.status ~= "defaulted" then
            f.status = "defaulted"
            local shop = VS.Shops.get(f.shopId)
            if shop then
                VS.Notify.staff(shop, T("notify_finance_defaulted", f.buyerName or "-", f.label, f.plate or ""), "error")
            end
            VS.Notify.identifier(f.buyerId, T("finance_title"), T("notify_finance_defaulted_buyer", f.label), "error")
        end
        save(f)
    end
end

CreateThread(function()
    while true do
        Wait(60000)
        if VS.Db.ready then
            tick()
        end
    end
end)

--- Buyer pays the rest at once.
function F.payOff(actor, financeId, payWith)
    local f = F.get(financeId)
    if not f or f.buyerId ~= actor.id or (f.status ~= "active" and f.status ~= "defaulted") then
        return nil, "not_found"
    end
    local rest = math.max(0, f.total - f.paid)
    local ok, err = VS.Account.playerPay(actor.src, payWith == "cash" and "cash" or "bank", rest)
    if not ok then
        return nil, err
    end
    f.paid = f.total
    f.ratesLeft = 0
    f.status = "paid"
    save(f)
    credit(f, rest, T("ledger_payoff", f.label, f.plate or ""))
    return { paid = rest }
end

--- Shop takes the vehicle back after too many missed rates.
function F.repossess(actor, shop, financeId)
    local f = F.get(financeId)
    if not f or f.shopId ~= shop.id then
        return nil, "not_found"
    end
    if f.status ~= "defaulted" then
        return nil, "invalid_status"
    end
    if not shop.ownerId then
        return nil, "no_owner"
    end
    if not f.plate or f.plate:find("^ORDER%-") then
        return nil, "invalid_status"
    end
    local owner = PAPA.Functions.getVehicleOwner(f.plate)
    if owner ~= f.buyerId then
        return nil, "ownership_mismatch"
    end
    if not PAPA.Functions.transferVehicleOwnership(f.plate, shop.ownerId) then
        return nil, "transfer_failed"
    end
    local owned = PAPA.Functions.getOwnedVehicle(f.plate)
    local s = VS.Stock.registerOwned(actor, shop, { plate = f.plate, model = owned and owned.model or "", label = f.label })
    if s then
        if owned and owned.props then
            s.props = owned.props
        end
        VS.Stock.toStorage(s)
    end
    f.status = "repossessed"
    save(f)
    VS.Notify.identifier(f.buyerId, T("finance_title"), T("notify_repossessed", f.label), "error")
    VS.audit(shop.id, actor, "finance.repossess", f.plate, { buyer = f.buyerName })
    VS.Sync.changed(shop)
    return true
end
