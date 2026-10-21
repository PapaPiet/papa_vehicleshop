--- Globaler Fahrzeugkatalog (vom Admin gepflegt) und die Filter je Autohaus (Whitelist / Blacklist).

VS = VS or {}
VS.Catalog = VS.Catalog or {}

local U = VS.U
local C = VS.Catalog

local entries = {} -- model -> entry
local ordered = {} -- sorted list

local globalBlocked = {}
for _, model in ipairs(Config.globalBlacklist or {}) do
    globalBlocked[tostring(model):lower()] = true
end

local function categoryIndex(category)
    for i, c in ipairs(Config.categories or {}) do
        if c == category then
            return i
        end
    end
    return 999
end

local function rebuild()
    ordered = {}
    for _, e in pairs(entries) do
        ordered[#ordered + 1] = e
    end
    table.sort(ordered, function(a, b)
        local ca, cb = categoryIndex(a.category), categoryIndex(b.category)
        if ca ~= cb then
            return ca < cb
        end
        if a.price ~= b.price then
            return a.price < b.price
        end
        return a.label < b.label
    end)
end

local function fromRow(row)
    return {
        model = tostring(row.model):lower(),
        label = row.label or row.model,
        brand = row.brand or "",
        category = row.category or "other",
        vtype = VS.isType(row.vtype) and row.vtype or "car",
        price = tonumber(row.price) or 0,
        minutes = tonumber(row.minutes),
        enabled = U.bool(row.enabled),
        image = row.image,
        blocked = globalBlocked[tostring(row.model):lower()] == true,
    }
end

function C.load()
    entries = {}
    local rows = MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("catalog"))) or {}
    if #rows == 0 and Config.seedCatalog ~= false then
        local now = U.now()
        for _, seed in ipairs(Config.catalogSeed or {}) do
            MySQL.insert.await(
                ("INSERT IGNORE INTO %s (`model`,`label`,`brand`,`category`,`vtype`,`price`,`minutes`,`enabled`,`updated_at`) VALUES (?,?,?,?,?,?,?,1,?)")
                    :format(VS.Db.t("catalog")),
                { tostring(seed.model):lower(), seed.label, seed.brand or "", seed.category or "other", seed.type or "car", tonumber(seed.price) or 0, seed.minutes, now }
            )
        end
        rows = MySQL.query.await(("SELECT * FROM %s"):format(VS.Db.t("catalog"))) or {}
        print(("^2[papa_vehicleshop] %s^0"):format(T("console_catalog_seeded", #rows)))
    end
    for _, row in ipairs(rows) do
        local e = fromRow(row)
        entries[e.model] = e
    end
    rebuild()
end

function C.get(model)
    if type(model) ~= "string" then
        return nil
    end
    return entries[model:lower()]
end

function C.all()
    return ordered
end

function C.isGloballyBlocked(model)
    return globalBlocked[tostring(model or ""):lower()] == true
end

--- Delivery time in minutes for an entry (catalog value or default per type).
function C.minutes(entry)
    if entry and tonumber(entry.minutes) and entry.minutes > 0 then
        return entry.minutes
    end
    local vtype = entry and entry.vtype or "car"
    return tonumber(Config.delivery.defaultMinutes[vtype]) or 45
end

--- Shop filter: { mode = "all"|"whitelist"|"blacklist", models = {}, categories = {}, types = {} }
function C.normalizeFilter(filter)
    filter = type(filter) == "table" and filter or {}
    local out = {
        mode = U.oneOf(filter.mode, { "all", "whitelist", "blacklist" }, "all"),
        models = {},
        categories = {},
        types = {},
    }
    local seen = {}
    for _, m in ipairs(type(filter.models) == "table" and filter.models or {}) do
        local s = U.str(m, 64):lower()
        if s ~= "" and not seen[s] then
            seen[s] = true
            out.models[#out.models + 1] = s
        end
    end
    for _, c in ipairs(type(filter.categories) == "table" and filter.categories or {}) do
        local s = U.str(c, 32)
        if s ~= "" then
            out.categories[#out.categories + 1] = s
        end
    end
    for _, ty in ipairs(type(filter.types) == "table" and filter.types or {}) do
        if VS.isType(ty) then
            out.types[#out.types + 1] = ty
        end
    end
    return out
end

local function listHas(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

--- true when the shop may sell / order the entry.
function C.allowedForShop(shop, entry)
    if not entry or not entry.enabled or entry.blocked then
        return false
    end
    local f = shop and shop.catalog or { mode = "all" }
    if #f.types > 0 and not listHas(f.types, entry.vtype) then
        return false
    end
    local listed = listHas(f.models, entry.model) or listHas(f.categories, entry.category)
    if f.mode == "whitelist" then
        return listed
    elseif f.mode == "blacklist" then
        return not listed
    end
    return true
end

--- Catalog entries a shop may use.
function C.forShop(shop)
    local out = {}
    for _, e in ipairs(ordered) do
        if C.allowedForShop(shop, e) then
            out[#out + 1] = e
        end
    end
    return out
end

--- Admin: create or update an entry.
function C.save(input, actor)
    if type(input) ~= "table" then
        return nil, "invalid"
    end
    local model = U.str(input.model, 64):lower()
    if model == "" or not model:match("^[%w_%-]+$") then
        return nil, "invalid_model"
    end
    local label = U.str(input.label, 96)
    if label == "" then
        label = model
    end
    local entry = {
        model = model,
        label = label,
        brand = U.str(input.brand, 64),
        category = U.str(input.category, 32) ~= "" and U.str(input.category, 32) or "other",
        vtype = VS.isType(input.vtype) and input.vtype or "car",
        price = U.int(input.price, 0, 2000000000, 0),
        minutes = U.int(input.minutes, 0, 100000, nil),
        enabled = input.enabled ~= false,
        image = U.optStr(input.image, 255),
    }
    if entry.minutes == 0 then
        entry.minutes = nil
    end
    MySQL.query.await(
        ([[INSERT INTO %s (`model`,`label`,`brand`,`category`,`vtype`,`price`,`minutes`,`enabled`,`image`,`updated_at`)
           VALUES (?,?,?,?,?,?,?,?,?,?)
           ON DUPLICATE KEY UPDATE `label`=VALUES(`label`),`brand`=VALUES(`brand`),`category`=VALUES(`category`),
           `vtype`=VALUES(`vtype`),`price`=VALUES(`price`),`minutes`=VALUES(`minutes`),`enabled`=VALUES(`enabled`),
           `image`=VALUES(`image`),`updated_at`=VALUES(`updated_at`)]]):format(VS.Db.t("catalog")),
        { entry.model, entry.label, entry.brand, entry.category, entry.vtype, entry.price, entry.minutes, entry.enabled and 1 or 0, entry.image, U.now() }
    )
    entry.blocked = C.isGloballyBlocked(model)
    entries[model] = entry
    rebuild()
    VS.audit(0, actor, "catalog.save", model, { price = entry.price, enabled = entry.enabled })
    return entry
end

function C.delete(model, actor)
    model = U.str(model, 64):lower()
    if not entries[model] then
        return nil, "not_found"
    end
    MySQL.query.await(("DELETE FROM %s WHERE `model` = ?"):format(VS.Db.t("catalog")), { model })
    entries[model] = nil
    rebuild()
    VS.audit(0, actor, "catalog.delete", model)
    return true
end

--- Admin: re-import the seed (adds missing models, keeps existing ones).
function C.importSeed(actor)
    local added = 0
    for _, seed in ipairs(Config.catalogSeed or {}) do
        local model = tostring(seed.model):lower()
        if not entries[model] then
            C.save({ model = model, label = seed.label, brand = seed.brand, category = seed.category, vtype = seed.type, price = seed.price, minutes = seed.minutes, enabled = true }, actor)
            added = added + 1
        end
    end
    return added
end

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    C.load()
end)
