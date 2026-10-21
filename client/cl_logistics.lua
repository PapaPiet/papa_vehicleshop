--- Logistik im Spiel: Abholung am Hafen / Flugplatz, Transportaufträge, Anlieferung und Inzahlungnahme
--- im Autohaus, Ausfahren aus dem Lager, Übergabe gekaufter Fahrzeuge, Fahrzeug direkt ausstellen.

VS = VS or {}

local U = VS.U

local job = nil -- running contract { id, deadlineAt, pointLabel }
local jobBlip = nil
local pendingTrade = nil -- { tradeId, vehicle }

local function epochMs()
    return GetCloudTimeAsInt() * 1000
end

local function clearJobBlip()
    if jobBlip then
        RemoveBlip(jobBlip)
        jobBlip = nil
    end
end

local function setRoute(coords, label)
    clearJobBlip()
    jobBlip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(jobBlip, 1)
    SetBlipColour(jobBlip, 3)
    SetBlipRoute(jobBlip, true)
    SetBlipRouteColour(jobBlip, 3)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(jobBlip)
end

local function shopDropoff(shopId)
    local shop = VS.shop(shopId)
    return shop and shop.points.dropoff, shop
end

--- Spawns a stock vehicle from server spawn info and reports the network id.
local function spawnStock(info, reportEvent)
    local veh, netId = U.spawnForPlayer(info.model, info.coords, info.props, info.condition, info.plate)
    TriggerServerEvent(reportEvent or "papa_vehicleshop:server:vehicleSpawned", info.stockId, netId)
    return veh
end

-- Delivery points ---------------------------------------------------------------------------

local function pickup(stockId, shopId)
    local info = U.call("pickup", stockId)
    if not info then
        return
    end
    local veh = spawnStock(info)
    if veh then
        local drop, shop = shopDropoff(shopId or info.shopId)
        if drop then
            setRoute(drop, T("blip_dropoff", shop.label))
        end
        U.notify(T("pickup_started", info.plate or ""), "success", 8000)
    end
end

local function acceptContract(contractId)
    local res = U.call("acceptContract", contractId)
    if not res then
        return
    end
    job = { id = res.contract.id, deadlineAt = res.contract.deadlineAt, pointLabel = res.point and res.point.label or "" }
    if res.point and res.point.interact then
        setRoute(res.point.interact, T("blip_pickup", res.point.label))
    end
    U.notify(T("contract_accepted", res.vehicle or "", res.point and res.point.label or ""), "success", 9000)
end

local function contractOptions(open)
    local options = {}
    for _, c in ipairs(open) do
        options[#options + 1] = {
            label = T("contract_row", c.label, U.money(c.reward)),
            description = T("contract_row_desc", c.shopLabel, c.pointLabel, c.deadlineMinutes),
            icon = "truck-fast",
            args = { contractId = c.id },
        }
    end
    return options
end

function VS.openBoard()
    local data = U.call("openContracts")
    if not data then
        return
    end
    local options = contractOptions(data.open or {})
    if data.running then
        table.insert(options, 1, { label = T("contract_running"), icon = "hourglass-half", disabled = true })
    end
    U.menu(T("contract_board"), options, function(args)
        if args.contractId then
            acceptContract(args.contractId)
        end
    end)
end

function VS.openDeliveryPointMenu(pointId)
    local data = U.call("pointMenu", pointId)
    if not data then
        return
    end
    local options = {}
    if data.job then
        local j = data.job
        options[#options + 1] = {
            label = T("pickup_contract", j.label, j.plate or ""),
            description = T("pickup_contract_desc", j.shopLabel, U.money(j.reward)),
            icon = "key",
            args = { action = "pickup", stockId = j.stockId },
        }
    end
    for _, v in ipairs(data.mine) do
        options[#options + 1] = {
            label = T("pickup_own", v.label, v.plate or ""),
            description = v.fee > 0 and T("pickup_own_fee", v.shopLabel, U.money(v.fee)) or v.shopLabel,
            icon = "warehouse",
            args = { action = "pickup", stockId = v.stockId },
        }
    end
    if data.running then
        options[#options + 1] = { label = T("contract_abandon"), description = T("contract_abandon_desc"), icon = "ban", args = { action = "abandon" } }
    else
        for _, o in ipairs(contractOptions(data.open or {})) do
            o.args.action = "accept"
            options[#options + 1] = o
        end
    end
    U.menu(data.point.label, options, function(args)
        if args.action == "pickup" then
            pickup(args.stockId)
        elseif args.action == "accept" then
            acceptContract(args.contractId)
        elseif args.action == "abandon" then
            if U.confirm(T("contract_abandon"), T("contract_abandon_desc")) and U.call("abandonContract") then
                job = nil
                clearJobBlip()
                U.notify(T("contract_abandoned"), "info")
            end
        end
    end)
end

RegisterNetEvent("papa_vehicleshop:client:contractsChanged", function()
    if job then
        -- Our contract may have expired or been recalled
        local data = lib.callback.await("papa_vehicleshop:openContracts", false)
        if type(data) == "table" and data.ok and data.data and not data.data.running then
            job = nil
            clearJobBlip()
        end
    end
end)

--- Remaining time of a running contract on screen.
CreateThread(function()
    while true do
        if job and job.deadlineAt and job.deadlineAt > 0 then
            local left = math.floor((job.deadlineAt - epochMs()) / 1000)
            if left < 0 then
                left = 0
            end
            U.drawText2D(T("contract_timer", math.floor(left / 60), left % 60), 0.5, 0.94, 0.42)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- Drop-off at the shop ----------------------------------------------------------------------

local function store(shopId, veh)
    local res = U.call("dropoff", shopId, U.vehicleData(veh))
    if not res then
        return
    end
    U.removeVehicle(veh)
    clearJobBlip()
    if res.payout then
        job = nil
        U.notify(T("contract_delivered", U.money(res.payout)), "success", 9000)
    else
        U.notify(res.registered and T("vehicle_registered") or T("vehicle_stored"), "success")
    end
end

local function tradeIn(shopId, veh)
    local shop = VS.shop(shopId)
    local asking = 0
    if shop and not shop.npcActive then
        local res = U.input(T("tradein_title"), {
            { type = "number", label = T("tradein_asking"), description = T("tradein_asking_desc"), min = 0, required = false },
        })
        if not res then
            return
        end
        asking = tonumber(res[1]) or 0
    end
    local data = U.vehicleData(veh)
    data.asking = asking
    local res = U.call("tradeInRequest", shopId, data)
    if not res then
        return
    end
    if res.mode == "npc" then
        local ok = U.confirm(T("tradein_title"), T("tradein_npc_offer", res.label, U.money(res.offer, res.currency), res.damage))
        local fresh = U.vehicleData(veh)
        local answer = U.call("tradeInAnswer", res.tradeId, { accept = ok, props = fresh.props, condition = fresh.condition })
        if ok and answer and answer.accepted then
            U.removeVehicle(veh)
            U.notify(T("tradein_sold", U.money(answer.offer, res.currency)), "success", 8000)
        end
        return
    end
    pendingTrade = { tradeId = res.tradeId, vehicle = veh }
    U.notify(T("tradein_waiting", res.minutes), "info", 9000)
end

RegisterNetEvent("papa_vehicleshop:client:tradeInOffer", function(o)
    local veh = pendingTrade and pendingTrade.tradeId == o.tradeId and pendingTrade.vehicle or GetVehiclePedIsIn(PlayerPedId(), false)
    local ok = U.confirm(T("tradein_title"), T("tradein_staff_offer", o.by, o.label, o.plate, U.money(o.offer, o.currency)))
    local data = { accept = ok }
    if ok then
        if not veh or veh == 0 or not DoesEntityExist(veh) or U.plate(veh) ~= o.plate then
            U.notify(T("tradein_vehicle_missing"), "error")
            data.accept = false
        else
            local fresh = U.vehicleData(veh)
            data.props, data.condition = fresh.props, fresh.condition
        end
    end
    local answer = U.call("tradeInAnswer", o.tradeId, data)
    pendingTrade = nil
    if data.accept and answer and answer.accepted then
        U.removeVehicle(veh)
        U.notify(T("tradein_sold", U.money(answer.offer, o.currency)), "success", 8000)
    end
end)

function VS.openDropoffMenu(shopId)
    local shop = VS.shop(shopId)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not shop or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        return
    end
    local options = {}
    if VS.isStaff(shopId) or job then
        options[#options + 1] = { label = T("dropoff_store"), description = T("dropoff_store_desc"), icon = "warehouse", args = { action = "store" } }
    end
    if shop.tradeIn then
        options[#options + 1] = { label = T("dropoff_tradein"), description = shop.npcActive and T("dropoff_tradein_npc") or T("dropoff_tradein_staff"), icon = "right-left", args = { action = "tradein" } }
    end
    U.menu(T("point_dropoff"), options, function(args)
        if args.action == "store" then
            store(shopId, veh)
        elseif args.action == "tradein" then
            tradeIn(shopId, veh)
        end
    end)
end

-- Staff: take a vehicle out of storage, put a driven vehicle on a display --------------------

function VS.takeOut(shopId, stockId)
    local info = U.call("takeOut", shopId, stockId)
    if info then
        spawnStock(info)
        U.notify(T("takeout_done", info.plate or ""), "success")
    end
end

function VS.displayVehicleHere(displayId, veh)
    local d = VS.world.displays[displayId]
    if not d then
        return
    end
    if not U.confirm(T("display_here_title"), T("display_here_text", U.modelLabel(GetEntityModel(veh)), d.label ~= "" and d.label or ("#" .. d.id))) then
        return
    end
    local data = U.vehicleData(veh)
    local res = U.call("displayFromWorld", displayId, data)
    if res then
        U.removeVehicle(veh)
        U.notify(T("display_here_done"), "success")
    end
end

-- Handover of a bought vehicle --------------------------------------------------------------

RegisterNetEvent("papa_vehicleshop:client:deliverVehicle", function(info)
    local veh = U.spawnVehicle(info.model, info.coords, info.props, nil, info.plate, true)
    if not veh then
        return
    end
    PAPA.Functions.giveVehicleKeys(veh)
    SetVehicleEngineOn(veh, false, true, false)
    SetNewWaypoint(info.coords.x + 0.0, info.coords.y + 0.0)
    U.notify(T("handover_ready", info.shopLabel), "success", 8000)
end)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() then
        clearJobBlip()
    end
end)
