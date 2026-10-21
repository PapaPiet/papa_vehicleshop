--- Wer bin ich, zu welchem Autohaus gehöre ich, was darf ich?

VS = VS or {}
VS.Access = VS.Access or {}

local U = VS.U
local A = VS.Access

A.POLICY_KEYS = {
    "stockView", "stockManage", "displayManage", "priceEdit", "order", "contracts", "sell", "discount",
    "tradeIn", "finance", "accountView", "accountManage", "settings", "auditView",
}

local function stateFromCore(src)
    if not U.coreHasExport("GetPlayerState") then
        return nil
    end
    return U.core():GetPlayerState(src)
end

--- Snapshot of the calling player. Returns nil if the character is not loaded.
function A.actor(src)
    src = tonumber(src)
    if not src or src <= 0 then
        return nil
    end
    local st = stateFromCore(src)
    local actor
    if st and st.identifier then
        local job = st.job or {}
        actor = {
            src = src,
            id = st.identifier,
            name = st.name or U.trim(((st.firstname or "") .. " " .. (st.lastname or ""))),
            job = job.name and tostring(job.name):lower() or nil,
            jobLabel = job.label or job.name,
            grade = tonumber(job.grade) or 0,
            gradeLabel = job.gradeLabel or "",
            isBoss = job.isBoss == true,
            onDuty = job.onDuty ~= false,
            isAdmin = st.isAdmin == true,
        }
    else
        local snap = PAPA.Functions.getPlayerSnapshot(src)
        if not snap or not snap.identifier then
            return nil
        end
        local job = snap.job or {}
        actor = {
            src = src,
            id = snap.identifier,
            name = snap.name or U.trim((snap.firstname or "") .. " " .. (snap.lastname or "")),
            job = job.name and tostring(job.name):lower() or nil,
            jobLabel = job.label or job.name,
            grade = tonumber(job.grade) or 0,
            gradeLabel = job.gradeLabel or "",
            isBoss = job.isBoss == true,
            onDuty = job.onDuty ~= false,
            isAdmin = snap.isAdmin == true,
        }
    end
    if not actor.name or actor.name == "" then
        actor.name = T("unknown_person")
    end
    if not actor.isAdmin then
        actor.isAdmin = PAPA.Functions.isPlayerAdmin(src) == true
    end
    return actor
end

--- true when the actor works in the shop (job match or owner).
function A.isStaff(actor, shop)
    if not actor or not shop or not shop.active or shop.type == "npc" then
        return false
    end
    if shop.ownerId and shop.ownerId == actor.id then
        return true
    end
    return shop.job ~= nil and actor.job == shop.job
end

--- Boss of the shop: job boss or shop owner.
function A.isBoss(actor, shop)
    if not A.isStaff(actor, shop) then
        return false
    end
    if shop.ownerId and shop.ownerId == actor.id then
        return true
    end
    return actor.isBoss == true
end

--- Shops the actor works in.
function A.shopsOf(actor)
    local out = {}
    if not actor then
        return out
    end
    for _, shop in ipairs(VS.Shops.all()) do
        if A.isStaff(actor, shop) then
            out[#out + 1] = shop
        end
    end
    return out
end

--- Permission check inside a shop.
function A.can(actor, shop, key)
    if not A.isStaff(actor, shop) then
        return false
    end
    if A.isBoss(actor, shop) then
        return true
    end
    local need = shop.policy[key]
    if need == nil then
        return false
    end
    return (actor.grade or 0) >= need
end

--- All permission flags for the UI and menus.
function A.flags(actor, shop)
    local out = {}
    for _, key in ipairs(A.POLICY_KEYS) do
        out[key] = A.can(actor, shop, key)
    end
    out.boss = A.isBoss(actor, shop)
    out.owner = shop and shop.ownerId ~= nil and shop.ownerId == actor.id or false
    out.admin = actor.isAdmin == true
    return out
end

--- Online staff of a shop (sources).
function A.onlineStaff(shop)
    local out = {}
    for _, snap in ipairs(PAPA.Functions.getAllPlayerSnapshots() or {}) do
        local job = snap.job and snap.job.name and tostring(snap.job.name):lower()
        if snap.source and ((shop.job and job == shop.job) or (shop.ownerId and snap.identifier == shop.ownerId)) then
            out[#out + 1] = snap.source
        end
    end
    return out
end
