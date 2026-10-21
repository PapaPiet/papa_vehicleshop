--- Admin-Menü ohne Papa OS (Befehl Config.adminCommand). Autohäuser anlegen, Punkte und Ausstellungsplätze an der
--- eigenen Position setzen, Einstellungen, Katalog (global und je Autohaus) und Lieferorte. Der Server prüft Admin-Rechte.

VS = VS or {}

local U = VS.U

local function rpc(action, payload)
    return U.rpc(action, payload or {})
end

local openShop, openShops, openDisplays, openDisplay, openCatalog, openPoints, openPoint

local function typeRows(selected)
    local rows = {}
    local set = {}
    for _, t in ipairs(selected or {}) do
        set[t] = true
    end
    for _, t in ipairs(VS.TYPE_ORDER) do
        rows[#rows + 1] = { type = "checkbox", label = T("vtype_" .. t), checked = set[t] == true }
    end
    return rows
end

local function typesFromResult(res, offset)
    local out = {}
    for i, t in ipairs(VS.TYPE_ORDER) do
        if res[(offset or 0) + i] then
            out[#out + 1] = t
        end
    end
    return out
end

local function typeOptions()
    local list = {}
    for _, t in ipairs(VS.TYPE_ORDER) do
        list[#list + 1] = { label = T("vtype_" .. t), value = t }
    end
    return list
end

local function categoryOptions()
    local list = {}
    for _, c in ipairs(Config.categories) do
        list[#list + 1] = { label = T("category_" .. c), value = c }
    end
    return list
end

-- Shop ----------------------------------------------------------------------------------------

local function editBase(shop)
    local typeList = {
        { label = T("shoptype_npc"), value = "npc" },
        { label = T("shoptype_player"), value = "player" },
        { label = T("shoptype_mixed"), value = "mixed" },
    }
    local res = U.input(shop and T("admin_edit_shop") or T("admin_new_shop"), {
        { type = "input", label = T("admin_shop_label"), default = shop and shop.label or "", required = true, max = 64 },
        { type = "select", label = T("admin_shop_type"), options = typeList, default = shop and shop.type or "player", required = true, description = T("admin_shop_type_desc") },
        { type = "input", label = T("admin_shop_job"), default = shop and shop.job or "", required = false, description = T("admin_shop_job_desc") },
        { type = "input", label = T("admin_shop_owner"), default = shop and shop.ownerId or "", required = false, description = T("admin_shop_owner_desc") },
        { type = "checkbox", label = T("admin_shop_active"), checked = shop == nil or shop.active },
    })
    if not res then
        return nil
    end
    return { label = res[1], type = res[2], job = res[3] or "", ownerId = res[4] or "", active = res[5] == true }
end

local function chooseOwner(shop)
    local list = rpc("admin.players", {})
    if not list then
        return
    end
    local options = {}
    for _, p in ipairs(list) do
        options[#options + 1] = { label = p.name, description = ("%s · %s"):format(p.identifier, p.job), icon = "user", args = { id = p.identifier } }
    end
    U.menu(T("admin_choose_owner"), options, function(args)
        if rpc("admin.shop.update", { shopId = shop.id, shop = { ownerId = args.id } }) then
            U.notify(T("saved"), "success")
        end
        openShop(shop.id)
    end, function()
        openShop(shop.id)
    end)
end

local function editSettings(shop)
    local s = shop.settings
    local res = U.input(T("admin_settings"), {
        { type = "number", label = T("set_npcPriceMultiplier"), default = s.npcPriceMultiplier, min = 0.1, max = 10, step = 0.01, precision = 2 },
        { type = "number", label = T("set_wholesaleMultiplier"), default = s.wholesaleMultiplier, min = 0.05, max = 5, step = 0.01, precision = 2 },
        { type = "number", label = T("set_mixedNpcMultiplier"), default = s.mixedNpcMultiplier, min = 0.1, max = 10, step = 0.01, precision = 2 },
        { type = "number", label = T("set_minStaffOnline"), default = s.minStaffOnline, min = 1, max = 50 },
        { type = "number", label = T("set_commissionPercent"), default = s.commissionPercent, min = 0, max = 50 },
        { type = "number", label = T("set_maxDiscountPercent"), default = s.maxDiscountPercent, min = 0, max = 100 },
        { type = "number", label = T("set_storageLimit"), default = s.storageLimit, min = 0, max = 10000 },
        { type = "number", label = T("set_dropoffRadius"), default = s.dropoffRadius, min = 2, max = 40 },
        { type = "checkbox", label = T("set_npcDelivery"), checked = s.npcDelivery == true },
        { type = "input", label = T("set_npcModel"), default = s.npcModel },
        { type = "checkbox", label = T("set_blip"), checked = s.blip.enabled == true },
        { type = "number", label = T("set_blipSprite"), default = s.blip.sprite, min = 1, max = 900 },
        { type = "number", label = T("set_blipColor"), default = s.blip.color, min = 0, max = 85 },
        { type = "checkbox", label = T("set_testDrive"), checked = s.testDrive.enabled == true },
        { type = "number", label = T("set_testDriveSeconds"), default = s.testDrive.seconds, min = 30, max = 1800 },
        { type = "number", label = T("set_testDriveDeposit"), default = s.testDrive.deposit, min = 0 },
        { type = "checkbox", label = T("set_finance"), checked = s.finance.enabled == true },
        { type = "checkbox", label = T("set_tradeIn"), checked = s.tradeIn.enabled == true },
        { type = "number", label = T("set_tradeInNpcPercent"), default = s.tradeIn.npcPercent, min = 0, max = 100 },
    })
    if not res then
        return
    end
    local settings = {
        npcPriceMultiplier = res[1], wholesaleMultiplier = res[2], mixedNpcMultiplier = res[3], minStaffOnline = res[4],
        commissionPercent = res[5], maxDiscountPercent = res[6], storageLimit = res[7], dropoffRadius = res[8],
        npcDelivery = res[9] == true, npcModel = res[10],
        blip = { enabled = res[11] == true, sprite = res[12], color = res[13] },
        testDrive = { enabled = res[14] == true, seconds = res[15], deposit = res[16] },
        finance = { enabled = res[17] == true },
        tradeIn = { enabled = res[18] == true, npcPercent = res[19] },
    }
    if rpc("admin.shop.update", { shopId = shop.id, shop = { settings = settings } }) then
        U.notify(T("saved"), "success")
    end
end

local function editCatalogFilter(shop)
    local f = shop.catalog or { mode = "all", models = {}, categories = {}, types = {} }
    local rows = {
        { type = "select", label = T("admin_catalog_mode"), options = {
            { label = T("catalog_mode_all"), value = "all" },
            { label = T("catalog_mode_whitelist"), value = "whitelist" },
            { label = T("catalog_mode_blacklist"), value = "blacklist" },
        }, default = f.mode, required = true },
        { type = "textarea", label = T("admin_catalog_models"), default = table.concat(f.models or {}, ", "), description = T("admin_catalog_models_desc") },
        { type = "multi-select", label = T("admin_catalog_categories"), options = categoryOptions(), default = f.categories or {} },
        { type = "multi-select", label = T("admin_catalog_types"), options = typeOptions(), default = f.types or {}, description = T("admin_catalog_types_desc") },
    }
    local res = U.input(T("admin_catalog_filter"), rows)
    if not res then
        return
    end
    local models = {}
    for m in tostring(res[2] or ""):gmatch("[^,%s]+") do
        models[#models + 1] = m:lower()
    end
    if rpc("admin.shop.update", { shopId = shop.id, shop = { catalog = { mode = res[1], models = models, categories = res[3] or {}, types = res[4] or {} } } }) then
        U.notify(T("saved"), "success")
    end
end

local function setPoint(shop, key)
    local options = {
        { label = T("admin_point_here"), description = T("admin_point_here_desc"), icon = "location-crosshairs", args = { action = "here" } },
    }
    local p = shop.points[key]
    if p then
        options[#options + 1] = { label = T("admin_point_goto"), icon = "route", args = { action = "goto" } }
        options[#options + 1] = { label = T("admin_point_remove"), icon = "trash", args = { action = "remove" } }
    end
    U.menu(T("point_key_" .. key), options, function(args)
        if args.action == "here" then
            local pos = U.myPosition()
            if rpc("admin.shop.point", { shopId = shop.id, key = key, coords = pos }) then
                U.notify(T("saved"), "success")
            end
        elseif args.action == "goto" then
            SetNewWaypoint(p.x + 0.0, p.y + 0.0)
        elseif args.action == "remove" then
            rpc("admin.shop.point", { shopId = shop.id, key = key, coords = false })
        end
        openShop(shop.id)
    end, function()
        openShop(shop.id)
    end)
end

openDisplay = function(shopId, displayId)
    local shop = rpc("admin.shop.get", { shopId = shopId })
    if not shop then
        return
    end
    local d
    for _, x in ipairs(shop.displays) do
        if x.id == displayId then
            d = x
        end
    end
    if not d then
        openDisplays(shopId)
        return
    end
    local back = function()
        openDisplay(shopId, displayId)
    end
    local options = {
        { label = T("admin_display_move"), description = T("admin_display_move_desc"), icon = "location-crosshairs", args = { action = "move" } },
        { label = T("admin_display_edit"), icon = "pen", args = { action = "edit" } },
        { label = d.sign.enabled and T("admin_sign_off") or T("admin_sign_on"), icon = "display", args = { action = "sign" } },
        { label = T("admin_sign_here"), description = T("admin_sign_here_desc"), icon = "location-crosshairs", args = { action = "signHere" } },
        { label = T("admin_sign_reset"), icon = "rotate-left", args = { action = "signReset" } },
        { label = T("admin_point_goto"), icon = "route", args = { action = "goto" } },
        { label = T("admin_display_delete"), icon = "trash", disabled = d.vehicle ~= nil, args = { action = "delete" } },
    }
    U.menu(d.label ~= "" and d.label or T("display_number", d.id), options, function(args)
        local a = args.action
        if a == "move" then
            rpc("admin.display.update", { displayId = d.id, display = { coords = U.myPosition() } })
        elseif a == "edit" then
            local rows = {
                { type = "input", label = T("admin_display_label"), default = d.label, max = 64 },
                { type = "select", label = T("admin_display_kind"), options = {
                    { label = T("display_kind_stock"), value = "stock" },
                    { label = T("display_kind_showcase"), value = "showcase" },
                }, default = d.kind, description = T("admin_display_kind_desc") },
                { type = "checkbox", label = T("admin_display_turntable"), checked = d.turntable == true },
            }
            for _, r in ipairs(typeRows(d.types)) do
                rows[#rows + 1] = r
            end
            local res = U.input(T("admin_display_edit"), rows)
            if res then
                rpc("admin.display.update", { displayId = d.id, display = { label = res[1], kind = res[2], turntable = res[3] == true, types = typesFromResult(res, 3) } })
            end
        elseif a == "sign" then
            rpc("admin.display.update", { displayId = d.id, display = { sign = { enabled = not d.sign.enabled } } })
        elseif a == "signHere" then
            local pos = U.myPosition()
            pos.w = (pos.w + 180.0) % 360.0
            rpc("admin.display.update", { displayId = d.id, display = { sign = { world = pos } } })
        elseif a == "signReset" then
            rpc("admin.display.update", { displayId = d.id, display = { sign = { world = false, offset = Config.sign.offset } } })
        elseif a == "goto" then
            SetNewWaypoint(d.x + 0.0, d.y + 0.0)
        elseif a == "delete" then
            if U.confirm(T("admin_display_delete"), T("admin_display_delete_text")) then
                rpc("admin.display.delete", { displayId = d.id })
                openDisplays(shopId)
                return
            end
        end
        back()
    end, function()
        openDisplays(shopId)
    end)
end

openDisplays = function(shopId)
    local shop = rpc("admin.shop.get", { shopId = shopId })
    if not shop then
        return
    end
    local options = {
        { label = T("admin_display_add"), description = T("admin_display_add_desc"), icon = "plus", args = { action = "add" } },
    }
    for _, d in ipairs(shop.displays) do
        local types = {}
        for _, t in ipairs(d.types) do
            types[#types + 1] = T("vtype_" .. t)
        end
        options[#options + 1] = {
            label = d.label ~= "" and d.label or T("display_number", d.id),
            description = ("%s · %s%s"):format(T("display_kind_" .. d.kind), table.concat(types, ", "), d.vehicle and (" · " .. d.vehicle.label) or ""),
            icon = "square-parking",
            args = { id = d.id },
        }
    end
    U.menu(T("admin_displays"), options, function(args)
        if args.action == "add" then
            local rows = {
                { type = "input", label = T("admin_display_label"), max = 64 },
                { type = "select", label = T("admin_display_kind"), options = {
                    { label = T("display_kind_stock"), value = "stock" },
                    { label = T("display_kind_showcase"), value = "showcase" },
                }, default = shop.type == "npc" and "showcase" or "stock", description = T("admin_display_kind_desc") },
                { type = "checkbox", label = T("admin_display_turntable") },
            }
            for _, r in ipairs(typeRows(Config.display.defaultTypes)) do
                rows[#rows + 1] = r
            end
            local res = U.input(T("admin_display_add"), rows)
            if res then
                local created = rpc("admin.display.create", { shopId = shopId, display = {
                    coords = U.myPosition(), label = res[1], kind = res[2], turntable = res[3] == true, types = typesFromResult(res, 3),
                } })
                if created then
                    U.notify(T("admin_display_added"), "success")
                end
            end
            openDisplays(shopId)
        else
            openDisplay(shopId, args.id)
        end
    end, function()
        openShop(shopId)
    end)
end

openShop = function(shopId)
    local shop = rpc("admin.shop.get", { shopId = shopId })
    if not shop then
        return
    end
    local cur = shop.settings.currency
    local options = {
        {
            label = ("%s · %s"):format(shop.label, T("shoptype_" .. shop.type)),
            description = T("admin_shop_summary", shop.job or "-", shop.ownerName or "-", U.money(shop.balance, cur), shop.counts.total or 0),
            icon = "store", disabled = true,
        },
        { label = T("admin_edit_shop"), icon = "pen", args = { action = "base" } },
        { label = T("admin_choose_owner"), description = T("admin_choose_owner_desc"), icon = "user-tie", args = { action = "owner" } },
        { label = T("admin_points"), icon = "location-dot", args = { action = "points" } },
        { label = T("admin_displays"), description = T("menu_count", #shop.displays), icon = "square-parking", args = { action = "displays" } },
        { label = T("admin_settings"), icon = "sliders", args = { action = "settings" } },
        { label = T("admin_catalog_filter"), description = T("catalog_mode_" .. (shop.catalog.mode or "all")), icon = "filter", args = { action = "filter" } },
        { label = T("admin_balance"), icon = "building-columns", args = { action = "balance" } },
        { label = T("admin_delete_shop"), description = T("admin_delete_shop_desc"), icon = "trash", args = { action = "delete" } },
    }
    U.menu(shop.label, options, function(args)
        local a = args.action
        if a == "base" then
            local input = editBase(shop)
            if input and rpc("admin.shop.update", { shopId = shop.id, shop = input }) then
                U.notify(T("saved"), "success")
            end
            openShop(shop.id)
        elseif a == "owner" then
            chooseOwner(shop)
        elseif a == "points" then
            local opts = {}
            for _, key in ipairs({ "manage", "npc", "handover", "dropoff" }) do
                opts[#opts + 1] = {
                    label = T("point_key_" .. key),
                    description = shop.points[key] and T("admin_point_set") or T("admin_point_missing"),
                    icon = shop.points[key] and "circle-check" or "circle",
                    args = { key = key },
                }
            end
            U.menu(T("admin_points"), opts, function(p)
                setPoint(shop, p.key)
            end, function()
                openShop(shop.id)
            end)
        elseif a == "displays" then
            openDisplays(shop.id)
        elseif a == "settings" then
            editSettings(shop)
            openShop(shop.id)
        elseif a == "filter" then
            editCatalogFilter(shop)
            openShop(shop.id)
        elseif a == "balance" then
            local res = U.input(T("admin_balance"), { { type = "number", label = T("admin_balance_amount"), description = T("admin_balance_desc"), required = true } })
            if res then
                rpc("admin.shop.balance", { shopId = shop.id, amount = tonumber(res[1]) })
            end
            openShop(shop.id)
        elseif a == "delete" then
            if U.confirm(T("admin_delete_shop"), T("admin_delete_shop_desc")) then
                local res = rpc("admin.shop.delete", { shopId = shop.id })
                if res then
                    U.notify(res.deleted and T("admin_shop_deleted") or T("admin_shop_deactivated"), "success")
                end
                openShops()
            end
        end
    end, function()
        openShops()
    end)
end

openShops = function()
    local list = rpc("admin.overview")
    if not list then
        return
    end
    local options = {
        { label = T("admin_new_shop"), description = T("admin_new_shop_desc"), icon = "plus", args = { action = "new" } },
    }
    for _, s in ipairs(list) do
        options[#options + 1] = {
            label = s.label,
            description = T("admin_shop_row", T("shoptype_" .. s.type), s.job or "-", s.displays, s.counts.total or 0, s.active and "" or T("admin_inactive")),
            icon = "store",
            args = { id = s.id },
        }
    end
    U.menu(T("admin_shops"), options, function(args)
        if args.action == "new" then
            local input = editBase(nil)
            if input then
                local shop = rpc("admin.shop.create", { shop = input })
                if shop then
                    U.notify(T("admin_shop_created"), "success")
                    openShop(shop.id)
                    return
                end
            end
            openShops()
        else
            openShop(args.id)
        end
    end, function()
        VS.openAdminMenu()
    end)
end

-- Catalog -----------------------------------------------------------------------------------

local function editEntry(entry)
    local res = U.input(entry and entry.label or T("admin_catalog_add"), {
        { type = "input", label = T("catalog_model"), default = entry and entry.model or "", required = true, disabled = entry ~= nil },
        { type = "input", label = T("catalog_label"), default = entry and entry.label or "", required = true },
        { type = "input", label = T("catalog_brand"), default = entry and entry.brand or "" },
        { type = "select", label = T("catalog_category"), options = categoryOptions(), default = entry and entry.category or "other", required = true },
        { type = "select", label = T("catalog_type"), options = typeOptions(), default = entry and entry.vtype or "car", required = true },
        { type = "number", label = T("catalog_price"), default = entry and entry.price or 10000, min = 0, required = true },
        { type = "number", label = T("catalog_minutes"), default = entry and entry.minutes or 0, min = 0, description = T("catalog_minutes_desc") },
        { type = "checkbox", label = T("catalog_enabled"), checked = entry == nil or entry.enabled },
    })
    if not res then
        return
    end
    local model = entry and entry.model or res[1]
    if rpc("admin.catalog.save", { entry = { model = model, label = res[2], brand = res[3], category = res[4], vtype = res[5], price = res[6], minutes = res[7], enabled = res[8] == true } }) then
        U.notify(T("saved"), "success")
    end
end

openCatalog = function()
    local list = rpc("admin.catalog.list")
    if not list then
        return
    end
    local byCategory = {}
    for _, e in ipairs(list) do
        byCategory[e.category] = byCategory[e.category] or {}
        table.insert(byCategory[e.category], e)
    end
    local options = {
        { label = T("admin_catalog_add"), icon = "plus", args = { action = "add" } },
        { label = T("admin_catalog_import"), description = T("admin_catalog_import_desc"), icon = "file-import", args = { action = "import" } },
    }
    for _, cat in ipairs(Config.categories) do
        if byCategory[cat] then
            options[#options + 1] = { label = T("category_" .. cat), description = T("menu_count", #byCategory[cat]), icon = "folder", args = { category = cat } }
        end
    end
    U.menu(T("admin_catalog"), options, function(args)
        if args.action == "add" then
            editEntry(nil)
            openCatalog()
        elseif args.action == "import" then
            local res = rpc("admin.catalog.import")
            if res then
                U.notify(T("admin_catalog_imported", res.added), "success")
            end
            openCatalog()
        else
            local function list2()
                local opts = {}
                for _, e in ipairs(byCategory[args.category]) do
                    opts[#opts + 1] = {
                        label = ("%s (%s)"):format(e.label, e.model),
                        description = ("%s · %s%s"):format(U.money(e.price), T("vtype_" .. e.vtype), e.enabled and "" or (" · " .. T("catalog_disabled"))),
                        icon = e.blocked and "ban" or "car",
                        args = { model = e.model },
                    }
                end
                U.menu(T("category_" .. args.category), opts, function(a)
                    for _, e in ipairs(byCategory[args.category]) do
                        if e.model == a.model then
                            local o = {
                                { label = T("admin_catalog_edit"), icon = "pen", args = { action = "edit" } },
                                { label = T("admin_catalog_delete"), icon = "trash", args = { action = "delete" } },
                            }
                            U.menu(e.label, o, function(x)
                                if x.action == "edit" then
                                    editEntry(e)
                                elseif U.confirm(T("admin_catalog_delete"), T("admin_catalog_delete_text", e.label)) then
                                    rpc("admin.catalog.delete", { model = e.model })
                                end
                                openCatalog()
                            end, list2)
                        end
                    end
                end, openCatalog)
            end
            list2()
        end
    end, function()
        VS.openAdminMenu()
    end)
end

-- Delivery points ---------------------------------------------------------------------------

openPoint = function(pointId)
    local list = rpc("admin.points.list")
    if not list then
        return
    end
    local p
    for _, x in ipairs(list) do
        if x.id == pointId then
            p = x
        end
    end
    if not p then
        openPoints()
        return
    end
    local function save(changes)
        changes.id = p.id
        if rpc("admin.points.save", { point = changes }) then
            U.notify(T("saved"), "success")
        end
    end
    local options = {
        { label = p.label, description = T("admin_point_summary", #p.spawns, #p.waterSpawns, #p.airSpawns), icon = "warehouse", disabled = true },
        { label = T("admin_point_edit"), icon = "pen", args = { action = "edit" } },
        { label = T("admin_point_interact_here"), icon = "location-crosshairs", args = { action = "interact" } },
        { label = T("admin_spawn_add_land"), description = T("admin_spawn_add_desc"), icon = "car", args = { action = "spawn", list = "spawns" } },
        { label = T("admin_spawn_add_water"), description = T("admin_spawn_add_desc"), icon = "ship", args = { action = "spawn", list = "waterSpawns" } },
        { label = T("admin_spawn_add_air"), description = T("admin_spawn_add_desc"), icon = "plane", args = { action = "spawn", list = "airSpawns" } },
        { label = T("admin_spawn_clear"), icon = "eraser", args = { action = "clear" } },
        { label = T("admin_point_goto"), icon = "route", args = { action = "goto" } },
        { label = T("admin_point_delete"), icon = "trash", args = { action = "delete" } },
    }
    U.menu(p.label, options, function(args)
        local a = args.action
        if a == "edit" then
            local rows = {
                { type = "input", label = T("admin_point_label"), default = p.label, required = true },
                { type = "input", label = T("admin_point_npc"), default = p.npc or "" },
                { type = "checkbox", label = T("admin_point_enabled"), checked = p.enabled },
            }
            for _, r in ipairs(typeRows(p.types)) do
                rows[#rows + 1] = r
            end
            local res = U.input(T("admin_point_edit"), rows)
            if res then
                save({ label = res[1], npc = res[2], enabled = res[3] == true, types = typesFromResult(res, 3) })
            end
        elseif a == "interact" then
            save({ interact = U.myPosition() })
        elseif a == "spawn" then
            local listCopy = {}
            for _, s in ipairs(p[args.list] or {}) do
                listCopy[#listCopy + 1] = s
            end
            listCopy[#listCopy + 1] = U.myPosition()
            save({ [args.list] = listCopy })
        elseif a == "clear" then
            if U.confirm(T("admin_spawn_clear"), T("admin_spawn_clear_text")) then
                save({ spawns = {}, waterSpawns = {}, airSpawns = {} })
            end
        elseif a == "goto" and p.interact then
            SetNewWaypoint(p.interact.x + 0.0, p.interact.y + 0.0)
        elseif a == "delete" then
            if U.confirm(T("admin_point_delete"), T("admin_point_delete_text")) then
                rpc("admin.points.delete", { pointId = p.id })
                openPoints()
                return
            end
        end
        openPoint(pointId)
    end, function()
        openPoints()
    end)
end

openPoints = function()
    local list = rpc("admin.points.list")
    if not list then
        return
    end
    local options = {
        { label = T("admin_point_add"), description = T("admin_point_add_desc"), icon = "plus", args = { action = "add" } },
    }
    for _, p in ipairs(list) do
        options[#options + 1] = { label = p.label, description = p.enabled and p.id or (p.id .. " · " .. T("admin_inactive")), icon = "warehouse", args = { id = p.id } }
    end
    U.menu(T("admin_points_delivery"), options, function(args)
        if args.action == "add" then
            local res = U.input(T("admin_point_add"), {
                { type = "input", label = T("admin_point_id"), required = true, description = T("admin_point_id_desc") },
                { type = "input", label = T("admin_point_label"), required = true },
            })
            if res and rpc("admin.points.save", { point = { id = res[1], label = res[2], interact = U.myPosition() } }) then
                openPoint(tostring(res[1]):lower():gsub("[^%w_%-]", ""))
                return
            end
            openPoints()
        else
            openPoint(args.id)
        end
    end, function()
        VS.openAdminMenu()
    end)
end

-- Main --------------------------------------------------------------------------------------

function VS.openAdminMenu()
    U.menu(T("admin_title"), {
        { label = T("admin_shops"), description = T("admin_shops_desc"), icon = "store", args = { action = "shops" } },
        { label = T("admin_catalog"), description = T("admin_catalog_desc"), icon = "book-open", args = { action = "catalog" } },
        { label = T("admin_points_delivery"), description = T("admin_points_delivery_desc"), icon = "warehouse", args = { action = "points" } },
        { label = T("admin_position"), description = T("admin_position_desc"), icon = "location-crosshairs", args = { action = "position" } },
    }, function(args)
        if args.action == "shops" then
            openShops()
        elseif args.action == "catalog" then
            openCatalog()
        elseif args.action == "points" then
            openPoints()
        elseif args.action == "position" then
            local p = U.myPosition()
            local text = ("vector4(%.2f, %.2f, %.2f, %.1f)"):format(p.x, p.y, p.z, p.w)
            print(text)
            U.notify(T("admin_position_printed", text), "info", 10000)
        end
    end)
end

if Config.adminCommand then
    RegisterCommand(Config.adminCommand, function()
        VS.refreshMe()
        if not VS.me.isAdmin then
            U.notify(T("err_no_permission"), "error")
            return
        end
        VS.openAdminMenu()
    end, false)
end
