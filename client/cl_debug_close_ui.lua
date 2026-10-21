--- Notfall-Befehl debugCloseUI (F8-Konsole oder Chat): schließt in jeder Papa-Ressource die Oberfläche,
--- gibt den Mauszeiger frei und räumt Kamera, Animation und Props auf - ohne Reconnect.
--- Jede Ressource registriert den Befehl selbst, weil der NUI-Fokus je Ressource gilt. Das Ereignis trägt
--- einen Zeitstempel, damit jede Ressource pro Aufruf nur einmal aufräumt, auch wenn mehrere Befehle feuern.

local lastDebugCloseStamp = nil

function DebugCloseUI()
    --- Die Werkstatt-Oberfläche läuft im papa_os_core-Fenster; hier nur den eigenen NUI-Fokus freigeben
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
end

AddEventHandler("papa:client:debugCloseUI", function(stamp)
    if stamp ~= nil and stamp == lastDebugCloseStamp then
        return
    end
    lastDebugCloseStamp = stamp
    DebugCloseUI()
end)

RegisterCommand("debugCloseUI", function()
    TriggerEvent("papa:client:debugCloseUI", GetGameTimer())
end, false)
