--- Gemeinsame Hilfen für Client und Server.

VS = VS or {}

--- Alle Fahrzeugtypen in fester Reihenfolge.
VS.TYPE_ORDER = { "car", "offroad", "van", "truck", "motorcycle", "bicycle", "boat", "heli", "plane" }

function VS.isType(value)
    return type(value) == "string" and Config.vehicleTypes[value] ~= nil
end

function VS.typeFromClass(class)
    return Config.classToType[tonumber(class) or -1] or "car"
end

--- true, wenn der Typ in der Liste steht (leere Liste = alle).
function VS.typeAllowed(list, vehicleType)
    if type(list) ~= "table" or #list == 0 then
        return true
    end
    for _, t in ipairs(list) do
        if t == vehicleType then
            return true
        end
    end
    return false
end

--- Typen, die auf dem Wasser starten oder ein Rollfeld brauchen.
function VS.spawnArea(vehicleType)
    if vehicleType == "boat" then
        return "water"
    elseif vehicleType == "plane" or vehicleType == "heli" then
        return "air"
    end
    return "land"
end

function VS.round(n)
    return math.floor((tonumber(n) or 0) + 0.5)
end
