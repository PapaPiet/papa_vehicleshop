Language = Language or {}

--- Roher Locale-Wert (String, Tabelle, …) ohne format.
function TR(key)
    if not key then
        return nil
    end
    local code = Config and Config.Language or "de"
    local bucket = Language[code]
    if bucket and bucket.strings and bucket.strings[key] ~= nil then
        return bucket.strings[key]
    end
    if bucket and bucket[key] ~= nil then
        return bucket[key]
    end
    -- Missing keys fall back to German, which is always complete.
    local fallback = Language["de"]
    if fallback and fallback.strings then
        return fallback.strings[key]
    end
    return nil
end

function T(text, ...)
    if not text then
        return "Error with translation"
    end

    local stringVal = TR(text)
    if type(stringVal) ~= "string" then
        stringVal = Language[Config and Config.Language or "de"] and Language[Config.Language][text]
    end

    if type(stringVal) == "string" then
        if select("#", ...) > 0 then
            return string.format(stringVal, ...)
        end
        return stringVal
    end

    return "Error with translation: " .. tostring(text)
end
