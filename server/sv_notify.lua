--- Benachrichtigungen: papa_bridge Notify, mit Papa OS zusätzlich als PC-/Handy-Benachrichtigung.

VS = VS or {}
VS.Notify = VS.Notify or {}

local U = VS.U
local N = VS.Notify

--- Short bridge notification for one player.
function N.player(src, text, kind, duration)
    if not src or src <= 0 then
        return
    end
    PAPA.Functions.NotifyPlayer(src, text, duration or 6000, kind or "info")
end

--- Papa OS notification (falls back to the bridge notification without Papa OS).
function N.os(src, title, text, kind)
    if U.coreHasExport("SendPcNotificationToSource") then
        U.core():SendPcNotificationToSource(src, title, text, {
            kind = "system",
            notifyBridge = true,
            bridgeType = kind or "info",
            bridgeMessage = text,
        })
        return
    end
    N.player(src, text, kind)
end

--- Notification for a character by identifier (only if online).
function N.identifier(identifier, title, text, kind)
    if not identifier then
        return
    end
    local src = PAPA.Functions.getPlayerSourceByCitizenId(identifier)
    if src then
        N.os(src, title, text, kind)
    end
end

--- All online staff of a shop (job members and owner).
function N.staff(shop, text, kind)
    if not shop then
        return
    end
    for _, src in ipairs(VS.Access.onlineStaff(shop)) do
        N.os(src, shop.label, text, kind)
    end
end
