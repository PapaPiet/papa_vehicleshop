--- Eine RPC-Schnittstelle für das Dashboard (Papa OS App) und den Admin-Bereich (OS-Admin).
--- Client: papa_vehicleshop:server:rpc(reqId, { action, shopId, ... }) -> papa_vehicleshop:client:rpcResult(reqId, result)

VS = VS or {}

local U = VS.U
local A = VS.Access
local S = VS.Shops
local D = VS.Displays
local P = VS.Points
local St = VS.Stock
local L = VS.Logistics
local Sa = VS.Sales
local F = VS.Finance
local Ti = VS.TradeIn
local Acc = VS.Account
local C = VS.Catalog

local handlers = {}
local adminHandlers = {}

--- All texts of the active language; the UI uses the same keys as T().
local function localeStrings()
    local out = {}
    local base = Language and Language["de"]
    for k, v in pairs(base and base.strings or {}) do
        out[k] = v
    end
    local bucket = Language and Language[Config.Language or "de"]
    for k, v in pairs(bucket and bucket.strings or {}) do
        out[k] = v
    end
    return out
end

local function fail(code)
    code = tostring(code or "unknown")
    if type(TR("err_" .. code)) ~= "string" then
        code = "unknown"
    end
    return { ok = false, error = code, message = T("err_" .. code) }
end

local function okData(data, extra)
    local out = { ok = true, data = data }
    if extra then
        for k, v in pairs(extra) do
            out[k] = v
        end
    end
    return out
end

local function wrap(value, err)
    if value == nil or value == false then
        return fail(err or "unknown")
    end
    return okData(value)
end

local function need(actor, shop, key)
    if not A.can(actor, shop, key) then
        return fail("no_permission")
    end
    return nil
end

local function needBoss(actor, shop)
    if not A.isBoss(actor, shop) then
        return fail("no_permission")
    end
    return nil
end

local function stockOf(shop, id)
    local s = St.get(id)
    if not s or s.shopId ~= shop.id then
        return nil
    end
    return s
end

local function meta()
    local types = {}
    for _, t in ipairs(VS.TYPE_ORDER) do
        types[#types + 1] = t
    end
    local points = {}
    for _, p in ipairs(P.all()) do
        points[#points + 1] = { id = p.id, label = p.label, types = p.types, enabled = p.enabled }
    end
    return {
        types = types,
        categories = Config.categories,
        statuses = St.STATUS,
        policyKeys = A.POLICY_KEYS,
        points = points,
        methods = Config.purchase.methods,
        cancelFeePercent = St.CANCEL_FEE_PERCENT,
        contractsEnabled = Config.contracts.enabled == true,
        maxMissed = Config.finance.maxMissed,
    }
end

local function shopSummary(shop)
    return {
        id = shop.id, label = shop.label, type = shop.type, job = shop.job, ownerId = shop.ownerId, ownerName = shop.ownerName,
        active = shop.active, npcActive = S.npcActive(shop), staffOnDuty = S.staffOnDuty(shop),
    }
end

-- Session -------------------------------------------------------------------------------

handlers["session"] = function(actor, shop)
    local list = {}
    for _, s in ipairs(A.shopsOf(actor)) do
        list[#list + 1] = shopSummary(s)
    end
    return okData({
        actor = { id = actor.id, name = actor.name, grade = actor.grade, gradeLabel = actor.gradeLabel, isBoss = actor.isBoss, isAdmin = actor.isAdmin },
        shops = list,
        shop = shopSummary(shop),
        settings = shop.settings,
        points = shop.points,
        flags = A.flags(actor, shop),
        strings = localeStrings(),
        meta = meta(),
        dateTimeFormat = U.coreHasExport("GetDateTimeFormatConfig") and U.core():GetDateTimeFormatConfig() or nil,
        uiCache = Config.UiCache ~= false,
        resourceVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "",
    })
end

handlers["dashboard"] = function(actor, shop)
    local counts = St.counts(shop.id)
    local arrivals = {}
    for _, s in ipairs(St.forShop(shop.id, { "transit" })) do
        arrivals[#arrivals + 1] = St.view(s)
    end
    table.sort(arrivals, function(a, b)
        return a.eta < b.eta
    end)
    while #arrivals > 6 do
        table.remove(arrivals)
    end
    local waiting = {}
    for _, s in ipairs(St.forShop(shop.id, { "waiting" })) do
        waiting[#waiting + 1] = St.view(s)
    end
    local overdue = 0
    for _, f in ipairs(F.forShop(shop, { "defaulted" })) do
        overdue = overdue + 1
    end
    local open = 0
    for _, c in ipairs(L.contractsOfShop(shop.id, false)) do
        if c.status == "open" or c.status == "taken" then
            open = open + 1
        end
    end
    local canAccount = A.can(actor, shop, "accountView")
    return okData({
        balance = canAccount and Acc.balance(shop) or nil,
        counts = counts,
        daily = Sa.daily(shop, 14),
        recentSales = Sa.list(shop, 6, 0),
        arrivals = arrivals,
        waiting = waiting,
        contractsOpen = open,
        tradeinsOpen = #Ti.listOpen(shop),
        financeDefaulted = overdue,
        staffOnDuty = S.staffOnDuty(shop),
        npcActive = S.npcActive(shop),
        displays = #D.forShop(shop.id),
        displaysUsed = (counts.display or 0) + (counts.testdrive or 0),
    })
end

-- Stock ---------------------------------------------------------------------------------

handlers["stock.list"] = function(actor, shop, d)
    local denied = need(actor, shop, "stockView")
    if denied then
        return denied
    end
    local list = {}
    local q = U.str(d.query, 48):lower()
    for _, s in ipairs(St.forShop(shop.id, type(d.statuses) == "table" and d.statuses or nil)) do
        if q == "" or (s.label or ""):lower():find(q, 1, true) or (s.plate or ""):lower():find(q, 1, true) or s.model:find(q, 1, true) then
            list[#list + 1] = St.view(s)
        end
    end
    return okData(list)
end

handlers["stock.get"] = function(actor, shop, d)
    local denied = need(actor, shop, "stockView")
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    local view = St.view(s)
    view.props = s.props
    view.damage = St.damagePercent(s)
    view.storageFee = s.status == "waiting" and St.storageFee(s) or 0
    local history = MySQL.query.await(
        ("SELECT `actor_name`,`action`,`details_json`,`created_at` FROM %s WHERE `shop_id` = ? AND `target` IN (?, ?) ORDER BY `id` DESC LIMIT 40")
            :format(VS.Db.t("audit")),
        { shop.id, tostring(s.id), s.plate or "-" }
    ) or {}
    view.history = history
    return okData(view)
end

handlers["stock.price"] = function(actor, shop, d)
    local denied = need(actor, shop, "priceEdit")
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    return wrap(St.setPrice(actor, shop, s, d.price, d.note))
end

handlers["stock.display"] = function(actor, shop, d)
    local denied = need(actor, shop, "displayManage")
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    return wrap(St.toDisplay(actor, shop, s, d.displayId))
end

handlers["stock.undisplay"] = function(actor, shop, d)
    local denied = need(actor, shop, "displayManage")
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    return wrap(St.fromDisplay(actor, shop, s))
end

handlers["stock.reserve"] = function(actor, shop, d)
    local denied = need(actor, shop, "sell")
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    local identifier, name = nil, nil
    if d.targetSrc then
        local target = A.actor(tonumber(d.targetSrc))
        if not target then
            return fail("customer_offline")
        end
        identifier, name = target.id, target.name
    end
    return wrap(St.reserve(actor, shop, s, identifier, name))
end

handlers["stock.remove"] = function(actor, shop, d)
    local denied = needBoss(actor, shop)
    if denied then
        return denied
    end
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    return wrap(St.remove(actor, shop, s, d.mode == "scrap" and "scrap" or "release"))
end

handlers["stock.recall"] = function(actor, shop, d)
    return need(actor, shop, "stockManage") or wrap(L.recall(actor, shop, d.stockId))
end

handlers["stock.cancelOrder"] = function(actor, shop, d)
    return need(actor, shop, "order") or wrap(St.cancelOrder(actor, shop, d.stockId))
end

-- Displays ------------------------------------------------------------------------------

handlers["displays.list"] = function(actor, shop)
    local out = {}
    for _, dsp in ipairs(D.forShop(shop.id)) do
        local s = dsp.stockId and St.get(dsp.stockId)
        out[#out + 1] = {
            id = dsp.id, label = dsp.label, types = dsp.types, kind = dsp.kind, turntable = dsp.turntable,
            sign = dsp.sign.enabled, x = dsp.x, y = dsp.y,
            vehicle = s and St.ACTIVE[s.status] and St.view(s) or nil,
            showcase = dsp.showcaseModel and C.get(dsp.showcaseModel) or nil,
        }
    end
    return okData(out)
end

handlers["displays.showcase"] = function(actor, shop, d)
    local denied = need(actor, shop, "displayManage")
    if denied then
        return denied
    end
    local dsp = D.get(d.displayId)
    if not dsp or dsp.shopId ~= shop.id then
        return fail("not_found")
    end
    return wrap(D.update(dsp.id, { showcaseModel = d.model or "", showcaseColor = d.color }, actor))
end

-- Catalog and orders --------------------------------------------------------------------

handlers["catalog.list"] = function(actor, shop)
    local out = {}
    for _, e in ipairs(C.forShop(shop)) do
        local pts = {}
        for _, p in ipairs(P.forType(shop, e.vtype)) do
            pts[#pts + 1] = p.id
        end
        out[#out + 1] = {
            model = e.model, label = e.label, brand = e.brand, category = e.category, vtype = e.vtype, price = e.price,
            wholesale = St.wholesale(shop, e), minutes = C.minutes(e), points = pts, image = e.image,
        }
    end
    return okData(out)
end

handlers["orders.create"] = function(actor, shop, d)
    return need(actor, shop, "order") or wrap(St.order(actor, shop, d.order))
end

-- Contracts -----------------------------------------------------------------------------

handlers["contracts.list"] = function(actor, shop, d)
    return okData(L.contractsOfShop(shop.id, d.history == true))
end

handlers["contracts.create"] = function(actor, shop, d)
    return need(actor, shop, "contracts") or wrap(L.createContract(actor, shop, d.stockId, d.reward, d.note))
end

handlers["contracts.cancel"] = function(actor, shop, d)
    return need(actor, shop, "contracts") or wrap(L.cancelContract(actor, shop, d.contractId))
end

handlers["contracts.suggest"] = function(actor, shop, d)
    local s = stockOf(shop, d.stockId)
    if not s then
        return fail("not_found")
    end
    return okData({ reward = L.suggestReward(s) })
end

-- Sales ---------------------------------------------------------------------------------

handlers["sales.list"] = function(actor, shop, d)
    return okData(Sa.list(shop, d.limit, d.offset))
end

handlers["sales.stats"] = function(actor, shop, d)
    return okData(Sa.daily(shop, d.days or 30))
end

--- Players close to the actor (server-side positions), for offers and reservations.
handlers["players.nearby"] = function(actor, shop)
    local ped = GetPlayerPed(actor.src)
    if ped == 0 then
        return okData({})
    end
    local pos = GetEntityCoords(ped)
    local out = {}
    for _, snap in ipairs(PAPA.Functions.getAllPlayerSnapshots() or {}) do
        if snap.source and snap.source ~= actor.src then
            local p = GetPlayerPed(snap.source)
            if p ~= 0 then
                local dist = #(GetEntityCoords(p) - pos)
                if dist <= 25.0 then
                    out[#out + 1] = { src = snap.source, name = snap.name, distance = math.floor(dist * 10) / 10 }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return a.distance < b.distance
    end)
    return okData(out)
end

handlers["sell.offer"] = function(actor, shop, d)
    return need(actor, shop, "sell") or wrap(Sa.offer(actor, shop, d.offer))
end

handlers["finance.preview"] = function(actor, shop, d)
    return wrap(F.plan(shop, d.price))
end

-- Trade-ins -----------------------------------------------------------------------------

handlers["tradeins.list"] = function(actor, shop)
    return need(actor, shop, "tradeIn") or okData(Ti.listOpen(shop))
end

handlers["tradeins.offer"] = function(actor, shop, d)
    return need(actor, shop, "tradeIn") or wrap(Ti.makeOffer(actor, shop, d.tradeId, d.amount))
end

handlers["tradeins.decline"] = function(actor, shop, d)
    return need(actor, shop, "tradeIn") or wrap(Ti.decline(actor, shop, d.tradeId))
end

-- Finance -------------------------------------------------------------------------------

handlers["finance.list"] = function(actor, shop)
    return need(actor, shop, "finance") or okData(F.forShop(shop))
end

handlers["finance.repossess"] = function(actor, shop, d)
    return need(actor, shop, "finance") or wrap(F.repossess(actor, shop, d.financeId))
end

-- Account -------------------------------------------------------------------------------

handlers["account.ledger"] = function(actor, shop, d)
    local denied = need(actor, shop, "accountView")
    if denied then
        return denied
    end
    return okData({ balance = Acc.balance(shop), entries = Acc.ledger(shop, d.limit, d.offset) })
end

handlers["account.deposit"] = function(actor, shop, d)
    return need(actor, shop, "accountManage") or wrap(Acc.deposit(actor, shop, d.amount))
end

handlers["account.withdraw"] = function(actor, shop, d)
    return need(actor, shop, "accountManage") or wrap(Acc.withdraw(actor, shop, d.amount))
end

-- Settings, policy, staff, audit --------------------------------------------------------

handlers["settings.save"] = function(actor, shop, d)
    local denied = need(actor, shop, "settings")
    if denied then
        return denied
    end
    S.updateByBoss(shop, d.settings, actor)
    return okData(shop.settings)
end

handlers["policy.get"] = function(actor, shop)
    local grades = {}
    if shop.job then
        grades = PAPA.Functions.getJobGrades(shop.job) or {}
    end
    return okData({ policy = shop.policy, grades = grades })
end

handlers["policy.save"] = function(actor, shop, d)
    local denied = needBoss(actor, shop)
    if denied then
        return denied
    end
    local p = S.setPolicy(shop, d.policy)
    VS.audit(shop.id, actor, "policy.save", shop.label)
    return okData(p)
end

handlers["staff.list"] = function(actor, shop)
    if shop.job and U.coreHasExport("GetEmployeeRosterForMdt") then
        return okData(U.core():GetEmployeeRosterForMdt(shop.job) or {})
    end
    local out = {}
    for _, snap in ipairs(PAPA.Functions.getAllPlayerSnapshots() or {}) do
        local job = snap.job and snap.job.name and tostring(snap.job.name):lower()
        if job == shop.job then
            out[#out + 1] = { playerId = snap.identifier, name = snap.name, gradeLabel = snap.job.gradeLabel, online = true, onDuty = snap.job.onDuty }
        end
    end
    return okData(out)
end

handlers["audit.list"] = function(actor, shop, d)
    local denied = need(actor, shop, "auditView")
    if denied then
        return denied
    end
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?"):format(VS.Db.t("audit")),
        { shop.id, U.int(d.limit, 1, 200, 80), U.int(d.offset, 0, 1000000, 0) }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, actor = r.actor_name, action = r.action, target = r.target,
            details = U.jsonDecode(r.details_json, nil), createdAt = tonumber(r.created_at) or 0,
        }
    end
    return okData(out)
end

-- Admin ---------------------------------------------------------------------------------

local function adminShopView(shop)
    local out = shopSummary(shop)
    out.settings = shop.settings
    out.points = shop.points
    out.policy = shop.policy
    out.catalog = shop.catalog
    out.balance = Acc.balance(shop)
    out.counts = St.counts(shop.id)
    out.displays = {}
    for _, dsp in ipairs(D.forShop(shop.id)) do
        local s = dsp.stockId and St.get(dsp.stockId)
        out.displays[#out.displays + 1] = {
            id = dsp.id, label = dsp.label, x = dsp.x, y = dsp.y, z = dsp.z, h = dsp.h, types = dsp.types, sign = dsp.sign,
            kind = dsp.kind, turntable = dsp.turntable, sort = dsp.sort, showcaseModel = dsp.showcaseModel, showcaseColor = dsp.showcaseColor,
            vehicle = s and St.ACTIVE[s.status] and { label = s.label, plate = s.plate, status = s.status } or nil,
        }
    end
    return out
end

adminHandlers["admin.session"] = function()
    return okData({ strings = localeStrings(), meta = meta(), currency = Config.shopDefaults.currency, defaults = { settings = S.normalizeSettings({}, {}), policy = Config.policyDefaults } })
end

adminHandlers["admin.overview"] = function()
    local out = {}
    for _, shop in ipairs(S.all()) do
        local v = shopSummary(shop)
        v.counts = St.counts(shop.id)
        v.balance = Acc.balance(shop)
        v.displays = #D.forShop(shop.id)
        out[#out + 1] = v
    end
    return okData(out)
end

adminHandlers["admin.shop.get"] = function(_, d)
    local shop = S.get(d.shopId)
    if not shop then
        return fail("not_found")
    end
    return okData(adminShopView(shop))
end

adminHandlers["admin.shop.create"] = function(actor, d)
    local shop, err = S.create(d.shop, actor)
    if not shop then
        return fail(err)
    end
    return okData(adminShopView(shop))
end

adminHandlers["admin.shop.update"] = function(actor, d)
    local shop, err = S.update(d.shopId, d.shop, actor)
    if not shop then
        return fail(err)
    end
    return okData(adminShopView(shop))
end

adminHandlers["admin.shop.delete"] = function(actor, d)
    return wrap(S.delete(d.shopId, actor))
end

adminHandlers["admin.shop.point"] = function(actor, d)
    local shop, err = S.setPoint(d.shopId, d.key, d.coords == false and false or d.coords, actor)
    if not shop then
        return fail(err)
    end
    return okData(adminShopView(shop))
end

adminHandlers["admin.shop.balance"] = function(actor, d)
    local shop = S.get(d.shopId)
    if not shop then
        return fail("not_found")
    end
    local amount = U.int(d.amount, -2000000000, 2000000000, 0)
    if amount > 0 then
        Acc.add(shop, amount, "admin", T("ledger_admin", actor.name), nil, actor.name)
    elseif amount < 0 then
        local ok, err = Acc.remove(shop, -amount, "admin", T("ledger_admin", actor.name), nil, actor.name)
        if not ok then
            return fail(err)
        end
    end
    VS.audit(shop.id, actor, "admin.balance", amount)
    return okData(adminShopView(shop))
end

adminHandlers["admin.display.create"] = function(actor, d)
    local dsp, err = D.create(d.shopId, d.display, actor)
    if not dsp then
        return fail(err)
    end
    return okData(adminShopView(S.get(dsp.shopId)))
end

adminHandlers["admin.display.update"] = function(actor, d)
    local dsp, err = D.update(d.displayId, d.display, actor)
    if not dsp then
        return fail(err)
    end
    return okData(adminShopView(S.get(dsp.shopId)))
end

adminHandlers["admin.display.delete"] = function(actor, d)
    local dsp = D.get(d.displayId)
    if not dsp then
        return fail("not_found")
    end
    local shopId = dsp.shopId
    local ok, err = D.delete(dsp.id, actor)
    if not ok then
        return fail(err)
    end
    return okData(adminShopView(S.get(shopId)))
end

adminHandlers["admin.catalog.list"] = function()
    return okData(C.all())
end

adminHandlers["admin.catalog.save"] = function(actor, d)
    local e, err = C.save(d.entry, actor)
    if not e then
        return fail(err)
    end
    VS.Sync.full(-1)
    return okData(e)
end

adminHandlers["admin.catalog.delete"] = function(actor, d)
    return wrap(C.delete(d.model, actor))
end

adminHandlers["admin.catalog.import"] = function(actor)
    return okData({ added = C.importSeed(actor) })
end

adminHandlers["admin.points.list"] = function()
    return okData(P.all())
end

adminHandlers["admin.points.save"] = function(actor, d)
    return wrap(P.save(d.point, actor))
end

adminHandlers["admin.points.delete"] = function(actor, d)
    return wrap(P.delete(d.pointId, actor))
end

adminHandlers["admin.players"] = function(_, d)
    local q = U.str(d.query, 48):lower()
    local out = {}
    for _, snap in ipairs(PAPA.Functions.getAllPlayerSnapshots() or {}) do
        local name = snap.name or ""
        if q == "" or name:lower():find(q, 1, true) or tostring(snap.identifier):lower():find(q, 1, true) then
            out[#out + 1] = { identifier = snap.identifier, name = name, job = snap.job and snap.job.name or "", src = snap.source }
        end
    end
    return okData(out)
end

adminHandlers["admin.audit"] = function(_, d)
    local rows = MySQL.query.await(
        ("SELECT * FROM %s WHERE (? = 0 OR `shop_id` = ?) ORDER BY `id` DESC LIMIT 150"):format(VS.Db.t("audit")),
        { tonumber(d.shopId) or 0, tonumber(d.shopId) or 0 }
    ) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, shopId = r.shop_id, actor = r.actor_name, action = r.action, target = r.target, createdAt = tonumber(r.created_at) or 0 }
    end
    return okData(out)
end

-- Dispatcher ----------------------------------------------------------------------------

local function dispatch(src, data)
    if type(data) ~= "table" or type(data.action) ~= "string" then
        return fail("invalid")
    end
    if not VS.Db.ready then
        return fail("db_not_ready")
    end
    local actor = A.actor(src)
    if not actor then
        return fail("no_player")
    end
    local adminHandler = adminHandlers[data.action]
    if adminHandler then
        if not actor.isAdmin then
            return fail("no_permission")
        end
        return adminHandler(actor, data)
    end
    local handler = handlers[data.action]
    if not handler then
        return fail("unknown_action")
    end
    local shops = A.shopsOf(actor)
    if #shops == 0 then
        return fail("not_dealer")
    end
    local shop = nil
    if data.shopId then
        shop = S.get(data.shopId)
        if not shop or not A.isStaff(actor, shop) then
            shop = nil
        end
    end
    shop = shop or shops[1]
    return handler(actor, shop, data)
end

VS.Rpc = { dispatch = dispatch, fail = fail, handlers = handlers, adminHandlers = adminHandlers }

--- A Lua or SQL error ends the handler without an answer. The watchdog then tells the UI right away.
local WATCHDOG_MS = 15000

RegisterNetEvent("papa_vehicleshop:server:rpc", function(reqId, data)
    local src = source
    local finished = false
    local action = type(data) == "table" and tostring(data.action) or "?"
    SetTimeout(WATCHDOG_MS, function()
        if not finished then
            print(("^1[papa_vehicleshop] %s^0"):format(T("console_rpc_failed", action, tostring(src))))
            TriggerClientEvent("papa_vehicleshop:client:rpcResult", src, reqId, fail("server_error"))
        end
    end)
    local result = dispatch(src, data)
    finished = true
    TriggerClientEvent("papa_vehicleshop:client:rpcResult", src, reqId, result)
end)
