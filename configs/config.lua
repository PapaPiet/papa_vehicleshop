Config = Config or {}

--- Sprache für alle Texte (locales/translations/<code>.lua).
Config.Language = "de"

--- Debug-Ausgaben in der Server- und Client-Konsole.
Config.Debug = false

--- Lokaler Cache in der Papa-OS-App (nur lesende Anfragen). false = jede Anfrage geht an den Server.
Config.UiCache = true

-- ============================================================================================
-- Papa OS (optional)
-- ============================================================================================

--- Läuft papa_os_core, registriert sich das Autohaus-Dashboard als App und der Admin-Bereich im OS-Admin.
--- Ohne papa_os_core funktioniert alles über die normalen Menüs (Terminal im Autohaus, Admin-Befehl).
Config.os = {
    enabled = true,
    appId = "vehicleshop_mdt",
    iconPath = "icon.png",
    --- true = App auch auf dem Handy (papa_os_phone)
    phone = true,
    --- true = vorinstalliert, false = über "Programme" installieren
    defaultApp = false,
    storeCategory = "work",
    adminPanel = {
        enabled = true,
        id = "papa_vehicleshop:admin",
        icon = "car",
        group = "manage",
        order = 45,
    },
}

-- ============================================================================================
-- Admin
-- ============================================================================================

--- Admin-Menü ohne Papa OS. Admin = papa_bridge isPlayerAdmin (ACE papa_bridge).
Config.adminCommand = "vehicleshopadmin"

--- Staff-Menü per Befehl (zusätzlich zum Terminal im Autohaus). nil = nur am Terminal.
Config.staffCommand = "dealer"

-- ============================================================================================
-- Interaktion
-- ============================================================================================

--- true = papa_bridge Target (ox_target / qb-target ...), false = Hinweistext und Taste.
Config.useTarget = true

--- Taste für Interaktionen ohne Target (Name aus papa_bridge ConvertKeyToId, z. B. "E").
Config.interactKey = "E"

--- Reichweite für Interaktionen ohne Target.
Config.interactDistance = 2.0

--- Ab dieser Entfernung werden Ausstellungsfahrzeuge, Schilder und NPCs erzeugt.
Config.renderDistance = 90.0

--- Höchstzahl gleichzeitig aktiver Preisschilder mit Bildschirm (DUI). Jedes Schild ist ein eigener Browser.
Config.maxActiveSigns = 6

--- Entfernung, ab der ein Preisschild seinen Bildschirm bekommt.
Config.signDistance = 25.0

-- ============================================================================================
-- Fahrzeugtypen
-- ============================================================================================

--- Alle Typen, die das System kennt. Texte: vtype_<typ>.
--- spawnType = Typ für CreateVehicleServerSetter, water = Fahrzeug startet auf dem Wasser.
Config.vehicleTypes = {
    car = { spawnType = "automobile", icon = "car" },
    motorcycle = { spawnType = "bike", icon = "motorcycle" },
    bicycle = { spawnType = "bike", icon = "bicycle" },
    truck = { spawnType = "automobile", icon = "truck" },
    van = { spawnType = "automobile", icon = "van" },
    offroad = { spawnType = "automobile", icon = "offroad" },
    boat = { spawnType = "boat", icon = "boat", water = true },
    heli = { spawnType = "heli", icon = "heli" },
    plane = { spawnType = "plane", icon = "plane" },
}

--- GTA-Fahrzeugklasse -> Typ (für Fahrzeuge, die nicht im Katalog stehen, z. B. Inzahlungnahme).
Config.classToType = {
    [0] = "car", [1] = "car", [2] = "offroad", [3] = "car", [4] = "car", [5] = "car", [6] = "car", [7] = "car",
    [8] = "motorcycle", [9] = "offroad", [10] = "truck", [11] = "truck", [12] = "van", [13] = "bicycle",
    [14] = "boat", [15] = "heli", [16] = "plane", [17] = "truck", [18] = "car", [19] = "offroad", [20] = "truck",
    [22] = "car",
}

-- ============================================================================================
-- Ausstellungsplätze und Preisschild
-- ============================================================================================

Config.display = {
    --- Typen, die ein neuer Ausstellungsplatz annimmt, wenn der Admin nichts auswählt.
    defaultTypes = { "car", "offroad", "van" },
    --- Ausstellungsfahrzeuge drehen sich langsam (nur auf Plätzen mit "Drehteller").
    turntableSpeed = 0.15,
    --- Ausstellungsfahrzeuge sind abgeschlossen, Türen zu, Motor aus.
    locked = true,
}

--- Preisschild neben dem Fahrzeug. Das Modell ist ein eigenes Prop (WIP). Der Bildschirm (DUI) wird auf die
--- Fläche "screen" des Props gezeichnet (Ecken relativ zum Prop). Fehlt das Modell, steht der Bildschirm
--- frei im Raum (fallbackScreen) auf einem einfachen Pfosten.
Config.sign = {
    enabled = true,
    model = "papa_vehicleshop_sign",
    --- Standard-Versatz relativ zum Ausstellungsplatz (rechts vorne), Admin kann ihn je Platz ändern
    offset = { x = 2.2, y = 2.0, z = 0.0, h = 200.0 },
    --- Auflösung des Bildschirms (Seitenverhältnis wie die Fläche)
    width = 512,
    height = 768,
    --- Bildschirmfläche auf dem Prop (Prop-Koordinaten in Metern), an das fertige Modell anpassen
    screen = {
        topLeft = vector3(-0.33, -0.03, 1.95),
        topRight = vector3(0.33, -0.03, 1.95),
        bottomRight = vector3(0.33, -0.03, 0.96),
        bottomLeft = vector3(-0.33, -0.03, 0.96),
    },
    --- Fläche im Raum, wenn das Prop fehlt (Breite und Höhe in Metern, Unterkante über Boden)
    fallbackScreen = { width = 0.66, height = 0.99, lift = 0.95 },
    --- Pfosten unter dem freien Bildschirm (nil = ohne)
    fallbackPost = "prop_sign_road_restriction_10",
}

-- ============================================================================================
-- Lieferung, Häfen und Flugplätze
-- ============================================================================================

--- Wo bestellte Fahrzeuge ankommen. Jeder Ort nimmt bestimmte Typen an.
--- spawns = Stellplätze (vector4). Boote brauchen Plätze auf dem Wasser, Flugzeuge auf dem Rollfeld.
Config.deliveryPoints = {
    {
        id = "port",
        label = "Hafen Los Santos",
        types = { "car", "motorcycle", "bicycle", "truck", "van", "offroad", "boat" },
        interact = vector4(1204.24, -3116.53, 5.54, 0.0),
        npc = "s_m_y_dockwork_01",
        blip = { sprite = 410, color = 3, scale = 0.75 },
        spawns = {
            vector4(1196.12, -3105.85, 5.57, 0.0),
            vector4(1191.43, -3105.85, 5.57, 0.0),
            vector4(1186.74, -3105.85, 5.57, 0.0),
            vector4(1182.05, -3105.85, 5.57, 0.0),
        },
        waterSpawns = {
            vector4(1252.12, -3238.40, 0.30, 90.0),
            vector4(1252.12, -3250.40, 0.30, 90.0),
        },
    },
    {
        id = "lsia",
        label = "Flughafen Los Santos",
        types = { "plane", "heli", "car", "motorcycle", "van", "offroad" },
        interact = vector4(-1023.67, -2730.23, 13.76, 240.0),
        npc = "s_m_y_airworker",
        blip = { sprite = 90, color = 3, scale = 0.75 },
        spawns = {
            vector4(-1015.28, -2736.53, 13.76, 240.0),
            vector4(-1011.62, -2742.36, 13.76, 240.0),
        },
        airSpawns = {
            vector4(-1274.12, -3385.06, 13.94, 330.0),
            vector4(-1149.73, -3362.47, 13.94, 330.0),
        },
    },
    {
        id = "sandy",
        label = "Flugplatz Sandy Shores",
        types = { "plane", "heli" },
        interact = vector4(1733.66, 3294.07, 41.22, 195.0),
        npc = "s_m_y_airworker",
        blip = { sprite = 90, color = 3, scale = 0.65 },
        spawns = {},
        airSpawns = {
            vector4(1738.75, 3282.52, 41.10, 195.0),
            vector4(1719.31, 3256.95, 41.18, 105.0),
        },
    },
}

Config.delivery = {
    --- Lieferzeit in echten Minuten, wenn der Katalog nichts angibt (je Typ)
    defaultMinutes = {
        car = 45, motorcycle = 30, bicycle = 15, truck = 75, van = 45, offroad = 45,
        boat = 90, heli = 120, plane = 150,
    },
    --- Zufällige Abweichung der Lieferzeit in Prozent (+/-)
    jitterPercent = 15,
    --- Wie lange ein angekommenes Fahrzeug kostenlos am Hafen/Flugplatz steht (Stunden). Danach Standgeld je Tag.
    freeStorageHours = 48,
    storageFeePerDay = 250,
    --- Garage, in der ein abgeholtes Fahrzeug im Framework steht, solange es dem Autohaus gehört
    --- und weder ausgestellt noch eingelagert ist. Das Lager des Autohauses heißt "papa_vs_<shopId>".
    garagePrefix = "papa_vs_",
    --- Garage im Framework, in die ein Fahrzeug kommt, wenn das Autohaus es aus dem Bestand freigibt
    --- (es bleibt beim Inhaber). Name wie in eurem Garagen-Script, z. B. "pillboxgarage" (qb-garages) oder "SanAndreasAvenue" (esx).
    releaseGarage = "pillboxgarage",
}

--- Transportaufträge: Spieler holen bestellte Fahrzeuge für ein Autohaus ab und werden bezahlt.
Config.contracts = {
    enabled = true,
    --- Zeit, um ein angenommenes Fahrzeug abzuliefern (Minuten)
    deadlineMinutes = 30,
    --- Vorschlag für die Bezahlung: Grundbetrag + Prozent vom Einkaufspreis
    suggestBase = 250,
    suggestPercent = 1.5,
    --- Abzug in Prozent je 10 % Schaden (Karosserie oder Motor)
    damagePenaltyPer10 = 5,
    --- Wer darf Aufträge annehmen? false = jeder, true = nur Spieler ohne Job des Autohauses
    onlyExternal = false,
    --- Zusätzliche Auftragstafeln (vector4), neben Häfen und Flugplätzen
    boards = {},
}

-- ============================================================================================
-- Kauf, Probefahrt, Finanzierung, Inzahlungnahme
-- ============================================================================================

Config.purchase = {
    --- Zahlarten am Ausstellungsfahrzeug
    methods = { "bank", "cash" },
    --- Gekauftes Fahrzeug direkt am Übergabepunkt bereitstellen (true) oder nur in die Garage stellen (false)
    spawnAtHandover = true,
    --- Garage im Framework für gekaufte Fahrzeuge (nil = Standardgarage der Bridge)
    garage = nil,
    --- Wunschkennzeichen beim Kauf erlauben
    customPlate = { enabled = true, price = 1500, minLength = 2, maxLength = 8 },
}

Config.testDrive = {
    --- Standard für neue Autohäuser (pro Autohaus änderbar)
    enabled = true,
    seconds = 180,
    deposit = 500,
    --- Fahrzeugtypen ohne Probefahrt
    blockedTypes = { "plane", "heli", "boat" },
    --- Abstand zur Übergabe, ab dem das Fahrzeug als zurückgebracht gilt
    returnRadius = 12.0,
}

Config.finance = {
    --- Standard für neue Autohäuser (pro Autohaus änderbar)
    enabled = true,
    downPaymentPercent = 20,
    installments = 10,
    --- Abstand der Raten in echten Minuten
    intervalMinutes = 60,
    interestPercent = 8,
    --- Ab so vielen verpassten Raten darf das Autohaus das Fahrzeug zurückholen
    maxMissed = 3,
    --- Mindestpreis für eine Finanzierung
    minPrice = 10000,
}

Config.tradeIn = {
    --- Standard für neue Autohäuser
    enabled = true,
    --- NPC-Ankauf (NPC-Autohaus oder gemischt ohne Personal): Anteil vom Katalogpreis in Prozent
    npcPercent = 45,
    --- Abzug je 10 % Schaden in Prozentpunkten
    damagePenaltyPer10 = 4,
    --- Fahrzeuge, die nicht im Katalog stehen, kauft der NPC nicht an
    npcRequiresCatalog = true,
    --- Wie lange eine Anfrage an das Personal offen bleibt (Minuten)
    requestMinutes = 10,
}

-- ============================================================================================
-- Standardwerte für neue Autohäuser (Admin und Chef können sie je Autohaus ändern)
-- ============================================================================================

Config.shopDefaults = {
    currency = "$",
    --- NPC-Preis = Katalogpreis * Faktor
    npcPriceMultiplier = 1.0,
    --- Einkaufspreis des Autohauses beim Hersteller = Katalogpreis * Faktor
    wholesaleMultiplier = 0.72,
    --- Gemischt: so viele Mitarbeiter im Dienst, damit der NPC Feierabend hat
    minStaffOnline = 1,
    --- Gemischt: NPC verkauft dann zu diesem Faktor (z. B. teurer als beim Personal)
    mixedNpcMultiplier = 1.15,
    --- Provision für den Verkäufer in Prozent (nur Verkäufe über Personal)
    commissionPercent = 5,
    --- Höchster Rabatt ohne Chef in Prozent
    maxDiscountPercent = 10,
    --- NPC-Katalogkauf: Lieferzeit aus dem Katalog nutzen (false = Fahrzeug sofort)
    npcDelivery = false,
    --- Höchstzahl Fahrzeuge im Lager (0 = unbegrenzt)
    storageLimit = 0,
    blip = { enabled = true, sprite = 326, color = 3, scale = 0.8 },
}

--- Rechte mit Mindest-Dienstgrad (Chef darf immer alles). Pro Autohaus änderbar.
Config.policyDefaults = {
    stockView = 0,
    stockManage = 0,
    displayManage = 0,
    priceEdit = 1,
    order = 2,
    contracts = 1,
    sell = 0,
    discount = 2,
    tradeIn = 1,
    finance = 2,
    accountView = 2,
    accountManage = 3,
    settings = 3,
    auditView = 2,
}

-- ============================================================================================
-- Katalog
-- ============================================================================================

--- Globale Sperrliste: diese Modelle gibt es in keinem Autohaus (zusätzlich zur Admin-Liste).
Config.globalBlacklist = {
    "rhino", "khanjali", "oppressor", "oppressor2", "hydra", "lazer", "savage", "hunter", "akula",
}

--- Beim ersten Start wird der Katalog aus configs/vehicles.lua in die Datenbank übernommen.
--- Danach pflegt der Admin ihn im OS-Admin oder im Admin-Menü.
Config.seedCatalog = true

-- ============================================================================================
-- Kaufvertrag (Papa OS, optional)
-- ============================================================================================

Config.documents = {
    --- Der Käufer bekommt den Kaufvertrag als Dokument in seine Papa-OS-Dateien
    enabled = true,
    --- Kaufvertrag zusätzlich per Mail an den Käufer (wenn er ein Mail-Konto hat)
    mailToBuyer = true,
}

-- ============================================================================================
-- Firmenkonto
-- ============================================================================================

--- "internal" = eigenes Konto im Autohaus (Standard). "papa_os_banking" = Firmenkonto aus papa_os_banking
--- für Autohäuser mit Job (wenn die Ressource läuft), sonst intern.
Config.accountProvider = "internal"
