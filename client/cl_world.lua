--- Spielwelt: Blips, NPCs und Interaktionspunkte (Verwaltung, Verkäufer, Anlieferung, Häfen/Flugplätze, Auftragstafeln).
--- Mit Config.useTarget über papa_bridge Target, sonst Hinweistext und Taste. Anlieferung geht immer per Taste,
--- weil man dabei im Fahrzeug sitzt.

VS = VS or {}

local U = VS.U

local blips = {}
local peds = {} -- key -> entity
local zones = {} -- key -> zone id (target)
local points = {} -- key -> point definition

-- Blips -------------------------------------------------------------------------------------

local function clearBlips()
    for _, b in pairs(blips) do
        RemoveBlip(b)
    end
    blips = {}
end

local function addBlip(key, coords, sprite, color, scale, label)
    local b = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    SetBlipScale(b, scale + 0.0)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    blips[key] = b
end

local function rebuildBlips()
    clearBlips()
    for _, shop in pairs(VS.world.shops) do
        local anchor = shop.points.npc or shop.points.manage or shop.points.dropoff
        if shop.active and anchor and shop.blip and shop.blip.enabled then
            addBlip("shop" .. shop.id, anchor, shop.blip.sprite, shop.blip.color, shop.blip.scale, shop.label)
        end
    end
    for _, p in ipairs(VS.world.points) do
        if p.enabled and p.interact and p.blip and p.blip.enabled ~= false then
            addBlip("point" .. p.id, p.interact, p.blip.sprite or 410, p.blip.color or 3, p.blip.scale or 0.75, p.label)
        end
    end
end

-- Interaction points ------------------------------------------------------------------------

local function removeZone(key)
    if zones[key] then
        PAPA.Target.removeZone(zones[key])
        zones[key] = nil
    end
end

local function removePed(key)
    local ped = peds[key]
    if ped and DoesEntityExist(ped) then
        if Config.useTarget then
            PAPA.Target.deleteLocalEntity(ped)
        end
        DeleteEntity(ped)
    end
    peds[key] = nil
end

local function targetOptions(key, def)
    return {
        {
            name = "papa_vs_" .. key,
            label = def.label(),
            icon = def.icon or "fas fa-car",
            distance = def.radius or 2.0,
            canInteract = function()
                return def.canUse == nil or def.canUse()
            end,
            onSelect = function()
                def.onUse()
            end,
        },
    }
end

--- Defines or replaces an interaction point.
--- def = { coords (vector4/table), radius, label = fn, canUse = fn, onUse = fn, ped = model|nil, inVehicle = bool, icon }
function VS.setPoint(key, def)
    VS.removePoint(key)
    def.coords = vector4(def.coords.x + 0.0, def.coords.y + 0.0, def.coords.z + 0.0, (def.coords.w or 0.0) + 0.0)
    points[key] = def
    if Config.useTarget and not def.inVehicle and not def.ped then
        zones[key] = PAPA.Target.addSphereZone("papa_vs_" .. key, def.coords.xyz, def.radius or 1.2, targetOptions(key, def), def.radius or 2.0)
    end
end

function VS.removePoint(key)
    removeZone(key)
    removePed(key)
    points[key] = nil
end

local function spawnPed(key, def)
    local hash = U.loadModel(def.ped)
    if not hash then
        return
    end
    local c = def.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z, c.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
    peds[key] = ped
    if Config.useTarget then
        PAPA.Target.addLocalEntity(ped, targetOptions(key, def), def.radius or 2.5)
    end
end

--- Rebuilds all points from the world state.
local function rebuildPoints()
    for key in pairs(points) do
        VS.removePoint(key)
    end
    for _, shop in pairs(VS.world.shops) do
        if shop.active then
            local id = shop.id
            if shop.points.manage and shop.type ~= "npc" then
                VS.setPoint("manage" .. id, {
                    coords = shop.points.manage,
                    radius = 1.5,
                    icon = "fas fa-laptop",
                    label = function()
                        return T("point_manage")
                    end,
                    canUse = function()
                        return VS.isStaff(id)
                    end,
                    onUse = function()
                        VS.openStaffMenu(id)
                    end,
                })
            end
            if shop.points.npc then
                local npcModel = shop.npcActive and shop.npcModel or nil
                VS.setPoint("npc" .. id, {
                    coords = shop.points.npc,
                    radius = 2.0,
                    ped = npcModel,
                    icon = "fas fa-user-tie",
                    label = function()
                        local s = VS.shop(id)
                        return s and s.npcActive and T("point_npc") or T("point_reception")
                    end,
                    onUse = function()
                        VS.openCustomerMenu(id)
                    end,
                })
            end
            if shop.points.dropoff then
                VS.setPoint("dropoff" .. id, {
                    coords = shop.points.dropoff,
                    radius = shop.dropoffRadius or 7.0,
                    inVehicle = true,
                    marker = true,
                    label = function()
                        return T("point_dropoff")
                    end,
                    onUse = function()
                        VS.openDropoffMenu(id)
                    end,
                })
            end
        end
    end
    for _, p in ipairs(VS.world.points) do
        if p.enabled and p.interact then
            local pid = p.id
            VS.setPoint("delivery" .. pid, {
                coords = p.interact,
                radius = 2.0,
                ped = p.npc,
                icon = "fas fa-warehouse",
                label = function()
                    return T("point_delivery")
                end,
                onUse = function()
                    VS.openDeliveryPointMenu(pid)
                end,
            })
        end
    end
    for i, b in ipairs(VS.world.boards or {}) do
        VS.setPoint("board" .. i, {
            coords = b,
            radius = 1.5,
            icon = "fas fa-clipboard-list",
            label = function()
                return T("point_board")
            end,
            onUse = function()
                VS.openBoard()
            end,
        })
    end
end

local rebuildQueued = false

local function queueRebuild()
    if rebuildQueued then
        return
    end
    rebuildQueued = true
    SetTimeout(250, function()
        rebuildQueued = false
        rebuildBlips()
        rebuildPoints()
    end)
end

AddEventHandler("papa_vehicleshop:client:worldChanged", function(kind)
    if kind == "all" or kind == "shop" or kind == "points" then
        queueRebuild()
    end
end)

--- papa_bridge restarted: target options are gone, build them again.
AddEventHandler("onClientResourceStart", function(name)
    if name == "papa_bridge" then
        queueRebuild()
    end
end)

-- Proximity loop: peds, help texts, markers --------------------------------------------------

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local nearest, nearestDist = nil, 999.0
        for key, def in pairs(points) do
            local dist = #(pos - def.coords.xyz)
            if def.ped then
                if dist < Config.renderDistance and not peds[key] then
                    spawnPed(key, def)
                elseif dist > Config.renderDistance + 10.0 and peds[key] then
                    removePed(key)
                end
            end
            local usable = (def.inVehicle and inVehicle) or (not def.inVehicle and not inVehicle and not Config.useTarget)
            if usable and dist < (def.radius or 2.0) + 15.0 and dist < nearestDist then
                nearest, nearestDist = def, dist
            end
        end
        if nearest then
            local untilTime = GetGameTimer() + 400
            while GetGameTimer() < untilTime do
                local c = nearest.coords
                if nearest.marker then
                    DrawMarker(1, c.x, c.y, c.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (nearest.radius or 7.0) * 2.0, (nearest.radius or 7.0) * 2.0, 0.6, 59, 130, 246, 70, false, false, 2, false, nil, nil, false)
                end
                local dist = #(GetEntityCoords(PlayerPedId()) - c.xyz)
                if dist <= (nearest.radius or 2.0) and (nearest.canUse == nil or nearest.canUse()) then
                    U.help(T("help_press", Config.interactKey, nearest.label()))
                    if U.pressed() then
                        nearest.onUse()
                        Wait(500)
                    end
                end
                Wait(0)
            end
        else
            Wait(600)
        end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then
        return
    end
    for key in pairs(points) do
        VS.removePoint(key)
    end
    clearBlips()
end)
