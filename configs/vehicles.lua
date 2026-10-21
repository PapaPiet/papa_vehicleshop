--- Startkatalog. Wird beim ersten Start in die Datenbank übernommen (Config.seedCatalog),
--- danach pflegt der Admin den Katalog im OS-Admin oder im Admin-Menü.
--- model = Spawn-Name, type = Fahrzeugtyp (Config.vehicleTypes), price = Listenpreis,
--- minutes = Lieferzeit in echten Minuten (nil = Standard je Typ aus Config.delivery).

Config.catalogSeed = {
    -- Kompakt
    { model = "blista", label = "Blista", brand = "Dinka", category = "compacts", type = "car", price = 18000 },
    { model = "brioso", label = "Brioso R/A", brand = "Grotti", category = "compacts", type = "car", price = 21000 },
    { model = "issi2", label = "Issi", brand = "Weeny", category = "compacts", type = "car", price = 16500 },
    { model = "panto", label = "Panto", brand = "Benefactor", category = "compacts", type = "car", price = 12000 },
    { model = "prairie", label = "Prairie", brand = "Bollokan", category = "compacts", type = "car", price = 19000 },
    -- Limousinen
    { model = "asea", label = "Asea", brand = "Declasse", category = "sedans", type = "car", price = 22000 },
    { model = "fugitive", label = "Fugitive", brand = "Cheval", category = "sedans", type = "car", price = 32000 },
    { model = "primo", label = "Primo", brand = "Albany", category = "sedans", type = "car", price = 24000 },
    { model = "schafter2", label = "Schafter", brand = "Benefactor", category = "sedans", type = "car", price = 58000 },
    { model = "tailgater", label = "Tailgater", brand = "Obey", category = "sedans", type = "car", price = 48000 },
    { model = "cognoscenti", label = "Cognoscenti", brand = "Enus", category = "sedans", type = "car", price = 125000 },
    -- SUV
    { model = "baller2", label = "Baller", brand = "Gallivanter", category = "suvs", type = "car", price = 78000 },
    { model = "cavalcade2", label = "Cavalcade", brand = "Albany", category = "suvs", type = "car", price = 52000 },
    { model = "granger", label = "Granger", brand = "Declasse", category = "suvs", type = "car", price = 61000 },
    { model = "huntley", label = "Huntley S", brand = "Enus", category = "suvs", type = "car", price = 96000 },
    { model = "rocoto", label = "Rocoto", brand = "Obey", category = "suvs", type = "car", price = 64000 },
    -- Coupés
    { model = "f620", label = "F620", brand = "Ocelot", category = "coupes", type = "car", price = 88000 },
    { model = "felon", label = "Felon", brand = "Lampadati", category = "coupes", type = "car", price = 72000 },
    { model = "oracle2", label = "Oracle XS", brand = "Übermacht", category = "coupes", type = "car", price = 69000 },
    { model = "zion", label = "Zion", brand = "Übermacht", category = "coupes", type = "car", price = 66000 },
    -- Muscle
    { model = "dominator", label = "Dominator", brand = "Vapid", category = "muscle", type = "car", price = 74000 },
    { model = "gauntlet", label = "Gauntlet", brand = "Bravado", category = "muscle", type = "car", price = 69000 },
    { model = "sabregt", label = "Sabre Turbo", brand = "Declasse", category = "muscle", type = "car", price = 52000 },
    { model = "vigero", label = "Vigero", brand = "Declasse", category = "muscle", type = "car", price = 48000 },
    -- Sport
    { model = "elegy2", label = "Elegy RH8", brand = "Annis", category = "sports", type = "car", price = 155000 },
    { model = "feltzer2", label = "Feltzer", brand = "Benefactor", category = "sports", type = "car", price = 168000 },
    { model = "jester", label = "Jester", brand = "Dinka", category = "sports", type = "car", price = 182000 },
    { model = "massacro", label = "Massacro", brand = "Dewbauchee", category = "sports", type = "car", price = 210000 },
    { model = "sultan", label = "Sultan", brand = "Karin", category = "sports", type = "car", price = 92000 },
    { model = "comet2", label = "Comet", brand = "Pfister", category = "sports", type = "car", price = 195000 },
    -- Supersport
    { model = "adder", label = "Adder", brand = "Truffade", category = "super", type = "car", price = 1000000, minutes = 120 },
    { model = "entityxf", label = "Entity XF", brand = "Överflöd", category = "super", type = "car", price = 795000, minutes = 110 },
    { model = "t20", label = "T20", brand = "Progen", category = "super", type = "car", price = 1350000, minutes = 140 },
    { model = "zentorno", label = "Zentorno", brand = "Pegassi", category = "super", type = "car", price = 725000, minutes = 110 },
    -- Offroad
    { model = "bifta", label = "Bifta", brand = "BF", category = "offroad", type = "offroad", price = 38000 },
    { model = "dubsta3", label = "Dubsta 6x6", brand = "Benefactor", category = "offroad", type = "offroad", price = 245000 },
    { model = "mesa3", label = "Mesa", brand = "Canis", category = "offroad", type = "offroad", price = 58000 },
    { model = "rebel2", label = "Rebel", brand = "Karin", category = "offroad", type = "offroad", price = 34000 },
    { model = "sandking", label = "Sandking XL", brand = "Vapid", category = "offroad", type = "offroad", price = 76000 },
    -- Transporter
    { model = "burrito3", label = "Burrito", brand = "Declasse", category = "vans", type = "van", price = 42000 },
    { model = "minivan", label = "Minivan", brand = "Vapid", category = "vans", type = "van", price = 29000 },
    { model = "speedo", label = "Speedo", brand = "Vapid", category = "vans", type = "van", price = 39000 },
    { model = "youga", label = "Youga", brand = "Bravado", category = "vans", type = "van", price = 33000 },
    -- Nutzfahrzeuge
    { model = "benson", label = "Benson", brand = "Vapid", category = "commercial", type = "truck", price = 115000, minutes = 90 },
    { model = "mule", label = "Mule", brand = "Maibatsu", category = "commercial", type = "truck", price = 98000, minutes = 90 },
    { model = "pounder", label = "Pounder", brand = "MTL", category = "commercial", type = "truck", price = 165000, minutes = 100 },
    { model = "phantom", label = "Phantom", brand = "Jobuilt", category = "commercial", type = "truck", price = 210000, minutes = 110 },
    { model = "hauler", label = "Hauler", brand = "Jobuilt", category = "commercial", type = "truck", price = 185000, minutes = 110 },
    -- Motorräder
    { model = "akuma", label = "Akuma", brand = "Dinka", category = "motorcycles", type = "motorcycle", price = 38000 },
    { model = "bati", label = "Bati 801", brand = "Pegassi", category = "motorcycles", type = "motorcycle", price = 42000 },
    { model = "daemon", label = "Daemon", brand = "Western", category = "motorcycles", type = "motorcycle", price = 31000 },
    { model = "faggio2", label = "Faggio", brand = "Pegassi", category = "motorcycles", type = "motorcycle", price = 4500 },
    { model = "hexer", label = "Hexer", brand = "LCC", category = "motorcycles", type = "motorcycle", price = 29000 },
    { model = "pcj", label = "PCJ 600", brand = "Shitzu", category = "motorcycles", type = "motorcycle", price = 21000 },
    { model = "sanchez", label = "Sanchez", brand = "Maibatsu", category = "motorcycles", type = "motorcycle", price = 14000 },
    -- Fahrräder
    { model = "bmx", label = "BMX", brand = "", category = "cycles", type = "bicycle", price = 650 },
    { model = "cruiser", label = "Cruiser", brand = "", category = "cycles", type = "bicycle", price = 520 },
    { model = "scorcher", label = "Scorcher", brand = "", category = "cycles", type = "bicycle", price = 1800 },
    { model = "tribike", label = "Whippet Race Bike", brand = "", category = "cycles", type = "bicycle", price = 2600 },
    -- Boote
    { model = "dinghy", label = "Dinghy", brand = "Nagasaki", category = "boats", type = "boat", price = 52000 },
    { model = "jetmax", label = "Jetmax", brand = "Shitzu", category = "boats", type = "boat", price = 148000 },
    { model = "seashark", label = "Seashark", brand = "Speedophile", category = "boats", type = "boat", price = 18000 },
    { model = "speeder", label = "Speeder", brand = "Pegassi", category = "boats", type = "boat", price = 192000 },
    { model = "squalo", label = "Squalo", brand = "Shitzu", category = "boats", type = "boat", price = 98000 },
    { model = "toro", label = "Toro", brand = "Lampadati", category = "boats", type = "boat", price = 265000 },
    { model = "marquis", label = "Marquis", brand = "Dinka", category = "boats", type = "boat", price = 410000, minutes = 180 },
    -- Hubschrauber
    { model = "frogger", label = "Frogger", brand = "Maibatsu", category = "helicopters", type = "heli", price = 1250000, minutes = 180 },
    { model = "maverick", label = "Maverick", brand = "Western", category = "helicopters", type = "heli", price = 980000, minutes = 160 },
    { model = "supervolito", label = "SuperVolito", brand = "Buckingham", category = "helicopters", type = "heli", price = 1650000, minutes = 200 },
    { model = "swift", label = "Swift", brand = "Buckingham", category = "helicopters", type = "heli", price = 1480000, minutes = 190 },
    -- Flugzeuge
    { model = "cuban800", label = "Cuban 800", brand = "Western", category = "planes", type = "plane", price = 640000, minutes = 180 },
    { model = "dodo", label = "Dodo", brand = "Mammoth", category = "planes", type = "plane", price = 720000, minutes = 190 },
    { model = "duster", label = "Duster", brand = "Western", category = "planes", type = "plane", price = 380000, minutes = 150 },
    { model = "luxor", label = "Luxor", brand = "Buckingham", category = "planes", type = "plane", price = 2850000, minutes = 240 },
    { model = "mammatus", label = "Mammatus", brand = "Jobuilt", category = "planes", type = "plane", price = 520000, minutes = 170 },
    { model = "shamal", label = "Shamal", brand = "Buckingham", category = "planes", type = "plane", price = 2300000, minutes = 230 },
    { model = "vestra", label = "Vestra", brand = "Buckingham", category = "planes", type = "plane", price = 1450000, minutes = 210 },
}

--- Kategorien (Reihenfolge = Anzeige). Texte: category_<name>.
Config.categories = {
    "compacts", "sedans", "suvs", "coupes", "muscle", "sports", "super", "offroad", "vans", "commercial",
    "motorcycles", "cycles", "boats", "helicopters", "planes", "other",
}
