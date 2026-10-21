VS = VS or {}
VS.U = VS.U or {}

PAPA = PAPA or exports["papa_bridge"]:getObjects()

local U = VS.U

function U.now()
    return os.time() * 1000
end

function U.trim(s)
    if type(s) ~= "string" then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Trimmed string cut to maxLen characters (UTF-8 safe enough for UI input).
function U.str(value, maxLen)
    local s = U.trim(type(value) == "number" and tostring(value) or value)
    maxLen = maxLen or 255
    if #s > maxLen then
        s = s:sub(1, maxLen)
        -- Drop a trailing partial UTF-8 sequence.
        s = s:gsub("[\192-\255][\128-\191]*$", "")
    end
    return s
end

function U.optStr(value, maxLen)
    local s = U.str(value, maxLen)
    if s == "" then
        return nil
    end
    return s
end

function U.int(value, min, max, fallback)
    local n = tonumber(value)
    if not n or n ~= n then
        return fallback
    end
    n = math.floor(n + 0.5)
    if min and n < min then n = min end
    if max and n > max then n = max end
    return n
end

function U.num(value, min, max, fallback, decimals)
    local n = tonumber(value)
    if not n or n ~= n then
        return fallback
    end
    if min and n < min then n = min end
    if max and n > max then n = max end
    local f = 10 ^ (decimals or 2)
    return math.floor(n * f + 0.5) / f
end

--- "1" instead of "1.0" for log texts.
function U.fmtNum(value)
    local n = tonumber(value) or 0
    if n == math.floor(n) then
        return tostring(math.floor(n))
    end
    return (("%.2f"):format(n):gsub("0+$", ""))
end

function U.bool(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

function U.normalizePlate(plate)
    if type(plate) ~= "string" and type(plate) ~= "number" then
        return ""
    end
    return tostring(plate):gsub("%s+", ""):upper():sub(1, 16)
end

function U.jsonDecode(value, fallback)
    if type(value) == "table" then
        return value
    end
    if type(value) ~= "string" or value == "" then
        return fallback
    end
    local decoded = json.decode(value)
    if type(decoded) ~= "table" then
        return fallback
    end
    return decoded
end

function U.jsonEncode(value)
    return json.encode(value or {})
end

function U.oneOf(value, list, fallback)
    for _, v in ipairs(list) do
        if v == value then
            return value
        end
    end
    return fallback
end

function U.likeEscape(s)
    return (s:gsub("[%%_\\]", "\\%0"))
end

function U.year()
    return tonumber(os.date("%Y"))
end

--- Adds calendar months to a millisecond timestamp.
function U.addMonths(ms, months)
    local t = os.date("*t", math.floor(ms / 1000))
    t.month = t.month + months
    return os.time(t) * 1000
end

function U.formatDate(ms)
    if not ms or ms <= 0 then
        return ""
    end
    return os.date("%d.%m.%Y", math.floor(ms / 1000))
end

function U.formatDateTime(ms)
    if not ms or ms <= 0 then
        return ""
    end
    return os.date("%d.%m.%Y %H:%M", math.floor(ms / 1000))
end

function U.htmlEscape(s)
    local t = tostring(s or "")
    t = t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
    return t
end

function U.formatMoney(amount, currency)
    local n = math.floor((tonumber(amount) or 0) + 0.5)
    local negative = n < 0
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if out:sub(1, 1) == "." then
        out = out:sub(2)
    end
    return (negative and "-" or "") .. out .. " " .. (currency or Config.shopDefaults.currency or "$")
end

--- Shallow copy with nested tables copied too (settings, points).
function U.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = U.deepCopy(v)
    end
    return out
end

--- Fills missing keys of target from defaults (recursively for tables that are not arrays).
function U.withDefaults(target, defaults)
    local out = type(target) == "table" and target or {}
    for k, v in pairs(defaults or {}) do
        if out[k] == nil then
            out[k] = U.deepCopy(v)
        elseif type(v) == "table" and type(out[k]) == "table" and v[1] == nil then
            out[k] = U.withDefaults(out[k], v)
        end
    end
    return out
end

--- vector4/table -> plain table { x, y, z, w }, nil for invalid input.
function U.vec4(value)
    if type(value) ~= "table" and type(value) ~= "vector4" and type(value) ~= "vector3" then
        return nil
    end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then
        return nil
    end
    local w = tonumber(value.w) or tonumber(value.h) or 0.0
    return { x = U.num(x, nil, nil, 0, 3), y = U.num(y, nil, nil, 0, 3), z = U.num(z, nil, nil, 0, 3), w = U.num(w, nil, nil, 0, 2) }
end

function U.debug(...)
    if Config.Debug then
        print("^5[papa_vehicleshop]^0", ...)
    end
end

--- Writes one line to the audit log of a shop (shopId 0 = global/admin).
function VS.audit(shopId, actor, action, target, details)
    MySQL.insert(
        ("INSERT INTO %s (`shop_id`,`actor_id`,`actor_name`,`action`,`target`,`details_json`,`created_at`) VALUES (?,?,?,?,?,?,?)")
            :format(VS.Db.t("audit")),
        {
            tonumber(shopId) or 0,
            actor and actor.id or nil,
            actor and actor.name or nil,
            action,
            target and tostring(target):sub(1, 128) or nil,
            details and U.jsonEncode(details) or nil,
            U.now(),
        }
    )
end

-- papa_os_core exports ----------------------------------------------------------------------

local coreExports = nil

AddEventHandler("onResourceStart", function(res)
    if res == "papa_os_core" then
        coreExports = nil
    end
end)

AddEventHandler("onResourceStop", function(res)
    if res == "papa_os_core" then
        coreExports = nil
    end
end)

--- true when papa_os_core is started and declares the server export `name` in its manifest.
function U.coreHasExport(name)
    if Config.os.enabled == false or GetResourceState("papa_os_core") ~= "started" then
        return false
    end
    if not coreExports then
        coreExports = {}
        local count = GetNumResourceMetadata("papa_os_core", "server_export") or 0
        for i = 0, count - 1 do
            local exportName = GetResourceMetadata("papa_os_core", "server_export", i)
            if exportName then
                coreExports[exportName] = true
            end
        end
    end
    return coreExports[name] == true
end

function U.core()
    return exports["papa_os_core"]
end
