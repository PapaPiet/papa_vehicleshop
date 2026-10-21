--- Tabellen von papa_vehicleshop. Der Präfix ist fest, damit ein umbenannter Ressourcen-Ordner
--- nicht plötzlich leere Tabellen sieht.

VS = VS or {}
VS.Db = VS.Db or {}

local PREFIX = "papa_vehicleshop"

function VS.Db.t(suffix)
    return ("`%s_%s`"):format(PREFIX, suffix)
end

VS.Db.ready = false

--- Column definitions declared in a CREATE TABLE statement: { name, definition }.
local function declaredColumns(sql)
    local cols = {}
    for line in sql:gmatch("[^\n]+") do
        local name, rest = line:match("^%s*`([%w_]+)`%s+(%u.-),?%s*$")
        if name then
            cols[#cols + 1] = { name = name, def = rest:gsub(",%s*$", "") }
        end
    end
    return cols
end

--- Creates a table, or adds columns that a newer version declares. Nothing is deleted.
local function ensureTable(sql, suffix)
    local raw = ("%s_%s"):format(PREFIX, suffix)
    local existing = MySQL.query.await(
        "SELECT `COLUMN_NAME` AS `name` FROM `INFORMATION_SCHEMA`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ?",
        { raw }
    ) or {}
    if #existing == 0 then
        MySQL.query.await(sql)
        return
    end
    local have = {}
    for _, row in ipairs(existing) do
        have[tostring(row.name):lower()] = true
    end
    for _, col in ipairs(declaredColumns(sql)) do
        if not have[col.name:lower()] then
            local def = col.def:gsub("AUTO_INCREMENT", "")
            MySQL.query.await(("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(raw, col.name, def))
            print(("^3[papa_vehicleshop] %s^0"):format(T("console_column_added", raw, col.name)))
        end
    end
end

local function createTables()
    local t = VS.Db.t

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(64) NOT NULL,
            `type` VARCHAR(16) NOT NULL DEFAULT 'player',
            `job` VARCHAR(64) NULL,
            `owner_id` VARCHAR(64) NULL,
            `owner_name` VARCHAR(96) NULL,
            `balance` BIGINT NOT NULL DEFAULT 0,
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            `settings_json` LONGTEXT NULL,
            `points_json` LONGTEXT NULL,
            `policy_json` LONGTEXT NULL,
            `catalog_json` LONGTEXT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("shops")), "shops")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `label` VARCHAR(64) NULL,
            `x` DOUBLE NOT NULL DEFAULT 0,
            `y` DOUBLE NOT NULL DEFAULT 0,
            `z` DOUBLE NOT NULL DEFAULT 0,
            `h` DOUBLE NOT NULL DEFAULT 0,
            `types_json` TEXT NULL,
            `sign_json` TEXT NULL,
            `kind` VARCHAR(16) NOT NULL DEFAULT 'stock',
            `stock_id` INT NULL,
            `showcase_model` VARCHAR(64) NULL,
            `showcase_color` INT NULL,
            `turntable` TINYINT(1) NOT NULL DEFAULT 0,
            `sort` INT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("displays")), "displays")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `plate` VARCHAR(16) NULL,
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(96) NULL,
            `vtype` VARCHAR(16) NOT NULL DEFAULT 'car',
            `status` VARCHAR(16) NOT NULL DEFAULT 'transit',
            `display_id` INT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `cost` INT NOT NULL DEFAULT 0,
            `props_json` LONGTEXT NULL,
            `condition_json` TEXT NULL,
            `source` VARCHAR(16) NOT NULL DEFAULT 'order',
            `delivery_point` VARCHAR(32) NULL,
            `eta` BIGINT NOT NULL DEFAULT 0,
            `arrived_at` BIGINT NOT NULL DEFAULT 0,
            `ordered_by` VARCHAR(96) NULL,
            `reserved_for` VARCHAR(64) NULL,
            `reserved_name` VARCHAR(96) NULL,
            `note` VARCHAR(255) NULL,
            `color` INT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            `sold_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_status` (`shop_id`, `status`),
            KEY `idx_plate` (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("stock")), "stock")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `buyer_id` VARCHAR(64) NOT NULL,
            `buyer_name` VARCHAR(96) NULL,
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(96) NULL,
            `vtype` VARCHAR(16) NOT NULL DEFAULT 'car',
            `price` INT NOT NULL DEFAULT 0,
            `plate` VARCHAR(16) NULL,
            `color` INT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'transit',
            `eta` BIGINT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `collected_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_buyer` (`buyer_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("customer_orders")), "customer_orders")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `stock_id` INT NOT NULL,
            `reward` INT NOT NULL DEFAULT 0,
            `payout` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(16) NOT NULL DEFAULT 'open',
            `note` VARCHAR(255) NULL,
            `taker_id` VARCHAR(64) NULL,
            `taker_name` VARCHAR(96) NULL,
            `taken_at` BIGINT NOT NULL DEFAULT 0,
            `deadline_at` BIGINT NOT NULL DEFAULT 0,
            `created_by` VARCHAR(96) NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `done_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_status` (`shop_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("contracts")), "contracts")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `stock_id` INT NULL,
            `plate` VARCHAR(16) NULL,
            `model` VARCHAR(64) NULL,
            `label` VARCHAR(96) NULL,
            `price` INT NOT NULL DEFAULT 0,
            `cost` INT NOT NULL DEFAULT 0,
            `buyer_id` VARCHAR(64) NULL,
            `buyer_name` VARCHAR(96) NULL,
            `seller_id` VARCHAR(64) NULL,
            `seller_name` VARCHAR(96) NULL,
            `method` VARCHAR(16) NOT NULL DEFAULT 'bank',
            `channel` VARCHAR(16) NOT NULL DEFAULT 'display',
            `commission` INT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_time` (`shop_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("sales")), "sales")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `sale_id` INT NULL,
            `plate` VARCHAR(16) NOT NULL,
            `label` VARCHAR(96) NULL,
            `buyer_id` VARCHAR(64) NOT NULL,
            `buyer_name` VARCHAR(96) NULL,
            `total` INT NOT NULL DEFAULT 0,
            `paid` INT NOT NULL DEFAULT 0,
            `rate` INT NOT NULL DEFAULT 0,
            `rates_left` INT NOT NULL DEFAULT 0,
            `interval_min` INT NOT NULL DEFAULT 60,
            `next_due_at` BIGINT NOT NULL DEFAULT 0,
            `missed` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(16) NOT NULL DEFAULT 'active',
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_buyer` (`buyer_id`, `status`),
            KEY `idx_shop_status` (`shop_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("finances")), "finances")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `amount` INT NOT NULL DEFAULT 0,
            `balance_after` BIGINT NOT NULL DEFAULT 0,
            `kind` VARCHAR(24) NOT NULL,
            `text` VARCHAR(255) NULL,
            `ref` VARCHAR(64) NULL,
            `actor_name` VARCHAR(96) NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_time` (`shop_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("ledger")), "ledger")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `plate` VARCHAR(16) NOT NULL,
            `model` VARCHAR(64) NULL,
            `label` VARCHAR(96) NULL,
            `vtype` VARCHAR(16) NOT NULL DEFAULT 'car',
            `seller_id` VARCHAR(64) NOT NULL,
            `seller_name` VARCHAR(96) NULL,
            `props_json` LONGTEXT NULL,
            `condition_json` TEXT NULL,
            `asking` INT NOT NULL DEFAULT 0,
            `offer` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(16) NOT NULL DEFAULT 'open',
            `offered_by` VARCHAR(96) NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            `expires_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_status` (`shop_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("tradeins")), "tradeins")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(96) NOT NULL,
            `brand` VARCHAR(64) NULL,
            `category` VARCHAR(32) NOT NULL DEFAULT 'other',
            `vtype` VARCHAR(16) NOT NULL DEFAULT 'car',
            `price` INT NOT NULL DEFAULT 0,
            `minutes` INT NULL,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `image` VARCHAR(255) NULL,
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("catalog")), "catalog")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` VARCHAR(32) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `types_json` TEXT NULL,
            `interact_json` TEXT NULL,
            `npc` VARCHAR(64) NULL,
            `blip_json` TEXT NULL,
            `spawns_json` LONGTEXT NULL,
            `water_json` LONGTEXT NULL,
            `air_json` LONGTEXT NULL,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("delivery_points")), "delivery_points")

    ensureTable(([[
        CREATE TABLE IF NOT EXISTS %s (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL DEFAULT 0,
            `actor_id` VARCHAR(64) NULL,
            `actor_name` VARCHAR(96) NULL,
            `action` VARCHAR(48) NOT NULL,
            `target` VARCHAR(128) NULL,
            `details_json` TEXT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_shop_time` (`shop_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(t("audit")), "audit")
end

CreateThread(function()
    local deadline = GetGameTimer() + 60000
    while GetResourceState("oxmysql") ~= "started" and GetGameTimer() < deadline do
        Wait(250)
    end
    createTables()
    VS.Db.ready = true
    TriggerEvent("papa_vehicleshop:server:dbReady")
end)
