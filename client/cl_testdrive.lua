--- Probefahrt: Fahrzeug am Übergabepunkt, Countdown, Rückgabe am Übergabepunkt.

VS = VS or {}

local U = VS.U

local drive = nil -- { vehicle, endsAt, returnTo, radius }

local function stop(returned)
    if not drive then
        return
    end
    local d = drive
    drive = nil
    local data = { returned = returned }
    if d.vehicle and DoesEntityExist(d.vehicle) then
        local fresh = U.vehicleData(d.vehicle)
        data.props, data.condition = fresh.props, fresh.condition
    end
    U.call("testDriveFinish", data)
    if d.vehicle and DoesEntityExist(d.vehicle) then
        U.removeVehicle(d.vehicle)
    end
end

function VS.startTestDrive(info)
    local veh, netId = U.spawnForPlayer(info.model, info.coords, info.props, info.condition, info.plate)
    TriggerServerEvent("papa_vehicleshop:server:testDriveSpawned", netId)
    if not veh then
        return
    end
    drive = {
        vehicle = veh,
        endsAt = GetGameTimer() + info.seconds * 1000,
        returnTo = vector3(info.returnTo.x, info.returnTo.y, info.returnTo.z),
        radius = info.radius or 12.0,
        startedAt = GetGameTimer(),
    }
    U.notify(T("testdrive_started", info.label, math.floor(info.seconds / 60)), "success", 8000)
    CreateThread(function()
        while drive do
            local ped = PlayerPedId()
            local left = math.max(0, math.floor((drive.endsAt - GetGameTimer()) / 1000))
            U.drawText2D(T("testdrive_timer", math.floor(left / 60), left % 60), 0.5, 0.94, 0.42)
            local pos = GetEntityCoords(ped)
            local near = #(pos - drive.returnTo) < drive.radius
            -- Only after the car has left the handover once (otherwise it would end right at the start)
            if near and GetGameTimer() - drive.startedAt > 15000 then
                DrawMarker(1, drive.returnTo.x, drive.returnTo.y, drive.returnTo.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, drive.radius * 2.0, drive.radius * 2.0, 0.5, 59, 130, 246, 60, false, false, 2, false, nil, nil, false)
                U.help(T("help_testdrive_return", Config.interactKey))
                if U.pressed() then
                    stop(true)
                    break
                end
            end
            if not DoesEntityExist(drive.vehicle) or IsEntityDead(ped) then
                stop(false)
                break
            end
            if left <= 0 and GetGameTimer() > drive.endsAt + 30000 then
                stop(false)
                break
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent("papa_vehicleshop:client:testDriveEnded", function()
    if drive then
        local d = drive
        drive = nil
        if d.vehicle and DoesEntityExist(d.vehicle) then
            U.removeVehicle(d.vehicle)
        end
    end
end)

AddEventHandler("papa:client:debugCloseUI", function()
    if drive then
        stop(false)
    end
end)
