--- Probefahrt: Kaution, Zeitlimit, Rückgabe am Übergabepunkt. Ausstellungsfahrzeuge werden wirklich gefahren
--- (Schäden bleiben), Katalogmodelle des NPC sind ein Vorführwagen.

VS = VS or {}
VS.TestDrive = VS.TestDrive or {}

local U = VS.U
local Td = VS.TestDrive
local St = VS.Stock

local running = {} -- src -> drive

local function deleteNet(netId)
    netId = tonumber(netId)
    if not netId then
        return
    end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
end

local function blocked(vtype)
    for _, t in ipairs(Config.testDrive.blockedTypes or {}) do
        if t == vtype then
            return true
        end
    end
    return false
end

function Td.isRunning(src)
    return running[src] ~= nil
end

function Td.start(actor, displayId, payWith)
    if running[actor.src] then
        return nil, "testdrive_running"
    end
    local d = VS.Displays.get(displayId)
    if not d then
        return nil, "not_found"
    end
    local shop = VS.Shops.get(d.shopId)
    if not shop or not shop.active or not shop.settings.testDrive.enabled then
        return nil, "testdrive_disabled"
    end
    local ped = GetPlayerPed(actor.src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(d.x, d.y, d.z)) > 15.0 then
        return nil, "too_far"
    end
    local spawnAt = shop.points.handover
    if not spawnAt then
        return nil, "no_handover_point"
    end
    local info
    local s = nil
    if d.kind == "stock" then
        s = d.stockId and St.get(d.stockId)
        if not s or s.status ~= "display" then
            return nil, "not_available"
        end
        if s.reservedFor and s.reservedFor ~= actor.id then
            return nil, "reserved"
        end
        if blocked(s.vtype) then
            return nil, "testdrive_type_blocked"
        end
        info = { model = s.model, plate = s.plate, props = s.props, condition = s.condition, vtype = s.vtype, label = s.label }
    else
        local entry = d.showcaseModel and VS.Catalog.get(d.showcaseModel)
        if not entry then
            return nil, "not_available"
        end
        if blocked(entry.vtype) then
            return nil, "testdrive_type_blocked"
        end
        local color = d.showcaseColor
        info = {
            model = entry.model, plate = ("TEST%04d"):format(math.random(0, 9999)), vtype = entry.vtype, label = entry.label,
            props = color and { color1 = color, color2 = color } or {},
        }
    end
    local deposit = shop.settings.testDrive.deposit or 0
    if deposit > 0 then
        local ok, err = VS.Account.playerPay(actor.src, payWith, deposit)
        if not ok then
            return nil, err
        end
    end
    if s then
        s.status = "testdrive"
        St.save(s)
        VS.Sync.display(d.id)
    end
    local seconds = shop.settings.testDrive.seconds or 180
    running[actor.src] = {
        shopId = shop.id, displayId = d.id, stockId = s and s.id or nil, deposit = deposit, payWith = payWith == "cash" and "cash" or "bank",
        endsAt = GetGameTimer() + seconds * 1000, netId = nil, identifier = actor.id, name = actor.name, label = info.label,
    }
    VS.audit(shop.id, actor, "testdrive.start", info.plate, { deposit = deposit })
    if s then
        VS.Notify.staff(shop, T("notify_testdrive_started", actor.name, info.label), "info")
    end
    info.coords = spawnAt
    info.seconds = seconds
    info.returnTo = spawnAt
    info.radius = Config.testDrive.returnRadius or 12.0
    info.deposit = deposit
    return info
end

function Td.spawned(src, netId)
    local r = running[src]
    if not r then
        return nil, "not_found"
    end
    if not netId then
        -- Spawning failed: give everything back
        Td.finish(src, { returned = true, failed = true })
        return true
    end
    r.netId = tonumber(netId)
    return true
end

--- Ends a test drive. data = { returned, props, condition, failed }
function Td.finish(src, data)
    local r = running[src]
    if not r then
        return nil, "not_found"
    end
    running[src] = nil
    data = type(data) == "table" and data or {}
    local shop = VS.Shops.get(r.shopId)
    local returned = data.returned == true
    if returned and shop and shop.points.handover and not data.failed then
        local ped = GetPlayerPed(src)
        local h = shop.points.handover
        if ped == 0 or #(GetEntityCoords(ped) - vector3(h.x, h.y, h.z)) > (Config.testDrive.returnRadius or 12.0) + 6.0 then
            returned = false
        end
    end
    if r.stockId then
        local s = St.get(r.stockId)
        if s and s.status == "testdrive" then
            if returned and data.props then
                St.capture(s, data.props, data.condition)
            end
            s.status = s.displayId and "display" or "storage"
            St.save(s)
            if s.displayId then
                VS.Sync.display(s.displayId)
            end
        end
    end
    deleteNet(r.netId)
    if r.deposit > 0 then
        if returned then
            VS.Account.playerReceive(src, r.payWith, r.deposit)
        elseif shop and shop.type ~= "npc" then
            VS.Account.add(shop, r.deposit, "deposit_kept", T("ledger_deposit_kept", r.name or "-", r.label or ""), nil, nil)
        end
    end
    if GetPlayerName(src) then
        VS.Notify.player(src, returned and T("testdrive_returned") or T("testdrive_deposit_kept"), returned and "success" or "error")
        TriggerClientEvent("papa_vehicleshop:client:testDriveEnded", src)
    end
    if shop then
        VS.audit(shop.id, { id = r.identifier, name = r.name }, "testdrive.end", r.label, { returned = returned })
        VS.Sync.changed(shop)
    end
    return { returned = returned }
end

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for src, r in pairs(running) do
            -- 30 seconds grace after the timer, then the vehicle is taken back
            if now > r.endsAt + 30000 then
                Td.finish(src, { returned = false })
            end
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    if running[src] then
        Td.finish(src, { returned = false })
    end
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then
        return
    end
    for _, r in pairs(running) do
        deleteNet(r.netId)
    end
end)
