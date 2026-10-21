--- NUI-Brücke für das Dashboard und den Admin-Bereich (beide laufen als iframe dieser Ressource in Papa OS).

local pending = {}
local nextId = 0

RegisterNUICallback("vehicleshopRpc", function(data, cb)
    nextId = nextId + 1
    local id = nextId
    pending[id] = cb
    TriggerServerEvent("papa_vehicleshop:server:rpc", id, data)
    SetTimeout(30000, function()
        local waiting = pending[id]
        if waiting then
            pending[id] = nil
            waiting({ ok = false, error = "timeout", message = T("err_timeout") })
        end
    end)
end)

RegisterNetEvent("papa_vehicleshop:client:rpcResult", function(id, result)
    local cb = pending[id]
    if cb then
        pending[id] = nil
        cb(result)
    end
end)

--- Own position (vehicle position when sitting in one), for "set at my position" in the admin area.
RegisterNUICallback("vehicleshopMyPosition", function(_, cb)
    local pos, veh = VS.U.myPosition()
    local streetHash = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    cb({
        ok = true,
        data = {
            x = pos.x, y = pos.y, z = pos.z, w = pos.w,
            inVehicle = veh ~= nil,
            street = GetStreetNameFromHashKey(streetHash),
        },
    })
end)

RegisterNUICallback("vehicleshopWaypoint", function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
    end
    cb({ ok = true })
end)

--- Dashboard: the shop changed (sale, delivery ...). The iframe listens for this message and reloads.
RegisterNetEvent("papa_vehicleshop:client:shopChanged", function(shopId)
    SendNUIMessage({ type = "papa_vehicleshop:shopChanged", shopId = shopId })
end)
