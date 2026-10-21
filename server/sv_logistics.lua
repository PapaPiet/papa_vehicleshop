--- Logistik: Abholung am Hafen / Flugplatz, Anlieferung im Autohaus, Ausfahren aus dem Lager und Transportaufträge.

VS = VS or {}
VS.Logistics = VS.Logistics or {}

local U = VS.U
local L = VS.Logistics
local St = VS.Stock

local active = {} -- stockId -> { src, netId, contractId, kind }

-- Helpers -----------------------------------------------------------------------------------

local function deleteNet(netId)
    netId = tonumber(netId)
    if not netId or netId == 0 then
        return
    end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
end

function L.activeOf(stockId)
    return active[stockId]
end

function L.clearActive(stockId, deleteVehicle)
    local a = active[stockId]
    if a and deleteVehicle then
        deleteNet(a.netId)
    end
    active[stockId] = nil
end

--- Free spawn slot for a vehicle type at a delivery point.
local function freeSlot(point, vehicleType)
    local area = VS.spawnArea(vehicleType)
    local slots = area == "water" and point.waterSpawns or area == "air" and point.airSpawns or point.spawns
    local vehicles = GetAllVehicles()
    for _, slot in ipairs(slots) do
        local pos = vector3(slot.x, slot.y, slot.z)
        local blocked = false
        for _, veh in ipairs(vehicles) do
            if #(GetEntityCoords(veh) - pos) < (area == "land" and 3.0 or 8.0) then
                blocked = true
                break
            end
        end
        if not blocked then
            return slot
        end
    end
    return nil
end

local function spawnInfo(s, coords)
    return {
        stockId = s.id,
        shopId = s.shopId,
        model = s.model,
        plate = s.plate,
        props = s.props,
        condition = s.condition,
        vtype = s.vtype,
        coords = coords,
    }
end

-- Contracts ---------------------------------------------------------------------------------

local function contractFromRow(r)
    return {
        id = tonumber(r.id), shopId = tonumber(r.shop_id), stockId = tonumber(r.stock_id), reward = tonumber(r.reward) or 0,
        payout = tonumber(r.payout) or 0, status = r.status, note = r.note, takerId = r.taker_id, takerName = r.taker_name,
        takenAt = tonumber(r.taken_at) or 0, deadlineAt = tonumber(r.deadline_at) or 0, createdBy = r.created_by,
        createdAt = tonumber(r.created_at) or 0, doneAt = tonumber(r.done_at) or 0,
    }
end

local contracts = {} -- open/taken contracts by id

local function saveContract(c)
    MySQL.update.await(
        ([[UPDATE %s SET `reward`=?,`payout`=?,`status`=?,`note`=?,`taker_id`=?,`taker_name`=?,`taken_at`=?,`deadline_at`=?,`done_at`=? WHERE `id`=?]])
            :format(VS.Db.t("contracts")),
        { c.reward, c.payout, c.status, c.note, c.takerId, c.takerName, c.takenAt, c.deadlineAt, c.doneAt, c.id }
    )
    if c.status == "open" or c.status == "taken" then
        contracts[c.id] = c
    else
        contracts[c.id] = nil
    end
end

function L.loadContracts()
    contracts = {}
    for _, r in ipairs(MySQL.query.await(("SELECT * FROM %s WHERE `status` IN ('open','taken')"):format(VS.Db.t("contracts"))) or {}) do
        local c = contractFromRow(r)
        contracts[c.id] = c
    end
end

function L.contractForStock(stockId)
    for _, c in pairs(contracts) do
        if c.stockId == stockId then
            return { id = c.id, status = c.status, reward = c.reward, takerName = c.takerName, deadlineAt = c.deadlineAt }
        end
    end
    return nil
end

function L.contractsOfShop(shopId, includeDone)
    local out = {}
    if includeDone then
        local rows = MySQL.query.await(
            ("SELECT * FROM %s WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT 100"):format(VS.Db.t("contracts")), { shopId }
        ) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = contractFromRow(r)
        end
    else
        for _, c in pairs(contracts) do
            if c.shopId == shopId then
                out[#out + 1] = c
            end
        end
        table.sort(out, function(a, b)
            return a.id > b.id
        end)
    end
    for _, c in ipairs(out) do
        local s = St.get(c.stockId)
        c.vehicle = s and { label = s.label, plate = s.plate, model = s.model, vtype = s.vtype, deliveryPoint = s.deliveryPoint } or nil
    end
    return out
end

--- Suggested reward for a stock vehicle.
function L.suggestReward(s)
    return VS.round((Config.contracts.suggestBase or 0) + (s.cost or 0) * (Config.contracts.suggestPercent or 0) / 100)
end

function L.createContract(actor, shop, stockId, reward, note)
    if not Config.contracts.enabled then
        return nil, "contracts_disabled"
    end
    local s = St.get(stockId)
    if not s or s.shopId ~= shop.id then
        return nil, "not_found"
    end
    if s.status ~= "waiting" then
        return nil, "invalid_status"
    end
    if L.contractForStock(s.id) then
        return nil, "contract_exists"
    end
    reward = U.int(reward, 1, 10000000, L.suggestReward(s))
    local ok, err = VS.Account.remove(shop, reward, "contract", T("ledger_contract_escrow", s.label, s.plate or ""), s.plate, actor.name)
    if not ok then
        return nil, err
    end
    local id = MySQL.insert.await(
        ("INSERT INTO %s (`shop_id`,`stock_id`,`reward`,`status`,`note`,`created_by`,`created_at`) VALUES (?,?,?,?,?,?,?)")
            :format(VS.Db.t("contracts")),
        { shop.id, s.id, reward, "open", U.optStr(note, 255), actor.name, U.now() }
    )
    local c = contractFromRow(MySQL.single.await(("SELECT * FROM %s WHERE `id` = ?"):format(VS.Db.t("contracts")), { id }))
    contracts[c.id] = c
    VS.audit(shop.id, actor, "contract.create", c.id, { reward = reward, stock = s.id })
    TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
    VS.Sync.changed(shop)
    return c
end

local function refundContract(c, shop, reason)
    local refund = c.reward - (c.payout or 0)
    if refund > 0 and shop then
        VS.Account.add(shop, refund, "refund", T("ledger_contract_refund", c.id, reason or ""), tostring(c.id), nil)
    end
end

function L.cancelContract(actor, shop, contractId)
    local c = contracts[tonumber(contractId) or -1]
    if not c or c.shopId ~= shop.id then
        return nil, "not_found"
    end
    if c.status ~= "open" then
        return nil, "contract_taken"
    end
    c.status = "cancelled"
    c.doneAt = U.now()
    saveContract(c)
    refundContract(c, shop, T("contract_cancelled"))
    VS.audit(shop.id, actor, "contract.cancel", c.id)
    TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
    VS.Sync.changed(shop)
    return true
end

--- Open contracts for the public board (optionally only for vehicles at one delivery point).
function L.openContracts(pointId)
    local out = {}
    for _, c in pairs(contracts) do
        if c.status == "open" then
            local s = St.get(c.stockId)
            local shop = VS.Shops.get(c.shopId)
            if s and shop and s.status == "waiting" and (not pointId or s.deliveryPoint == pointId) then
                local point = VS.Points.get(s.deliveryPoint)
                out[#out + 1] = {
                    id = c.id, reward = c.reward, shopLabel = shop.label, label = s.label, vtype = s.vtype, plate = s.plate,
                    pointId = s.deliveryPoint, pointLabel = point and point.label or "-", note = c.note,
                    deadlineMinutes = Config.contracts.deadlineMinutes,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        return a.reward > b.reward
    end)
    return out
end

function L.takenBy(identifier)
    for _, c in pairs(contracts) do
        if c.status == "taken" and c.takerId == identifier then
            return c
        end
    end
    return nil
end

function L.acceptContract(actor, contractId)
    local c = contracts[tonumber(contractId) or -1]
    if not c or c.status ~= "open" then
        return nil, "contract_unavailable"
    end
    if L.takenBy(actor.id) then
        return nil, "contract_already_running"
    end
    local shop = VS.Shops.get(c.shopId)
    if Config.contracts.onlyExternal and shop and VS.Access.isStaff(actor, shop) then
        return nil, "contract_only_external"
    end
    c.status = "taken"
    c.takerId = actor.id
    c.takerName = actor.name
    c.takenAt = U.now()
    c.deadlineAt = c.takenAt + (tonumber(Config.contracts.deadlineMinutes) or 30) * 60000
    saveContract(c)
    if shop then
        VS.Notify.staff(shop, T("notify_contract_taken", actor.name, c.id), "info")
        VS.Sync.changed(shop)
    end
    VS.audit(c.shopId, actor, "contract.accept", c.id)
    TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
    local s = St.get(c.stockId)
    local point = s and VS.Points.get(s.deliveryPoint)
    return { contract = c, point = point and { id = point.id, label = point.label, interact = point.interact } or nil, vehicle = s and s.label }
end

local function failContract(c, reason)
    local shop = VS.Shops.get(c.shopId)
    local s = St.get(c.stockId)
    if s and (s.status == "pickup") then
        L.clearActive(s.id, true)
        s.status = "waiting"
        St.save(s)
    end
    c.status = "failed"
    c.note = reason
    c.doneAt = U.now()
    saveContract(c)
    refundContract(c, shop, reason)
    if shop then
        VS.Notify.staff(shop, T("notify_contract_failed", c.id, c.takerName or "-"), "error")
        VS.Sync.changed(shop)
    end
    VS.Notify.identifier(c.takerId, T("contract_title"), T("notify_contract_expired"), "error")
    TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
end

--- The taker gives the contract back (vehicle not picked up yet or returned to the delivery point).
function L.abandonContract(actor)
    local c = L.takenBy(actor.id)
    if not c then
        return nil, "not_found"
    end
    local s = St.get(c.stockId)
    if s and s.status == "pickup" then
        L.clearActive(s.id, true)
        s.status = "waiting"
        St.save(s)
    end
    c.status = "open"
    c.takerId, c.takerName, c.takenAt, c.deadlineAt = nil, nil, 0, 0
    saveContract(c)
    TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
    local shop = VS.Shops.get(c.shopId)
    if shop then
        VS.Sync.changed(shop)
    end
    return true
end

CreateThread(function()
    while true do
        Wait(15000)
        if VS.Db.ready then
            local now = U.now()
            for _, c in pairs(contracts) do
                if c.status == "taken" and c.deadlineAt > 0 and c.deadlineAt < now then
                    failContract(c, T("contract_deadline"))
                end
            end
        end
    end
end)

-- Pickup at a delivery point ----------------------------------------------------------------

--- What the player can do at a delivery point.
function L.pointMenu(actor, pointId)
    local point = VS.Points.get(pointId)
    if not point then
        return nil, "not_found"
    end
    local mine = {}
    for _, shop in ipairs(VS.Access.shopsOf(actor)) do
        if VS.Access.can(actor, shop, "stockManage") then
            for _, s in ipairs(St.forShop(shop.id, { "waiting" })) do
                if s.deliveryPoint == point.id then
                    local c = L.contractForStock(s.id)
                    if not c or c.status == "open" then
                        mine[#mine + 1] = {
                            stockId = s.id, label = s.label, plate = s.plate, vtype = s.vtype, shopLabel = shop.label,
                            fee = St.storageFee(s), contract = c ~= nil,
                        }
                    end
                end
            end
        end
    end
    local running = L.takenBy(actor.id)
    local job = nil
    if running then
        local s = St.get(running.stockId)
        if s and s.deliveryPoint == point.id and s.status == "waiting" then
            local shop = VS.Shops.get(running.shopId)
            job = { contractId = running.id, stockId = s.id, label = s.label, plate = s.plate, shopLabel = shop and shop.label or "-", reward = running.reward, deadlineAt = running.deadlineAt }
        end
    end
    return {
        point = { id = point.id, label = point.label },
        mine = mine,
        job = job,
        running = running and { id = running.id, deadlineAt = running.deadlineAt } or nil,
        open = Config.contracts.enabled and L.openContracts(nil) or {},
    }
end

--- Prepares a pickup. Returns spawn info for the client; the client reports the network id afterwards.
function L.pickup(actor, stockId)
    local s = St.get(stockId)
    if not s or s.status ~= "waiting" then
        return nil, "not_available"
    end
    local shop = VS.Shops.get(s.shopId)
    if not shop then
        return nil, "not_found"
    end
    local c = nil
    for _, contract in pairs(contracts) do
        if contract.stockId == s.id then
            c = contract
        end
    end
    local asTaker = c and c.status == "taken" and c.takerId == actor.id
    if not asTaker then
        if not VS.Access.can(actor, shop, "stockManage") then
            return nil, "no_permission"
        end
        if c and c.status == "taken" then
            return nil, "contract_taken"
        end
    end
    local point = VS.Points.get(s.deliveryPoint)
    if not point then
        return nil, "no_delivery_point"
    end
    local ped = GetPlayerPed(actor.src)
    if ped == 0 or not point.interact or #(GetEntityCoords(ped) - vector3(point.interact.x, point.interact.y, point.interact.z)) > 60.0 then
        return nil, "too_far"
    end
    local slot = freeSlot(point, s.vtype)
    if not slot then
        return nil, "no_free_slot"
    end
    -- Storage fee at the port is paid by the shop (not by a contract taker)
    local fee = St.storageFee(s)
    if fee > 0 then
        local ok = VS.Account.remove(shop, fee, "storage_fee", T("ledger_storage_fee", s.label, s.plate or ""), s.plate, actor.name)
        if not ok then
            return nil, "insufficient_funds"
        end
    end
    s.status = "pickup"
    St.save(s)
    active[s.id] = { src = actor.src, netId = nil, contractId = asTaker and c.id or nil, kind = "pickup", identifier = actor.id }
    PAPA.Functions.setOwnedVehicleGarage(s.plate, nil, false)
    VS.audit(shop.id, actor, "stock.pickup", s.id, { contract = asTaker and c.id or nil })
    VS.Sync.changed(shop)
    return spawnInfo(s, slot)
end

--- Client reports the spawned vehicle (or a failure).
function L.spawned(actor, stockId, netId)
    local a = active[tonumber(stockId) or -1]
    if not a or a.src ~= actor.src then
        return nil, "not_found"
    end
    if not netId then
        local s = St.get(stockId)
        if s and s.status == "pickup" then
            s.status = "waiting"
            St.save(s)
        elseif s and s.status == "out" then
            s.status = "storage"
            St.save(s)
            PAPA.Functions.setOwnedVehicleGarage(s.plate, VS.Shops.garage(VS.Shops.get(s.shopId)), true)
        end
        active[stockId] = nil
        return true
    end
    a.netId = tonumber(netId)
    return true
end

-- Take out of storage (staff drives a stock vehicle away, e.g. to a garage) ------------------

function L.takeOut(actor, shop, stockId)
    local s = St.get(stockId)
    if not s or s.shopId ~= shop.id then
        return nil, "not_found"
    end
    if s.status ~= "storage" then
        return nil, "invalid_status"
    end
    local h = shop.points.handover
    if not h then
        return nil, "no_handover_point"
    end
    s.status = "out"
    St.save(s)
    active[s.id] = { src = actor.src, netId = nil, kind = "out", identifier = actor.id }
    PAPA.Functions.setOwnedVehicleGarage(s.plate, nil, false)
    VS.audit(shop.id, actor, "stock.takeout", s.id)
    VS.Sync.changed(shop)
    return spawnInfo(s, h)
end

--- Staff: vehicle that is out / being picked up is put back (deletes the world vehicle if it still exists).
function L.recall(actor, shop, stockId)
    local s = St.get(stockId)
    if not s or s.shopId ~= shop.id then
        return nil, "not_found"
    end
    if s.status == "pickup" then
        local c = nil
        for _, contract in pairs(contracts) do
            if contract.stockId == s.id and contract.status == "taken" then
                c = contract
            end
        end
        if c then
            failContract(c, T("contract_recalled"))
        else
            L.clearActive(s.id, true)
            s.status = "waiting"
            St.save(s)
        end
    elseif s.status == "out" then
        L.clearActive(s.id, true)
        St.toStorage(s)
    else
        return nil, "invalid_status"
    end
    VS.audit(shop.id, actor, "stock.recall", s.id)
    VS.Sync.changed(shop)
    return true
end

-- Drop-off at the shop ----------------------------------------------------------------------

--- A vehicle is brought to the drop-off point of a shop. data = { plate, model, label, vtype, props, condition, netId }
function L.dropoff(actor, shopId, data)
    local shop = VS.Shops.get(shopId)
    if not shop or not shop.active or shop.type == "npc" then
        return nil, "not_found"
    end
    local drop = shop.points.dropoff
    local ped = GetPlayerPed(actor.src)
    if not drop or ped == 0 or #(GetEntityCoords(ped) - vector3(drop.x, drop.y, drop.z)) > (shop.settings.dropoffRadius or 7.0) + 4.0 then
        return nil, "too_far"
    end
    if type(data) ~= "table" then
        return nil, "invalid"
    end
    local s = St.byPlate(data.plate)
    if s and s.shopId ~= shop.id then
        return nil, "wrong_shop"
    end
    local payout = nil
    if s then
        local a = active[s.id]
        local contract = a and a.contractId and contracts[a.contractId] or nil
        if s.status == "pickup" or s.status == "out" then
            if not contract and not VS.Access.isStaff(actor, shop) then
                return nil, "no_permission"
            end
            if contract and contract.takerId ~= actor.id and not VS.Access.isStaff(actor, shop) then
                return nil, "no_permission"
            end
        else
            return nil, "invalid_status"
        end
        St.toStorage(s, data.props, data.condition)
        active[s.id] = nil
        if contract and contract.status == "taken" then
            local damage = St.damagePercent(s)
            local penalty = math.floor(damage / 10) * (tonumber(Config.contracts.damagePenaltyPer10) or 0)
            payout = VS.round(contract.reward * math.max(0, 100 - penalty) / 100)
            contract.payout = payout
            contract.status = "done"
            contract.doneAt = U.now()
            saveContract(contract)
            local takerSrc = PAPA.Functions.getPlayerSourceByCitizenId(contract.takerId)
            if takerSrc then
                VS.Account.playerReceive(takerSrc, "bank", payout)
                VS.Notify.player(takerSrc, T("notify_contract_paid", U.formatMoney(payout, shop.settings.currency), damage), "success")
            else
                PAPA.Functions.changeOfflinePlayerMoney(contract.takerId, "bank", payout)
            end
            refundContract(contract, shop, T("contract_damage_refund"))
            VS.Notify.staff(shop, T("notify_contract_done", contract.takerName or "-", s.label, damage), "success")
            TriggerClientEvent("papa_vehicleshop:client:contractsChanged", -1)
        else
            VS.Notify.staff(shop, T("notify_vehicle_stored", s.label, s.plate or ""), "info")
        end
        VS.audit(shop.id, actor, "stock.dropoff", s.id, { payout = payout })
        return { stored = true, stockId = s.id, payout = payout }
    end
    -- Not in stock: a vehicle of the owner from a garage becomes stock
    if not VS.Access.can(actor, shop, "stockManage") then
        return nil, "no_permission"
    end
    local created, err = St.registerOwned(actor, shop, data)
    if not created then
        return nil, err
    end
    St.toStorage(created, data.props, data.condition)
    return { stored = true, stockId = created.id, registered = true }
end

--- Puts a vehicle of the owner directly on a display spot (driven onto the spot).
function L.displayFromWorld(actor, displayId, data)
    local d = VS.Displays.get(displayId)
    if not d then
        return nil, "not_found"
    end
    local shop = VS.Shops.get(d.shopId)
    if not shop or not VS.Access.can(actor, shop, "displayManage") then
        return nil, "no_permission"
    end
    local ped = GetPlayerPed(actor.src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > 12.0 then
        return nil, "too_far"
    end
    if type(data) ~= "table" then
        return nil, "invalid"
    end
    local s = St.byPlate(data.plate)
    if s and s.shopId ~= shop.id then
        return nil, "wrong_shop"
    end
    if s then
        if s.status ~= "pickup" and s.status ~= "out" and s.status ~= "storage" then
            return nil, "invalid_status"
        end
        local a = active[s.id]
        if a and a.contractId then
            return nil, "contract_running"
        end
        active[s.id] = nil
        St.toStorage(s, data.props, data.condition)
    else
        local err
        s, err = St.registerOwned(actor, shop, data)
        if not s then
            return nil, err
        end
        St.toStorage(s, data.props, data.condition)
    end
    local ok, err = St.toDisplay(actor, shop, s, d.id)
    if not ok then
        return nil, err
    end
    return { displayed = true, stockId = s.id }
end

AddEventHandler("playerDropped", function()
    local src = source
    for stockId, a in pairs(active) do
        if a.src == src and a.kind == "out" then
            -- Staff left with a vehicle: keep it out, but forget the driver
            a.src = -1
        end
    end
end)

AddEventHandler("papa_vehicleshop:server:dbReady", function()
    L.loadContracts()
    -- Contracts that were running when the server stopped: the vehicle is back at the port
    for _, c in pairs(contracts) do
        if c.status == "taken" then
            c.status = "open"
            c.takerId, c.takerName, c.takenAt, c.deadlineAt = nil, nil, 0, 0
            saveContract(c)
        end
    end
end)
