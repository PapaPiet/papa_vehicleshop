--- Kunden: Fahrzeug am Ausstellungsplatz ansehen und kaufen, finanzieren, Probefahrt, NPC-Katalog,
--- eigene Bestellungen und Finanzierungen, Personal rufen, Angebote des Personals annehmen.

VS = VS or {}

local U = VS.U

local function shopOf(d)
    return d and VS.shop(d.shopId) or nil
end

local function conditionText(condition)
    if type(condition) ~= "table" then
        return T("condition_unknown")
    end
    local engine = math.floor((tonumber(condition.engine) or 1000) / 10)
    local body = math.floor((tonumber(condition.body) or 1000) / 10)
    return T("condition_text", engine, body, tonumber(condition.fuel) or 0)
end

--- Shows the finance plan and asks for confirmation. Returns true when accepted.
local function confirmFinance(shop, price)
    local plan = U.call("financePlan", shop.id, price)
    if not plan then
        return false
    end
    local cur = shop.currency
    return U.confirm(T("finance_title"), T("finance_plan_text",
        U.money(plan.price, cur), U.money(plan.downPayment, cur), plan.installments, U.money(plan.rate, cur),
        U.minutes(plan.intervalMinutes), U.money(plan.interest, cur), U.money(plan.total + plan.downPayment, cur)))
end

local function deliveredText(res)
    if res.ordered then
        return T("bought_ordered", res.label, U.minutes(res.minutes))
    end
    if res.delivered == "handover" then
        return T("bought_handover", res.label, res.plate)
    end
    return T("bought_garage", res.label, res.plate)
end

--- Asks for an optional wish plate (only new vehicles). Returns plate or "" or nil (cancelled).
local function askPlate()
    local cfg = Config.purchase.customPlate
    if not cfg or not cfg.enabled then
        return ""
    end
    local res = U.input(T("plate_title"), {
        { type = "input", label = T("plate_label", U.money(cfg.price)), description = T("plate_hint", cfg.minLength, cfg.maxLength), required = false, max = cfg.maxLength },
    })
    if not res then
        return nil
    end
    return res[1] or ""
end

-- Display -----------------------------------------------------------------------------------

local function buy(d, finance)
    local shop = shopOf(d)
    if not shop then
        return
    end
    local item = d.vehicle or d.showcase
    local price = item.price
    if finance and not confirmFinance(shop, price) then
        return
    end
    local payWith = U.choosePayment(nil, finance and T("menu_down_payment") or T("menu_payment"))
    if not payWith then
        return
    end
    local plate = ""
    if d.showcase then
        plate = askPlate()
        if plate == nil then
            return
        end
    end
    if not finance and not U.confirm(T("buy_confirm_title"), T("buy_confirm_text", item.label, U.money(price, shop.currency), T("method_" .. payWith))) then
        return
    end
    local res = U.call("buyDisplay", d.id, { method = finance and "finance" or payWith, payWith = payWith, plate = plate })
    if res then
        U.notify(deliveredText(res), "success", 9000)
    end
end

local function testDrive(d)
    local shop = shopOf(d)
    if not shop then
        return
    end
    local payWith = "bank"
    if shop.testDrive then
        payWith = U.choosePayment(nil, T("menu_testdrive_deposit"))
        if not payWith then
            return
        end
    end
    local info = U.call("testDrive", d.id, payWith)
    if info then
        VS.startTestDrive(info)
    end
end

function VS.openDisplayMenu(displayId)
    local d = VS.world.displays[displayId]
    local shop = shopOf(d)
    if not d or not shop then
        return
    end
    local item = d.vehicle or d.showcase
    if not item then
        return
    end
    local cur = shop.currency
    local options = {}
    local title = ("%s %s"):format(item.brand or "", item.label):gsub("^%s+", "")
    if d.vehicle then
        local v = d.vehicle
        options[#options + 1] = { label = T("menu_price", U.money(v.price, cur)), description = T("menu_vehicle_info", v.plate or "-", conditionText(v.condition)), icon = "tag", disabled = true }
        if v.note and v.note ~= "" then
            options[#options + 1] = { label = v.note, icon = "note-sticky", disabled = true }
        end
        if v.status == "testdrive" then
            options[#options + 1] = { label = T("menu_on_testdrive"), icon = "road", disabled = true }
        else
            options[#options + 1] = { label = T("menu_buy"), description = T("menu_buy_desc"), icon = "cart-shopping", args = { action = "buy" }, disabled = v.price <= 0 }
            if shop.finance then
                options[#options + 1] = { label = T("menu_finance"), description = T("menu_finance_desc"), icon = "percent", args = { action = "finance" } }
            end
            if shop.testDrive then
                options[#options + 1] = { label = T("menu_testdrive"), description = T("menu_testdrive_desc"), icon = "road", args = { action = "testdrive" } }
            end
        end
    else
        local c = d.showcase
        options[#options + 1] = {
            label = T("menu_price", U.money(c.price, cur)),
            description = c.minutes and c.minutes > 0 and T("menu_delivery_time", U.minutes(c.minutes)) or T("menu_immediate"),
            icon = "tag", disabled = true,
        }
        if c.available then
            options[#options + 1] = { label = T("menu_buy_new"), description = T("menu_buy_new_desc"), icon = "cart-shopping", args = { action = "buy" } }
            if shop.finance then
                options[#options + 1] = { label = T("menu_finance"), description = T("menu_finance_desc"), icon = "percent", args = { action = "finance" } }
            end
        else
            options[#options + 1] = { label = T("menu_ask_staff"), icon = "user-tie", disabled = true }
        end
        if shop.testDrive then
            options[#options + 1] = { label = T("menu_testdrive"), description = T("menu_testdrive_desc"), icon = "road", args = { action = "testdrive" } }
        end
    end
    if shop.type ~= "npc" then
        options[#options + 1] = { label = T("menu_call_staff"), description = T("menu_call_staff_desc"), icon = "bell", args = { action = "call" } }
    end
    if VS.can(shop.id, "displayManage") then
        options[#options + 1] = { label = T("target_manage_spot"), icon = "screwdriver-wrench", args = { action = "manage" } }
    end
    U.menu(title, options, function(args)
        if args.action == "buy" then
            buy(d, false)
        elseif args.action == "finance" then
            buy(d, true)
        elseif args.action == "testdrive" then
            testDrive(d)
        elseif args.action == "call" then
            if U.call("callStaff", shop.id) then
                U.notify(T("staff_called"), "success")
            end
        elseif args.action == "manage" then
            VS.openDisplayStaffMenu(d.id)
        end
    end)
end

-- NPC catalog -------------------------------------------------------------------------------

local function catalogDetail(shop, data, entry, back, colorIndex)
    local cur = data.shop.currency
    local colors = {}
    local colorIds = { 0, 111, 27, 64, 55, 88, 50, 138, 4, 12 }
    for _, c in ipairs(colorIds) do
        colors[#colors + 1] = T("color_" .. c)
    end
    local options = {
        { label = T("menu_price", U.money(entry.price, cur)), description = entry.minutes > 0 and T("menu_delivery_time", U.minutes(entry.minutes)) or T("menu_immediate"), icon = "tag", disabled = true },
        { label = T("menu_color"), description = T("menu_color_desc"), icon = "palette", values = colors, defaultIndex = colorIndex or 1, args = { action = "color" } },
        { label = T("menu_buy_new"), icon = "cart-shopping", args = { action = "buy" } },
    }
    if data.shop.finance then
        options[#options + 1] = { label = T("menu_finance"), description = T("menu_finance_desc"), icon = "percent", args = { action = "finance" } }
    end
    local chosenColor = colorIds[colorIndex or 1] or colorIds[1]
    U.menu(entry.label, options, function(args, scrollIndex)
        if args.action == "color" then
            U.notify(T("color_chosen", colors[scrollIndex or 1] or ""), "info", 2500)
            catalogDetail(shop, data, entry, back, scrollIndex or 1)
            return
        end
        local finance = args.action == "finance"
        if finance and not confirmFinance({ id = shop.id, currency = cur }, entry.price) then
            return
        end
        local payWith = U.choosePayment(data.methods, finance and T("menu_down_payment") or T("menu_payment"))
        if not payWith then
            return
        end
        local plate = askPlate()
        if plate == nil then
            return
        end
        if not finance and not U.confirm(T("buy_confirm_title"), T("buy_confirm_text", entry.label, U.money(entry.price, cur), T("method_" .. payWith))) then
            return
        end
        local res = U.call("buyCatalog", shop.id, entry.model, { method = finance and "finance" or payWith, payWith = payWith, plate = plate, color = chosenColor })
        if res then
            U.notify(deliveredText(res), "success", 9000)
        end
    end, back)
end

local function openCatalog(shop)
    local data = U.call("npcCatalog", shop.id)
    if not data then
        return
    end
    local byCategory = {}
    for _, v in ipairs(data.vehicles) do
        byCategory[v.category] = byCategory[v.category] or {}
        table.insert(byCategory[v.category], v)
    end
    local function showCategories()
        local options = {}
        for _, cat in ipairs(Config.categories) do
            local list = byCategory[cat]
            if list and #list > 0 then
                options[#options + 1] = { label = T("category_" .. cat), description = T("menu_count", #list), icon = "folder", args = { category = cat } }
            end
        end
        U.menu(T("menu_catalog", data.shop.label), options, function(args)
            local function showList()
                local opts = {}
                for _, v in ipairs(byCategory[args.category]) do
                    opts[#opts + 1] = {
                        label = v.label,
                        description = ("%s · %s%s"):format(v.brand ~= "" and v.brand or T("vtype_" .. v.vtype), U.money(v.price, data.shop.currency),
                            v.minutes > 0 and (" · " .. U.minutes(v.minutes)) or ""),
                        icon = "car",
                        args = { model = v.model },
                    }
                end
                U.menu(T("category_" .. args.category), opts, function(a)
                    for _, v in ipairs(byCategory[args.category]) do
                        if v.model == a.model then
                            catalogDetail(shop, data, v, showList)
                        end
                    end
                end, showCategories)
            end
            showList()
        end)
    end
    showCategories()
end

-- My orders and finances --------------------------------------------------------------------

local function openOrders(shopId)
    local list = U.call("myOrders")
    if not list then
        return
    end
    local options = {}
    for _, o in ipairs(list) do
        local ready = o.status == "ready"
        options[#options + 1] = {
            label = ("%s · %s"):format(o.label, o.shopLabel),
            description = ready and T("order_ready") or T("order_transit"),
            icon = ready and "circle-check" or "truck",
            disabled = not ready or o.shopId ~= shopId,
            args = { id = o.id },
        }
    end
    U.menu(T("menu_my_orders"), options, function(args)
        local res = U.call("collectOrder", args.id)
        if res then
            U.notify(deliveredText(res), "success", 9000)
        end
    end)
end

local function openFinances()
    local list = U.call("myFinances")
    if not list then
        return
    end
    local options = {}
    for _, f in ipairs(list) do
        options[#options + 1] = {
            label = ("%s · %s"):format(f.label or "-", f.plate or ""),
            description = T("finance_row", U.money(f.remaining), f.ratesLeft, U.money(f.rate), f.missed),
            icon = f.status == "defaulted" and "triangle-exclamation" or "percent",
            args = { id = f.id, remaining = f.remaining, label = f.label },
        }
    end
    U.menu(T("menu_my_finances"), options, function(args)
        if not U.confirm(T("finance_payoff_title"), T("finance_payoff_text", args.label or "", U.money(args.remaining))) then
            return
        end
        local payWith = U.choosePayment(nil)
        if not payWith then
            return
        end
        if U.call("payOff", args.id, payWith) then
            U.notify(T("finance_paid_off"), "success")
        end
    end)
end

function VS.openCustomerMenu(shopId)
    local shop = VS.shop(shopId)
    if not shop then
        return
    end
    local options = {}
    if shop.npcActive then
        options[#options + 1] = { label = T("menu_open_catalog"), description = T("menu_open_catalog_desc"), icon = "book-open", args = { action = "catalog" } }
    elseif shop.type ~= "npc" then
        options[#options + 1] = { label = T("menu_call_staff"), description = T("menu_call_staff_desc"), icon = "bell", args = { action = "call" } }
    end
    options[#options + 1] = { label = T("menu_my_orders"), icon = "box", args = { action = "orders" } }
    options[#options + 1] = { label = T("menu_my_finances"), icon = "percent", args = { action = "finances" } }
    if shop.tradeIn and shop.points.dropoff then
        options[#options + 1] = { label = T("menu_tradein_info"), description = T("menu_tradein_info_desc"), icon = "right-left", args = { action = "tradeinfo" } }
    end
    if VS.isStaff(shopId) then
        options[#options + 1] = { label = T("point_manage"), icon = "laptop", args = { action = "staff" } }
    end
    U.menu(shop.label, options, function(args)
        if args.action == "catalog" then
            openCatalog(shop)
        elseif args.action == "call" then
            if U.call("callStaff", shop.id) then
                U.notify(T("staff_called"), "success")
            end
        elseif args.action == "orders" then
            openOrders(shop.id)
        elseif args.action == "finances" then
            openFinances()
        elseif args.action == "tradeinfo" then
            local d = shop.points.dropoff
            SetNewWaypoint(d.x + 0.0, d.y + 0.0)
            U.notify(T("tradein_info"), "info", 8000)
        elseif args.action == "staff" then
            VS.openStaffMenu(shop.id)
        end
    end)
end

-- Offers from staff -------------------------------------------------------------------------

RegisterNetEvent("papa_vehicleshop:client:saleOffer", function(o)
    local cur = o.currency
    local text = T("offer_text", o.seller, o.label, o.plate or "-", U.money(o.price, cur), conditionText(o.condition))
    if o.listPrice and o.listPrice > o.price then
        text = text .. "\n" .. T("offer_discount", U.money(o.listPrice - o.price, cur))
    end
    local options = {
        { label = T("offer_header", o.shopLabel), description = text, icon = "file-signature", disabled = true },
    }
    for _, m in ipairs(o.methods) do
        options[#options + 1] = { label = T("offer_accept_" .. m), icon = m == "finance" and "percent" or "check", args = { method = m } }
    end
    options[#options + 1] = { label = T("offer_decline"), icon = "xmark", args = { method = "decline" } }
    U.menu(T("offer_title"), options, function(args)
        if args.method == "decline" then
            U.call("answerOffer", o.offerId, false)
            return
        end
        local payWith = args.method
        if args.method == "finance" then
            local f = o.finance
            if not f or not U.confirm(T("finance_title"), T("finance_plan_text",
                U.money(f.price, cur), U.money(f.downPayment, cur), f.installments, U.money(f.rate, cur),
                U.minutes(f.intervalMinutes), U.money(f.interest, cur), U.money(f.total + f.downPayment, cur))) then
                U.call("answerOffer", o.offerId, false)
                return
            end
            payWith = U.choosePayment(nil, T("menu_down_payment")) or "bank"
        end
        local res = U.call("answerOffer", o.offerId, true, args.method, payWith)
        if res and not res.declined then
            U.notify(deliveredText(res), "success", 9000)
        end
    end, function()
        U.call("answerOffer", o.offerId, false)
    end)
end)
