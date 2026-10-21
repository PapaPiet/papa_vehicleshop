--- Autohäuser, Ausstellungsplätze und Lieferorte (Häfen, Flugplätze). Alles liegt im Speicher und in der DB.

VS = VS or {}
VS.Shops = VS.Shops or {}
VS.Displays = VS.Displays or {}
VS.Points = VS.Points or {}

local U = VS.U
local S = VS.Shops
local D = VS.Displays
local P = VS.Points

S.TYPES = { "npc", "player", "mixed" }
S.POINT_KEYS = { "manage", "npc", "handover", "dropoff" }

local shops = {} -- id -> shop
local displays = {} -- id -> display
local points = {} -- id -> delivery point
local pointOrder = {}

-- Settings --------------------------------------------------------------------------------

local function defaultSettings()
    local d = U.deepCopy(Config.shopDefaults)
    d.testDrive = { enabled = Config.testDrive.enabled ~= false, seconds = Config.testDrive.seconds, deposit = Config.testDrive.deposit }
    d.finance = {
        enabled = Config.finance.enabled ~= false,
        downPaymentPercent = Config.finance.downPaymentPercent,
        installments = Config.finance.installments,
        intervalMinutes = Config.finance.intervalMinutes,
        interestPercent = Config.finance.interestPercent,
    }
    d.tradeIn = { enabled = Config.tradeIn.enabled ~= false, npcPercent = Config.tradeIn.npcPercent }
    d.npcModel = "s_m_m_autoshop_01"
    d.dropoffRadius = 7.0
    d.deliveryPoints = {}
    d.description = ""
    return d
end

--- Clamps all settings into valid ranges.
function S.normalizeSettings(input, base)
    local s = U.withDefaults(U.deepCopy(base or {}), defaultSettings())
    input = type(input) == "table" and input or {}
    local function num(key, min, max, decimals)
        if input[key] ~= nil then
            s[key] = U.num(input[key], min, max, s[key], decimals or 2)
        end
    end
    if input.currency ~= nil then
        s.currency = U.str(input.currency, 4) ~= "" and U.str(input.currency, 4) or s.currency
    end
    num("npcPriceMultiplier", 0.1, 10)
    num("wholesaleMultiplier", 0.05, 5)
    num("mixedNpcMultiplier", 0.1, 10)
    num("minStaffOnline", 1, 50, 0)
    num("commissionPercent", 0, 50)
    num("maxDiscountPercent", 0, 100)
    num("storageLimit", 0, 10000, 0)
    num("dropoffRadius", 2, 40, 1)
    if input.npcDelivery ~= nil then
        s.npcDelivery = U.bool(input.npcDelivery)
    end
    if input.npcModel ~= nil then
        local m = U.str(input.npcModel, 64)
        s.npcModel = m ~= "" and m or s.npcModel
    end
    if input.description ~= nil then
        s.description = U.str(input.description, 500)
    end
    if type(input.blip) == "table" then
        s.blip.enabled = input.blip.enabled == nil and s.blip.enabled or U.bool(input.blip.enabled)
        s.blip.sprite = U.int(input.blip.sprite, 1, 900, s.blip.sprite)
        s.blip.color = U.int(input.blip.color, 0, 85, s.blip.color)
        s.blip.scale = U.num(input.blip.scale, 0.3, 2.0, s.blip.scale)
    end
    if type(input.testDrive) == "table" then
        local t = input.testDrive
        s.testDrive.enabled = t.enabled == nil and s.testDrive.enabled or U.bool(t.enabled)
        s.testDrive.seconds = U.int(t.seconds, 30, 1800, s.testDrive.seconds)
        s.testDrive.deposit = U.int(t.deposit, 0, 10000000, s.testDrive.deposit)
    end
    if type(input.finance) == "table" then
        local f = input.finance
        s.finance.enabled = f.enabled == nil and s.finance.enabled or U.bool(f.enabled)
        s.finance.downPaymentPercent = U.num(f.downPaymentPercent, 0, 90, s.finance.downPaymentPercent)
        s.finance.installments = U.int(f.installments, 2, 100, s.finance.installments)
        s.finance.intervalMinutes = U.int(f.intervalMinutes, 5, 10080, s.finance.intervalMinutes)
        s.finance.interestPercent = U.num(f.interestPercent, 0, 100, s.finance.interestPercent)
    end
    if type(input.tradeIn) == "table" then
        local t = input.tradeIn
        s.tradeIn.enabled = t.enabled == nil and s.tradeIn.enabled or U.bool(t.enabled)
        s.tradeIn.npcPercent = U.num(t.npcPercent, 0, 100, s.tradeIn.npcPercent)
    end
    if type(input.deliveryPoints) == "table" then
        local list = {}
        for _, id in ipairs(input.deliveryPoints) do
            if type(id) == "string" and id ~= "" then
                list[#list + 1] = id
            end
        end
        s.deliveryPoints = list
    end
    return s
end

--- Settings the shop boss may change without an admin.
S.BOSS_SETTINGS = { "commissionPercent", "maxDiscountPercent", "testDrive", "finance", "tradeIn", "description", "deliveryPoints" }

local function normalizePoints(input, base)
    local out = U.deepCopy(base or {})
    input = type(input) == "table" and input or {}
    for _, key in ipairs(S.POINT_KEYS) do
        if input[key] == false then
            out[key] = nil
        elseif input[key] ~= nil then
            local v = U.vec4(input[key])
            if v then
                out[key] = v
            end
        end
    end
    return out
end

local function policyFrom(raw)
    local stored = U.jsonDecode(raw, {})
    local out = {}
    for key, def in pairs(Config.policyDefaults) do
        local v = tonumber(stored[key])
        if v == nil then
            v = def
        end
        out[key] = math.max(0, math.min(99, math.floor(v)))
    end
    return out
end

local function fromRow(row)
    local shop = {
        id = tonumber(row.id),
        label = row.label,
        type = U.oneOf(row.type, S.TYPES, "player"),
        job = row.job and row.job ~= "" and tostring(row.job):lower() or nil,
        ownerId = row.owner_id and row.owner_id ~= "" and row.owner_id or nil,
        ownerName = row.owner_name,
        balance = tonumber(row.balance) or 0,
        active = U.bool(row.active),
        settings = S.normalizeSettings({}, U.jsonDecode(row.settings_json, {})),
        points = normalizePoints({}, U.jsonDecode(row.points_json, {})),
        policy = policyFrom(row.policy_json),
        catalog = VS.Catalog.normalizeFilter(U.jsonDecode(row.catalog_json, {})),
        createdAt = tonumber(row.created_at) or 0,
        updatedAt = tonumber(row.updated_at) or 0,
    }
    return shop
end

function S.load()
    shops = {}
    for _, row in ipairs(MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("shops"))) or {}) do
        local shop = fromRow(row)
        shops[shop.id] = shop
    end
end

function S.get(id)
    return shops[tonumber(id) or -1]
end

function S.all()
    local list = {}
    for _, shop in pairs(shops) do
        list[#list + 1] = shop
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

--- Active shops with staff (player or mixed) for a job.
function S.byJob(job)
    local out = {}
    if type(job) ~= "string" or job == "" then
        return out
    end
    job = job:lower()
    for _, shop in ipairs(S.all()) do
        if shop.active and shop.job == job and shop.type ~= "npc" then
            out[#out + 1] = shop
        end
    end
    return out
end

--- All jobs that run a shop (for the Papa OS app visibility).
function S.jobs()
    local seen, out = {}, {}
    for _, shop in pairs(shops) do
        if shop.active and shop.job and shop.type ~= "npc" and not seen[shop.job] then
            seen[shop.job] = true
            out[#out + 1] = shop.job
        end
    end
    table.sort(out)
    return out
end

--- Framework garage name for a shop's storage.
function S.garage(shop)
    return (Config.delivery.garagePrefix or "papa_vs_") .. tostring(shop.id)
end

local function persist(shop)
    shop.updatedAt = U.now()
    MySQL.update.await(
        ([[UPDATE %s SET `label`=?,`type`=?,`job`=?,`owner_id`=?,`owner_name`=?,`active`=?,`settings_json`=?,
           `points_json`=?,`policy_json`=?,`catalog_json`=?,`updated_at`=? WHERE `id`=?]]):format(VS.Db.t("shops")),
        {
            shop.label, shop.type, shop.job, shop.ownerId, shop.ownerName, shop.active and 1 or 0,
            U.jsonEncode(shop.settings), U.jsonEncode(shop.points), U.jsonEncode(shop.policy), U.jsonEncode(shop.catalog),
            shop.updatedAt, shop.id,
        }
    )
end

local function validateCore(input, base)
    local label = U.str(input.label, 64)
    if label == "" then
        label = base and base.label or ""
    end
    if label == "" then
        return nil, "label_required"
    end
    local shopType = U.oneOf(input.type, S.TYPES, base and base.type or "player")
    local job = input.job ~= nil and U.str(input.job, 64):lower() or (base and base.job or "")
    if shopType ~= "npc" and job == "" then
        return nil, "job_required"
    end
    if shopType == "npc" then
        job = ""
    end
    return { label = label, type = shopType, job = job ~= "" and job or nil }
end

--- Resolves an owner identifier to a display name (online or offline).
function S.ownerName(identifier)
    if not identifier then
        return nil
    end
    local snap = PAPA.Functions.getOfflinePlayerSnapshot and PAPA.Functions.getOfflinePlayerSnapshot(identifier)
    if snap and snap.name and snap.name ~= "" then
        return snap.name
    end
    return identifier
end

function S.create(input, actor)
    if type(input) ~= "table" then
        return nil, "invalid"
    end
    local core, err = validateCore(input, nil)
    if not core then
        return nil, err
    end
    local now = U.now()
    local ownerId = U.optStr(input.ownerId, 64)
    local settings = S.normalizeSettings(input.settings, {})
    local id = MySQL.insert.await(
        ([[INSERT INTO %s (`label`,`type`,`job`,`owner_id`,`owner_name`,`balance`,`active`,`settings_json`,`points_json`,`policy_json`,`catalog_json`,`created_at`,`updated_at`)
           VALUES (?,?,?,?,?,0,1,?,?,?,?,?,?)]]):format(VS.Db.t("shops")),
        {
            core.label, core.type, core.job, ownerId, S.ownerName(ownerId),
            U.jsonEncode(settings), U.jsonEncode(normalizePoints(input.points, {})), U.jsonEncode({}),
            U.jsonEncode(VS.Catalog.normalizeFilter(input.catalog)), now, now,
        }
    )
    if not id then
        return nil, "db_error"
    end
    local row = MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("shops")), { id })
    local shop = fromRow(row)
    shops[shop.id] = shop
    VS.audit(shop.id, actor, "shop.create", shop.label, { type = shop.type, job = shop.job })
    VS.Sync.shop(shop.id)
    TriggerEvent("papa_vehicleshop:server:shopsChanged")
    return shop
end

--- Admin update (all fields).
function S.update(id, input, actor)
    local shop = S.get(id)
    if not shop then
        return nil, "not_found"
    end
    input = type(input) == "table" and input or {}
    local core, err = validateCore(input, shop)
    if not core then
        return nil, err
    end
    shop.label, shop.type, shop.job = core.label, core.type, core.job
    if input.ownerId ~= nil then
        local ownerId = U.optStr(input.ownerId, 64)
        if ownerId ~= shop.ownerId then
            shop.ownerId = ownerId
            shop.ownerName = S.ownerName(ownerId)
        end
    end
    if input.active ~= nil then
        shop.active = U.bool(input.active)
    end
    if input.settings ~= nil then
        shop.settings = S.normalizeSettings(input.settings, shop.settings)
    end
    if input.points ~= nil then
        shop.points = normalizePoints(input.points, shop.points)
    end
    if input.catalog ~= nil then
        shop.catalog = VS.Catalog.normalizeFilter(input.catalog)
    end
    if input.policy ~= nil then
        S.setPolicy(shop, input.policy)
    end
    persist(shop)
    VS.audit(shop.id, actor, "shop.update", shop.label)
    VS.Sync.shop(shop.id)
    TriggerEvent("papa_vehicleshop:server:shopsChanged")
    return shop
end

--- Boss update: only the settings in S.BOSS_SETTINGS.
function S.updateByBoss(shop, input, actor)
    local filtered = {}
    for _, key in ipairs(S.BOSS_SETTINGS) do
        if type(input) == "table" and input[key] ~= nil then
            filtered[key] = input[key]
        end
    end
    shop.settings = S.normalizeSettings(filtered, shop.settings)
    persist(shop)
    VS.audit(shop.id, actor, "shop.settings", shop.label)
    VS.Sync.shop(shop.id)
    return shop
end

function S.setPolicy(shop, input)
    local out = {}
    for key, def in pairs(Config.policyDefaults) do
        local v = tonumber(type(input) == "table" and input[key])
        if v == nil then
            v = shop.policy[key] or def
        end
        out[key] = math.max(0, math.min(99, math.floor(v)))
    end
    shop.policy = out
    persist(shop)
    return out
end

function S.setPoint(id, key, coords, actor)
    local shop = S.get(id)
    if not shop then
        return nil, "not_found"
    end
    if not U.oneOf(key, S.POINT_KEYS, nil) then
        return nil, "invalid"
    end
    if coords == false then
        shop.points[key] = nil
    else
        local v = U.vec4(coords)
        if not v then
            return nil, "invalid_coords"
        end
        shop.points[key] = v
    end
    persist(shop)
    VS.audit(shop.id, actor, "shop.point", key)
    VS.Sync.shop(shop.id)
    return shop
end

--- Shops are only deleted when nothing is left in stock; otherwise they are deactivated.
function S.delete(id, actor)
    local shop = S.get(id)
    if not shop then
        return nil, "not_found"
    end
    local count = MySQL.scalar.await(
        ("SELECT COUNT(*) FROM %s WHERE `shop_id` = ? AND `status` NOT IN ('sold','removed')"):format(VS.Db.t("stock")),
        { shop.id }
    ) or 0
    if tonumber(count) > 0 then
        shop.active = false
        persist(shop)
        VS.audit(shop.id, actor, "shop.deactivate", shop.label)
        VS.Sync.shop(shop.id)
        TriggerEvent("papa_vehicleshop:server:shopsChanged")
        return { deactivated = true }
    end
    MySQL.query.await(("DELETE FROM %s WHERE `shop_id` = ?"):format(VS.Db.t("displays")), { shop.id })
    MySQL.query.await(("DELETE FROM %s WHERE `id` = ?"):format(VS.Db.t("shops")), { shop.id })
    for did, d in pairs(displays) do
        if d.shopId == shop.id then
            displays[did] = nil
        end
    end
    shops[shop.id] = nil
    VS.audit(shop.id, actor, "shop.delete", shop.label)
    VS.Sync.removeShop(shop.id)
    TriggerEvent("papa_vehicleshop:server:shopsChanged")
    return { deleted = true }
end

function S.setBalance(shop, balance)
    shop.balance = balance
end

-- Staff on duty / NPC mode ------------------------------------------------------------------

local onDuty = {} -- job -> count

function S.refreshDuty()
    local counts = {}
    for _, snap in ipairs(PAPA.Functions.getAllPlayerSnapshots() or {}) do
        local job = snap.job and snap.job.name and tostring(snap.job.name):lower()
        if job and snap.job.onDuty ~= false then
            counts[job] = (counts[job] or 0) + 1
        end
    end
    local changed = false
    for _, shop in pairs(shops) do
        if shop.job then
            local before = onDuty[shop.job] or 0
            if before ~= (counts[shop.job] or 0) then
                changed = true
            end
        end
    end
    onDuty = counts
    if changed then
        for _, shop in pairs(shops) do
            if shop.type == "mixed" then
                VS.Sync.shop(shop.id)
            end
        end
    end
end

function S.staffOnDuty(shop)
    if not shop or not shop.job then
        return 0
    end
    return onDuty[shop.job] or 0
end

--- true when the NPC seller works (NPC shop always, mixed shop without enough staff).
function S.npcActive(shop)
    if not shop or not shop.active then
        return false
    end
    if shop.type == "npc" then
        return true
    elseif shop.type == "mixed" then
        return S.staffOnDuty(shop) < (shop.settings.minStaffOnline or 1)
    end
    return false
end

--- Price factor of the NPC seller.
function S.npcMultiplier(shop)
    if shop.type == "mixed" then
        return shop.settings.mixedNpcMultiplier or 1.0
    end
    return shop.settings.npcPriceMultiplier or 1.0
end

AddEventHandler("papa_bridge:s:playerDataChanged", function(_, kind)
    if kind == "loaded" or kind == "unloaded" or kind == "job" or kind == "duty" then
        SetTimeout(500, S.refreshDuty)
    end
end)

AddEventHandler("playerDropped", function()
    SetTimeout(1000, S.refreshDuty)
end)

CreateThread(function()
    while true do
        Wait(30000)
        if VS.Db.ready then
            S.refreshDuty()
        end
    end
end)

-- Displays ----------------------------------------------------------------------------------

D.KINDS = { "stock", "showcase" }

local function normalizeSign(input, base)
    local s = U.deepCopy(base or { enabled = true, offset = U.deepCopy(Config.sign.offset) })
    input = type(input) == "table" and input or {}
    if input.enabled ~= nil then
        s.enabled = U.bool(input.enabled)
    end
    if type(input.offset) == "table" then
        s.offset = {
            x = U.num(input.offset.x, -15, 15, s.offset.x),
            y = U.num(input.offset.y, -15, 15, s.offset.y),
            z = U.num(input.offset.z, -5, 5, s.offset.z),
            h = U.num(input.offset.h, -360, 360, s.offset.h),
        }
    end
    if input.world ~= nil then
        -- Absolute position of the sign (set "at my position" in the editor); nil = offset from the spot
        s.world = input.world and U.vec4(input.world) or nil
    end
    return s
end

local function normalizeTypes(list)
    local out = {}
    for _, t in ipairs(type(list) == "table" and list or {}) do
        if VS.isType(t) then
            out[#out + 1] = t
        end
    end
    if #out == 0 then
        out = U.deepCopy(Config.display.defaultTypes)
    end
    return out
end

local function displayFromRow(row)
    return {
        id = tonumber(row.id),
        shopId = tonumber(row.shop_id),
        label = row.label or "",
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        h = tonumber(row.h) or 0.0,
        types = normalizeTypes(U.jsonDecode(row.types_json, {})),
        sign = normalizeSign({}, U.jsonDecode(row.sign_json, nil)),
        kind = U.oneOf(row.kind, D.KINDS, "stock"),
        stockId = tonumber(row.stock_id),
        showcaseModel = row.showcase_model,
        showcaseColor = tonumber(row.showcase_color),
        turntable = U.bool(row.turntable),
        sort = tonumber(row.sort) or 0,
    }
end

function D.load()
    displays = {}
    for _, row in ipairs(MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("displays"))) or {}) do
        local d = displayFromRow(row)
        displays[d.id] = d
    end
end

function D.get(id)
    return displays[tonumber(id) or -1]
end

function D.forShop(shopId)
    local out = {}
    for _, d in pairs(displays) do
        if d.shopId == shopId then
            out[#out + 1] = d
        end
    end
    table.sort(out, function(a, b)
        if a.sort ~= b.sort then
            return a.sort < b.sort
        end
        return a.id < b.id
    end)
    return out
end

function D.all()
    local out = {}
    for _, d in pairs(displays) do
        out[#out + 1] = d
    end
    return out
end

local function persistDisplay(d)
    MySQL.update.await(
        ([[UPDATE %s SET `label`=?,`x`=?,`y`=?,`z`=?,`h`=?,`types_json`=?,`sign_json`=?,`kind`=?,`stock_id`=?,
           `showcase_model`=?,`showcase_color`=?,`turntable`=?,`sort`=? WHERE `id`=?]]):format(VS.Db.t("displays")),
        {
            d.label, d.x, d.y, d.z, d.h, U.jsonEncode(d.types), U.jsonEncode(d.sign), d.kind, d.stockId,
            d.showcaseModel, d.showcaseColor, d.turntable and 1 or 0, d.sort, d.id,
        }
    )
end

function D.create(shopId, input, actor)
    local shop = S.get(shopId)
    if not shop then
        return nil, "not_found"
    end
    input = type(input) == "table" and input or {}
    local pos = U.vec4(input.coords or input)
    if not pos then
        return nil, "invalid_coords"
    end
    local kind = U.oneOf(input.kind, D.KINDS, shop.type == "npc" and "showcase" or "stock")
    local id = MySQL.insert.await(
        ([[INSERT INTO %s (`shop_id`,`label`,`x`,`y`,`z`,`h`,`types_json`,`sign_json`,`kind`,`turntable`,`sort`,`created_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]]):format(VS.Db.t("displays")),
        {
            shop.id, U.str(input.label, 64), pos.x, pos.y, pos.z, pos.w,
            U.jsonEncode(normalizeTypes(input.types)), U.jsonEncode(normalizeSign(input.sign, nil)), kind,
            U.bool(input.turntable) and 1 or 0, U.int(input.sort, -1000, 1000, 0), U.now(),
        }
    )
    if not id then
        return nil, "db_error"
    end
    local d = displayFromRow(MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("displays")), { id }))
    displays[d.id] = d
    VS.audit(shop.id, actor, "display.create", d.id)
    VS.Sync.display(d.id)
    return d
end

function D.update(id, input, actor)
    local d = D.get(id)
    if not d then
        return nil, "not_found"
    end
    input = type(input) == "table" and input or {}
    if input.label ~= nil then
        d.label = U.str(input.label, 64)
    end
    if input.coords ~= nil then
        local pos = U.vec4(input.coords)
        if not pos then
            return nil, "invalid_coords"
        end
        d.x, d.y, d.z, d.h = pos.x, pos.y, pos.z, pos.w
    end
    if input.types ~= nil then
        d.types = normalizeTypes(input.types)
    end
    if input.sign ~= nil then
        d.sign = normalizeSign(input.sign, d.sign)
    end
    if input.turntable ~= nil then
        d.turntable = U.bool(input.turntable)
    end
    if input.sort ~= nil then
        d.sort = U.int(input.sort, -1000, 1000, d.sort)
    end
    if input.kind ~= nil then
        local kind = U.oneOf(input.kind, D.KINDS, d.kind)
        if kind ~= d.kind then
            if d.stockId then
                return nil, "display_occupied"
            end
            d.kind = kind
        end
    end
    if d.kind == "showcase" then
        if input.showcaseModel ~= nil then
            local model = U.str(input.showcaseModel, 64):lower()
            if model ~= "" then
                local entry = VS.Catalog.get(model)
                if not entry then
                    return nil, "not_in_catalog"
                end
                if not VS.typeAllowed(d.types, entry.vtype) then
                    return nil, "type_not_allowed"
                end
            end
            d.showcaseModel = model ~= "" and model or nil
        end
        if input.showcaseColor ~= nil then
            d.showcaseColor = U.int(input.showcaseColor, 0, 160, nil)
        end
    end
    persistDisplay(d)
    VS.audit(d.shopId, actor, "display.update", d.id)
    VS.Sync.display(d.id)
    return d
end

--- Internal: links or unlinks a stock vehicle (no audit, caller logs).
function D.setStock(d, stockId)
    d.stockId = stockId
    persistDisplay(d)
    VS.Sync.display(d.id)
end

function D.delete(id, actor)
    local d = D.get(id)
    if not d then
        return nil, "not_found"
    end
    if d.stockId then
        return nil, "display_occupied"
    end
    MySQL.query.await(("DELETE FROM %s WHERE `id` = ?"):format(VS.Db.t("displays")), { d.id })
    displays[d.id] = nil
    VS.audit(d.shopId, actor, "display.delete", d.id)
    VS.Sync.removeDisplay(d.id)
    return true
end

-- Delivery points ---------------------------------------------------------------------------

local function vecList(list)
    local out = {}
    for _, v in ipairs(type(list) == "table" and list or {}) do
        local p = U.vec4(v)
        if p then
            out[#out + 1] = p
        end
    end
    return out
end

local function pointFromRow(row)
    local blip = U.jsonDecode(row.blip_json, {})
    return {
        id = row.id,
        label = row.label,
        types = normalizeTypes(U.jsonDecode(row.types_json, {})),
        interact = U.vec4(U.jsonDecode(row.interact_json, {})),
        npc = row.npc,
        blip = { sprite = tonumber(blip.sprite) or 410, color = tonumber(blip.color) or 3, scale = tonumber(blip.scale) or 0.75, enabled = blip.enabled ~= false },
        spawns = vecList(U.jsonDecode(row.spawns_json, {})),
        waterSpawns = vecList(U.jsonDecode(row.water_json, {})),
        airSpawns = vecList(U.jsonDecode(row.air_json, {})),
        enabled = U.bool(row.enabled),
    }
end

local function persistPoint(p)
    MySQL.query.await(
        ([[INSERT INTO %s (`id`,`label`,`types_json`,`interact_json`,`npc`,`blip_json`,`spawns_json`,`water_json`,`air_json`,`enabled`,`updated_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)
           ON DUPLICATE KEY UPDATE `label`=VALUES(`label`),`types_json`=VALUES(`types_json`),`interact_json`=VALUES(`interact_json`),
           `npc`=VALUES(`npc`),`blip_json`=VALUES(`blip_json`),`spawns_json`=VALUES(`spawns_json`),`water_json`=VALUES(`water_json`),
           `air_json`=VALUES(`air_json`),`enabled`=VALUES(`enabled`),`updated_at`=VALUES(`updated_at`)]]):format(VS.Db.t("delivery_points")),
        {
            p.id, p.label, U.jsonEncode(p.types), U.jsonEncode(p.interact), p.npc, U.jsonEncode(p.blip),
            U.jsonEncode(p.spawns), U.jsonEncode(p.waterSpawns), U.jsonEncode(p.airSpawns), p.enabled and 1 or 0, U.now(),
        }
    )
end

local function rebuildPointOrder()
    pointOrder = {}
    for _, p in pairs(points) do
        pointOrder[#pointOrder + 1] = p
    end
    table.sort(pointOrder, function(a, b)
        return a.label < b.label
    end)
end

function P.load()
    points = {}
    local rows = MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("delivery_points"))) or {}
    if #rows == 0 then
        for _, cfg in ipairs(Config.deliveryPoints or {}) do
            persistPoint({
                id = cfg.id, label = cfg.label, types = cfg.types, interact = U.vec4(cfg.interact), npc = cfg.npc,
                blip = cfg.blip or {}, spawns = vecList(cfg.spawns), waterSpawns = vecList(cfg.waterSpawns),
                airSpawns = vecList(cfg.airSpawns), enabled = true,
            })
        end
        rows = MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("delivery_points"))) or {}
    end
    for _, row in ipairs(rows) do
        local p = pointFromRow(row)
        points[p.id] = p
    end
    rebuildPointOrder()
end

function P.get(id)
    return points[id]
end

function P.all()
    return pointOrder
end

--- Delivery points that accept a vehicle type and that the shop may use.
function P.forType(shop, vehicleType)
    local out = {}
    local allowed = shop and shop.settings.deliveryPoints or {}
    for _, p in ipairs(pointOrder) do
        if p.enabled and VS.typeAllowed(p.types, vehicleType) and (#allowed == 0 or U.oneOf(p.id, allowed, nil)) then
            local area = VS.spawnArea(vehicleType)
            local slots = area == "water" and p.waterSpawns or area == "air" and p.airSpawns or p.spawns
            if #slots > 0 then
                out[#out + 1] = p
            end
        end
    end
    return out
end

function P.save(input, actor)
    if type(input) ~= "table" then
        return nil, "invalid"
    end
    local id = U.str(input.id, 32):lower():gsub("[^%w_%-]", "")
    if id == "" then
        return nil, "invalid"
    end
    local base = points[id] or { spawns = {}, waterSpawns = {}, airSpawns = {}, blip = { sprite = 410, color = 3, scale = 0.75, enabled = true }, enabled = true }
    local p = {
        id = id,
        label = U.str(input.label, 64) ~= "" and U.str(input.label, 64) or (base.label or id),
        types = input.types ~= nil and normalizeTypes(input.types) or base.types or normalizeTypes({}),
        interact = input.interact ~= nil and U.vec4(input.interact) or base.interact,
        npc = input.npc ~= nil and U.optStr(input.npc, 64) or base.npc,
        blip = base.blip,
        spawns = input.spawns ~= nil and vecList(input.spawns) or base.spawns,
        waterSpawns = input.waterSpawns ~= nil and vecList(input.waterSpawns) or base.waterSpawns,
        airSpawns = input.airSpawns ~= nil and vecList(input.airSpawns) or base.airSpawns,
        enabled = input.enabled == nil and base.enabled ~= false or U.bool(input.enabled),
    }
    if type(input.blip) == "table" then
        p.blip = {
            enabled = input.blip.enabled == nil and base.blip.enabled ~= false or U.bool(input.blip.enabled),
            sprite = U.int(input.blip.sprite, 1, 900, base.blip.sprite or 410),
            color = U.int(input.blip.color, 0, 85, base.blip.color or 3),
            scale = U.num(input.blip.scale, 0.3, 2.0, base.blip.scale or 0.75),
        }
    end
    if not p.interact then
        return nil, "invalid_coords"
    end
    persistPoint(p)
    points[id] = p
    rebuildPointOrder()
    VS.audit(0, actor, "point.save", id)
    VS.Sync.points()
    return p
end

function P.delete(id, actor)
    if not points[id] then
        return nil, "not_found"
    end
    MySQL.query.await(("DELETE FROM %s WHERE `id` = ?"):format(VS.Db.t("delivery_points")), { id })
    points[id] = nil
    rebuildPointOrder()
    VS.audit(0, actor, "point.delete", id)
    VS.Sync.points()
    return true
end

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    S.load()
    D.load()
    P.load()
    S.refreshDuty()
end)
