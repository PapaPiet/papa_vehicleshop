--- Firmenkonto eines Autohauses: intern (Standard) oder papa_os_banking (optional, Config.accountProvider).
--- Jede Buchung steht zusätzlich im eigenen Kontobuch (ledger), damit das Dashboard alles zeigen kann.

VS = VS or {}
VS.Account = VS.Account or {}

local U = VS.U
local Acc = VS.Account

local function useBanking(shop)
    return Config.accountProvider == "papa_os_banking" and shop and shop.job ~= nil
        and GetResourceState("papa_os_banking") == "started"
end

function Acc.balance(shop)
    if not shop then
        return 0
    end
    if useBanking(shop) then
        return math.floor(tonumber(exports["papa_os_banking"]:GetSocietyBalance(shop.job)) or 0)
    end
    return shop.balance or 0
end

local function book(shop, amount, kind, text, ref, actorName)
    local balance = Acc.balance(shop)
    MySQL.insert(
        ("INSERT INTO %s (`shop_id`,`amount`,`balance_after`,`kind`,`text`,`ref`,`actor_name`,`created_at`) VALUES (?,?,?,?,?,?,?,?)")
            :format(VS.Db.t("ledger")),
        { shop.id, amount, balance, kind, text and tostring(text):sub(1, 255) or nil, ref and tostring(ref):sub(1, 64) or nil, actorName, U.now() }
    )
    VS.Sync.balance(shop)
end

--- Credits the shop account.
function Acc.add(shop, amount, kind, text, ref, actorName)
    amount = math.floor(tonumber(amount) or 0)
    if not shop or amount <= 0 then
        return false
    end
    if useBanking(shop) then
        exports["papa_os_banking"]:AddSocietyMoney(shop.job, amount, text or T("ledger_" .. kind))
    else
        MySQL.update.await(("UPDATE %s SET `balance` = `balance` + ? WHERE `id` = ?"):format(VS.Db.t("shops")), { amount, shop.id })
        shop.balance = (shop.balance or 0) + amount
    end
    book(shop, amount, kind, text, ref, actorName)
    return true
end

--- Debits the shop account. Returns false, "insufficient_funds" when the balance is too low.
function Acc.remove(shop, amount, kind, text, ref, actorName)
    amount = math.floor(tonumber(amount) or 0)
    if not shop or amount < 0 then
        return false, "invalid"
    end
    if amount == 0 then
        return true
    end
    if useBanking(shop) then
        if Acc.balance(shop) < amount then
            return false, "insufficient_funds"
        end
        local ok = exports["papa_os_banking"]:RemoveSocietyMoney(shop.job, amount, text or T("ledger_" .. kind), "job", false)
        if ok == false then
            return false, "insufficient_funds"
        end
    else
        local changed = MySQL.update.await(
            ("UPDATE %s SET `balance` = `balance` - ? WHERE `id` = ? AND `balance` >= ?"):format(VS.Db.t("shops")),
            { amount, shop.id, amount }
        ) or 0
        if tonumber(changed) == 0 then
            return false, "insufficient_funds"
        end
        shop.balance = (shop.balance or 0) - amount
    end
    book(shop, -amount, kind, text, ref, actorName)
    return true
end

function Acc.ledger(shop, limit, offset)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?"):format(VS.Db.t("ledger")),
        { shop.id, U.int(limit, 1, 200, 50), U.int(offset, 0, 1000000, 0) }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, amount = tonumber(r.amount) or 0, balanceAfter = tonumber(r.balance_after) or 0,
            kind = r.kind, text = r.text, ref = r.ref, actor = r.actor_name, createdAt = tonumber(r.created_at) or 0,
        }
    end
    return out
end

--- Player money helpers. removePlayerMoney of the bridge does not check the balance, so we do.
function Acc.playerPay(src, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end
    method = method == "cash" and "cash" or "bank"
    if (tonumber(PAPA.Functions.getPlayerMoney(src, method)) or 0) < amount then
        return false, method == "cash" and "not_enough_cash" or "not_enough_bank"
    end
    if not PAPA.Functions.removePlayerMoney(src, method, amount) then
        return false, "payment_failed"
    end
    return true
end

function Acc.playerReceive(src, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end
    return PAPA.Functions.addPlayerMoney(src, method == "cash" and "cash" or "bank", amount) == true
end

--- Boss deposits personal bank money into the shop account.
function Acc.deposit(actor, shop, amount)
    amount = U.int(amount, 1, 2000000000, 0)
    if amount <= 0 then
        return nil, "invalid_amount"
    end
    local ok, err = Acc.playerPay(actor.src, "bank", amount)
    if not ok then
        return nil, err
    end
    Acc.add(shop, amount, "deposit", T("ledger_deposit_by", actor.name), nil, actor.name)
    VS.audit(shop.id, actor, "account.deposit", amount)
    return Acc.balance(shop)
end

--- Boss withdraws from the shop account to the personal bank account.
function Acc.withdraw(actor, shop, amount)
    amount = U.int(amount, 1, 2000000000, 0)
    if amount <= 0 then
        return nil, "invalid_amount"
    end
    local ok, err = Acc.remove(shop, amount, "withdraw", T("ledger_withdraw_by", actor.name), nil, actor.name)
    if not ok then
        return nil, err
    end
    if not Acc.playerReceive(actor.src, "bank", amount) then
        Acc.add(shop, amount, "refund", T("ledger_withdraw_failed"), nil, actor.name)
        return nil, "payment_failed"
    end
    VS.audit(shop.id, actor, "account.withdraw", amount)
    return Acc.balance(shop)
end
