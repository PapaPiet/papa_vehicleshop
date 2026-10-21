-- Prüft beim Start die Mindestversionen der Abhängigkeiten.
-- FiveM kann in `dependencies` keine Versionen prüfen, deshalb stehen sie zusätzlich in fxmanifest.lua:
--   papa_requires 'papa_bridge@1.6.14'
-- (mehrere Zeilen erlaubt). Ist eine Abhängigkeit zu alt oder fehlt sie, steht ein Fehler in der Server-Konsole.

local function parseVersion(version)
    local parts = {}
    for number in tostring(version):gmatch("%d+") do
        parts[#parts + 1] = tonumber(number)
    end
    return parts
end

--- true, wenn version kleiner als minimum ist
local function isLowerVersion(version, minimum)
    local a, b = parseVersion(version), parseVersion(minimum)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            return x < y
        end
    end
    return false
end

CreateThread(function()
    local resource = GetCurrentResourceName()
    local count = GetNumResourceMetadata(resource, "papa_requires")
    for i = 0, count - 1 do
        local entry = GetResourceMetadata(resource, "papa_requires", i)
        local dependency, minimum = tostring(entry):match("^%s*([^@%s]+)%s*@%s*([%d%.]+)%s*$")
        if dependency then
            local state = GetResourceState(dependency)
            local current = GetResourceMetadata(dependency, "version", 0)
            if state == "missing" or state == "unknown" then
                print(("^1[%s] Missing dependency: %s (version %s or newer required)^0"):format(resource, dependency, minimum))
            elseif not current or isLowerVersion(current, minimum) then
                print(("^1[%s] %s is too old: installed %s, required %s or newer. Please update %s.^0")
                    :format(resource, dependency, tostring(current or "?"), minimum, dependency))
            end
        end
    end
end)
