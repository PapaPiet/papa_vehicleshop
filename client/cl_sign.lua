--- Preisschilder: Prop (oder freier Bildschirm) neben dem Ausstellungsfahrzeug mit einem DUI-Bildschirm
--- (html/sign.html). Jeder aktive Bildschirm ist ein eigener Browser, deshalb gibt es höchstens
--- Config.maxActiveSigns gleichzeitig (die nächsten zum Spieler).

VS = VS or {}
VS.Sign = VS.Sign or {}

local U = VS.U
local Sg = VS.Sign
local RES = GetCurrentResourceName()
local TXD = "papa_vs_signs"

local txd = nil
local duis = {} -- displayId -> { obj, texture, ready, payload }
local textureCounter = 0
local propModelOk = nil

local function propAvailable()
    if propModelOk == nil then
        propModelOk = Config.sign.model ~= nil and U.modelExists(Config.sign.model)
    end
    return propModelOk
end

-- Geometry ----------------------------------------------------------------------------------

--- World position and heading of a sign (absolute position or offset from the display spot).
function Sg.placement(d)
    local sign = d.sign or {}
    if sign.world then
        return vector3(sign.world.x, sign.world.y, sign.world.z), sign.world.w or 0.0
    end
    local o = sign.offset or Config.sign.offset
    local rad = math.rad(d.h)
    local cos, sin = math.cos(rad), math.sin(rad)
    local x = d.x + o.x * cos - o.y * sin
    local y = d.y + o.x * sin + o.y * cos
    return vector3(x, y, d.z + (o.z or 0.0)), (d.h + (o.h or 0.0)) % 360.0
end

local function rotate(v, heading)
    local rad = math.rad(heading)
    local cos, sin = math.cos(rad), math.sin(rad)
    return vector3(v.x * cos - v.y * sin, v.x * sin + v.y * cos, v.z)
end

--- Four world corners of the screen (top-left, top-right, bottom-right, bottom-left).
function Sg.corners(entry)
    if entry.corners then
        return entry.corners
    end
    local list
    if entry.prop and DoesEntityExist(entry.prop) then
        local s = Config.sign.screen
        list = {}
        for i, v in ipairs({ s.topLeft, s.topRight, s.bottomRight, s.bottomLeft }) do
            list[i] = GetOffsetFromEntityInWorldCoords(entry.prop, v.x, v.y, v.z)
        end
    else
        local f = Config.sign.fallbackScreen
        local hw = f.width / 2
        local top, bottom = f.lift + f.height, f.lift
        local base, heading = entry.pos, entry.heading
        list = {
            base + rotate(vector3(-hw, 0.0, top), heading),
            base + rotate(vector3(hw, 0.0, top), heading),
            base + rotate(vector3(hw, 0.0, bottom), heading),
            base + rotate(vector3(-hw, 0.0, bottom), heading),
        }
    end
    entry.corners = list
    return list
end

-- Props -------------------------------------------------------------------------------------

--- Spawns the sign prop (or the fallback post). Returns { prop, post, pos, heading }.
function Sg.spawn(d)
    local pos, heading = Sg.placement(d)
    local entry = { pos = pos, heading = heading }
    if propAvailable() then
        local hash = U.loadModel(Config.sign.model)
        if hash then
            local prop = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(prop, heading)
            FreezeEntityPosition(prop, true)
            SetEntityInvincible(prop, true)
            SetModelAsNoLongerNeeded(hash)
            entry.prop = prop
        end
    elseif Config.sign.fallbackPost then
        local hash = U.loadModel(Config.sign.fallbackPost)
        if hash then
            local post = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(post, heading)
            FreezeEntityPosition(post, true)
            SetEntityInvincible(post, true)
            SetEntityCollision(post, false, false)
            SetModelAsNoLongerNeeded(hash)
            entry.post = post
        end
    end
    return entry
end

function Sg.despawn(entry)
    if not entry then
        return
    end
    if entry.prop and DoesEntityExist(entry.prop) then
        DeleteEntity(entry.prop)
    end
    if entry.post and DoesEntityExist(entry.post) then
        DeleteEntity(entry.post)
    end
end

-- DUI ---------------------------------------------------------------------------------------

local function send(dui, payload)
    if dui.ready then
        SendDuiMessage(dui.obj, json.encode({ type = "show", data = payload }))
    end
end

--- Texts the sign page needs (from the language files).
local function signTexts()
    local keys = {
        "sign_price", "sign_delivery", "sign_immediate", "sign_condition", "sign_reserved", "sign_testdrive",
        "sign_plate", "sign_finance_from", "sign_new", "sign_used", "sign_unavailable", "sign_ask_staff",
        "sign_fuel", "sign_damage",
    }
    local out = {}
    for _, k in ipairs(keys) do
        out[k] = T(k)
    end
    for _, t in ipairs(VS.TYPE_ORDER) do
        out["vtype_" .. t] = T("vtype_" .. t)
    end
    return out
end

local texts = nil

function Sg.ensureDui(displayId)
    local dui = duis[displayId]
    if dui then
        return dui
    end
    local count = 0
    for _ in pairs(duis) do
        count = count + 1
    end
    if count >= (Config.maxActiveSigns or 6) then
        return nil
    end
    txd = txd or CreateRuntimeTxd(TXD)
    local obj = CreateDui(("nui://%s/html/sign.html"):format(RES), Config.sign.width, Config.sign.height)
    if not obj then
        return nil
    end
    textureCounter = textureCounter + 1
    local texName = "sign" .. textureCounter
    CreateRuntimeTextureFromDuiHandle(txd, texName, GetDuiHandle(obj))
    dui = { obj = obj, texture = texName, ready = false, payload = nil, createdAt = GetGameTimer() }
    duis[displayId] = dui
    -- The page has no way to tell us it is loaded; give it a moment, then send the data
    SetTimeout(600, function()
        if duis[displayId] == dui then
            dui.ready = true
            texts = texts or signTexts()
            SendDuiMessage(dui.obj, json.encode({ type = "texts", data = texts }))
            if dui.payload then
                send(dui, dui.payload)
            end
            -- Slow first load of the page: send everything once more
            SetTimeout(1500, function()
                if duis[displayId] == dui then
                    SendDuiMessage(dui.obj, json.encode({ type = "texts", data = texts }))
                    if dui.payload then
                        send(dui, dui.payload)
                    end
                end
            end)
        end
    end)
    return dui
end

function Sg.update(displayId, payload)
    local dui = duis[displayId]
    if not dui then
        return
    end
    local encoded = json.encode(payload)
    if dui.lastEncoded == encoded then
        return
    end
    dui.lastEncoded = encoded
    dui.payload = payload
    send(dui, payload)
end

function Sg.release(displayId)
    local dui = duis[displayId]
    if dui then
        DestroyDui(dui.obj)
        duis[displayId] = nil
    end
end

function Sg.activeIds()
    local out = {}
    for id in pairs(duis) do
        out[id] = true
    end
    return out
end

--- Draws the DUI texture on the screen corners (both windings, so it is visible regardless of culling).
function Sg.draw(displayId, entry)
    local dui = duis[displayId]
    if not dui or not dui.ready then
        return
    end
    local c = Sg.corners(entry)
    local tl, tr, br, bl = c[1], c[2], c[3], c[4]
    local tex = dui.texture
    DrawSpritePoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 255, 255, 255, 255, TXD, tex, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 255, 255, 255, 255, TXD, tex, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
    DrawSpritePoly(br.x, br.y, br.z, tr.x, tr.y, tr.z, tl.x, tl.y, tl.z, 255, 255, 255, 255, TXD, tex, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0)
    DrawSpritePoly(bl.x, bl.y, bl.z, br.x, br.y, br.z, tl.x, tl.y, tl.z, 255, 255, 255, 255, TXD, tex, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0)
end

AddEventHandler("onResourceStop", function(name)
    if name ~= RES then
        return
    end
    for id in pairs(duis) do
        Sg.release(id)
    end
end)
