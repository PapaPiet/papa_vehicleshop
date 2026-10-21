--- Personal-Menü ohne Papa OS (Terminal im Autohaus oder Befehl): Bestand, Ausstellung, Bestellungen,
--- Lieferungen, Transportaufträge, Verkauf an Kunden, Ankauf, Finanzierungen, Konto.
--- Nutzt dieselbe RPC-Schnittstelle wie das Papa-OS-Dashboard, alle Rechte prüft der Server.

VS = VS or {}

local U = VS.U

local function rpc(shopId, action, payload)
    payload = payload or {}
    payload.shopId = shopId
    return U.rpc(action, payload)
end

local function statusText(s)
    return T("status_" .. tostring(s))
end

local function timeLeft(eta)
    local left = math.floor((eta - GetCloudTimeAsInt() * 1000) / 60000)
    if left <= 0 then
        return T("time_soon")
    end
    return U.minutes(left)
end

-- Stock -------------------------------------------------------------------------------------

local openStock, openVehicle

local function chooseDisplay(shopId, v, back)
    local list = rpc(shopId, "displays.list")
    if not list then
        return
    end
    local options = {}
    for _, d in ipairs(list) do
        if d.kind == "stock" then
            local allowed = VS.typeAllowed(d.types, v.vtype)
            options[#options + 1] = {
                label = d.label ~= "" and d.label or T("display_number", d.id),
                description = d.vehicle and T("display_taken", d.vehicle.label) or (allowed and T("display_free") or T("display_wrong_type")),
                icon = "square-parking",
                disabled = d.vehicle ~= nil or not allowed,
                args = { displayId = d.id },
            }
        end
    end
    U.menu(T("menu_choose_display"), options, function(args)
        if rpc(shopId, "stock.display", { stockId = v.id, displayId = args.displayId }) then
            U.notify(T("stock_displayed", v.label), "success")
        end
    end, back)
end

local function chooseNearbyPlayer(shopId, title)
    local list = rpc(shopId, "players.nearby")
    if not list then
        return nil
    end
    local options = {}
    for _, p in ipairs(list) do
        options[#options + 1] = { label = p.name, description = T("player_distance", p.distance), icon = "user", args = { src = p.src } }
    end
    local pr = promise.new()
    U.menu(title, options, function(args)
        pr:resolve(args.src)
    end, function()
        pr:resolve(nil)
    end)
    return Citizen.Await(pr)
end

local function sellToCustomer(shopId, v)
    local target = chooseNearbyPlayer(shopId, T("menu_choose_customer"))
    if not target then
        return
    end
    local res = U.input(T("sell_title", v.label), {
        { type = "number", label = T("sell_price"), default = v.price, min = 1, required = true },
        { type = "checkbox", label = T("sell_allow_finance"), checked = true },
    })
    if not res then
        return
    end
    local sent = rpc(shopId, "sell.offer", { offer = { stockId = v.id, targetSrc = target, price = tonumber(res[1]), allowFinance = res[2] == true } })
    if sent then
        U.notify(T("offer_sent", sent.customer), "success")
    end
end

openVehicle = function(shopId, id, back)
    local v = rpc(shopId, "stock.get", { stockId = id })
    if not v then
        return
    end
    local cur = (VS.shop(shopId) or {}).currency
    local options = {
        { label = ("%s · %s"):format(v.label, v.plate or "-"), description = T("stock_info", statusText(v.status), U.money(v.price, cur), v.damage), icon = "car", disabled = true },
    }
    local function add(cond, label, action, icon, desc)
        if cond then
            options[#options + 1] = { label = label, description = desc, icon = icon, args = { action = action } }
        end
    end
    local canManage = VS.can(shopId, "stockManage")
    add(VS.can(shopId, "priceEdit") and v.status ~= "transit", T("action_price"), "price", "tag")
    add(VS.can(shopId, "displayManage") and v.status == "storage", T("action_display"), "display", "square-parking")
    add(VS.can(shopId, "displayManage") and v.status == "display", T("action_undisplay"), "undisplay", "warehouse")
    add(VS.can(shopId, "sell") and (v.status == "storage" or v.status == "display"), T("action_sell"), "sell", "handshake")
    add(VS.can(shopId, "sell") and (v.status == "storage" or v.status == "display"), v.reservedFor and T("action_unreserve") or T("action_reserve"), "reserve", "bookmark")
    add(canManage and v.status == "storage", T("action_takeout"), "takeout", "key", T("action_takeout_desc"))
    add(canManage and (v.status == "out" or v.status == "pickup"), T("action_recall"), "recall", "rotate-left", T("action_recall_desc"))
    add(VS.can(shopId, "contracts") and v.status == "waiting" and not v.contract, T("action_contract"), "contract", "truck-fast")
    add(VS.can(shopId, "order") and v.status == "transit", T("action_cancel_order"), "cancel", "ban")
    add(v.status == "waiting" and v.deliveryLabel ~= nil, T("action_route_pickup", v.deliveryLabel or ""), "route", "route")
    local flags = VS.me.byShop and VS.me.byShop[shopId] and VS.me.byShop[shopId].flags or {}
    add(flags.boss and (v.status == "storage" or v.status == "display" or v.status == "out"), T("action_release"), "release", "right-from-bracket", T("action_release_desc"))
    add(flags.boss and (v.status == "storage" or v.status == "display" or v.status == "out"), T("action_scrap"), "scrap", "trash")
    local reopen = function()
        openVehicle(shopId, id, back)
    end
    U.menu(v.label, options, function(args)
        local a = args.action
        if a == "price" then
            local res = U.input(T("action_price"), {
                { type = "number", label = T("sell_price"), default = v.price, min = 0, required = true },
                { type = "input", label = T("stock_note"), default = v.note or "", required = false, max = 255 },
            })
            if res and rpc(shopId, "stock.price", { stockId = v.id, price = tonumber(res[1]), note = res[2] }) then
                U.notify(T("saved"), "success")
            end
            reopen()
        elseif a == "display" then
            chooseDisplay(shopId, v, reopen)
        elseif a == "undisplay" then
            if rpc(shopId, "stock.undisplay", { stockId = v.id }) then
                U.notify(T("stock_undisplayed"), "success")
            end
        elseif a == "sell" then
            sellToCustomer(shopId, v)
        elseif a == "reserve" then
            if v.reservedFor then
                rpc(shopId, "stock.reserve", { stockId = v.id })
            else
                local target = chooseNearbyPlayer(shopId, T("menu_choose_customer"))
                if target then
                    rpc(shopId, "stock.reserve", { stockId = v.id, targetSrc = target })
                end
            end
            reopen()
        elseif a == "takeout" then
            VS.takeOut(shopId, v.id)
        elseif a == "recall" then
            if U.confirm(T("action_recall"), T("action_recall_desc")) and rpc(shopId, "stock.recall", { stockId = v.id }) then
                U.notify(T("saved"), "success")
            end
        elseif a == "contract" then
            local suggestion = rpc(shopId, "contracts.suggest", { stockId = v.id })
            local res = U.input(T("action_contract"), {
                { type = "number", label = T("contract_reward"), default = suggestion and suggestion.reward or 500, min = 1, required = true },
                { type = "input", label = T("contract_note"), required = false, max = 255 },
            })
            if res and rpc(shopId, "contracts.create", { stockId = v.id, reward = tonumber(res[1]), note = res[2] }) then
                U.notify(T("contract_created"), "success")
            end
        elseif a == "cancel" then
            if U.confirm(T("action_cancel_order"), T("cancel_order_text")) then
                local res = rpc(shopId, "stock.cancelOrder", { stockId = v.id })
                if res then
                    U.notify(T("order_cancelled", U.money(res.refund, cur)), "success")
                end
            end
        elseif a == "route" then
            for _, p in ipairs(VS.world.points) do
                if p.id == v.deliveryPoint and p.interact then
                    SetNewWaypoint(p.interact.x + 0.0, p.interact.y + 0.0)
                end
            end
        elseif a == "release" or a == "scrap" then
            if U.confirm(a == "scrap" and T("action_scrap") or T("action_release"), a == "scrap" and T("scrap_text") or T("action_release_desc")) then
                if rpc(shopId, "stock.remove", { stockId = v.id, mode = a }) then
                    U.notify(T("saved"), "success")
                end
            end
        end
    end, back)
end

openStock = function(shopId, statuses, title, back)
    local list = rpc(shopId, "stock.list", { statuses = statuses })
    if not list then
        return
    end
    local cur = (VS.shop(shopId) or {}).currency
    local options = {}
    for _, v in ipairs(list) do
        local desc
        if v.status == "transit" then
            desc = T("stock_row_transit", v.deliveryLabel or "-", timeLeft(v.eta))
        elseif v.status == "waiting" then
            desc = T("stock_row_waiting", v.deliveryLabel or "-", v.contract and T("status_contract_" .. v.contract.status) or "")
        else
            desc = T("stock_row", statusText(v.status), U.money(v.price, cur), v.displayLabel or "")
        end
        options[#options + 1] = { label = ("%s · %s"):format(v.label, v.plate or "-"), description = desc, icon = "car", args = { id = v.id } }
    end
    local function self()
        openStock(shopId, statuses, title, back)
    end
    U.menu(title, options, function(args)
        openVehicle(shopId, args.id, self)
    end, back)
end

-- Ordering ----------------------------------------------------------------------------------

local function orderVehicle(shopId, e, back)
    local shop = VS.shop(shopId)
    local cur = shop and shop.currency
    local pointLabels, pointIds = {}, {}
    for _, p in ipairs(VS.world.points) do
        for _, id in ipairs(e.points) do
            if p.id == id then
                pointLabels[#pointLabels + 1] = { label = p.label, value = p.id }
                pointIds[#pointIds + 1] = p.id
            end
        end
    end
    if #pointIds == 0 then
        U.notify(T("err_no_delivery_point"), "error")
        return
    end
    local res = U.input(T("order_title", e.label), {
        { type = "number", label = T("order_quantity"), default = 1, min = 1, max = 20, required = true },
        { type = "number", label = T("order_sale_price"), default = e.price, min = 0, required = true },
        { type = "select", label = T("order_point"), options = pointLabels, default = pointIds[1], required = true },
        { type = "input", label = T("order_note"), required = false, max = 255 },
    })
    if not res then
        return
    end
    local qty = tonumber(res[1]) or 1
    if not U.confirm(T("order_confirm_title"), T("order_confirm_text", qty, e.label, U.money(e.wholesale * qty, cur), U.minutes(e.minutes))) then
        return
    end
    local done = rpc(shopId, "orders.create", { order = { model = e.model, quantity = qty, price = tonumber(res[2]), deliveryPoint = res[3], note = res[4] } })
    if done then
        U.notify(T("order_done", done.count, e.label, U.money(done.total, cur)), "success", 8000)
    end
end

local function openOrder(shopId, back)
    local list = rpc(shopId, "catalog.list")
    if not list then
        return
    end
    local cur = (VS.shop(shopId) or {}).currency
    local byCategory = {}
    for _, e in ipairs(list) do
        byCategory[e.category] = byCategory[e.category] or {}
        table.insert(byCategory[e.category], e)
    end
    local function categories()
        local options = {}
        for _, cat in ipairs(Config.categories) do
            if byCategory[cat] then
                options[#options + 1] = { label = T("category_" .. cat), description = T("menu_count", #byCategory[cat]), icon = "folder", args = { category = cat } }
            end
        end
        U.menu(T("menu_order"), options, function(args)
            local function models()
                local opts = {}
                for _, e in ipairs(byCategory[args.category]) do
                    opts[#opts + 1] = {
                        label = e.label,
                        description = T("order_row", U.money(e.wholesale, cur), U.money(e.price, cur), U.minutes(e.minutes)),
                        icon = "car",
                        args = { model = e.model },
                    }
                end
                U.menu(T("category_" .. args.category), opts, function(a)
                    for _, e in ipairs(byCategory[args.category]) do
                        if e.model == a.model then
                            orderVehicle(shopId, e, models)
                        end
                    end
                end, categories)
            end
            models()
        end, back)
    end
    categories()
end

-- Contracts, trade-ins, finance, account ----------------------------------------------------

local function openContracts(shopId, back)
    local list = rpc(shopId, "contracts.list")
    if not list then
        return
    end
    local options = {}
    for _, c in ipairs(list) do
        options[#options + 1] = {
            label = T("contract_row", c.vehicle and c.vehicle.label or "-", U.money(c.reward)),
            description = c.status == "taken" and T("contract_taken_by", c.takerName or "-") or T("status_contract_open"),
            icon = "truck-fast",
            disabled = c.status ~= "open",
            args = { id = c.id },
        }
    end
    U.menu(T("menu_contracts"), options, function(args)
        if U.confirm(T("contract_cancel"), T("contract_cancel_text")) and rpc(shopId, "contracts.cancel", { contractId = args.id }) then
            U.notify(T("contract_cancelled"), "success")
        end
    end, back)
end

local function openTradeIns(shopId, back)
    local list = rpc(shopId, "tradeins.list")
    if not list then
        return
    end
    local cur = (VS.shop(shopId) or {}).currency
    local options = {}
    for _, t in ipairs(list) do
        options[#options + 1] = {
            label = ("%s · %s"):format(t.label, t.sellerName or "-"),
            description = T("tradein_row", U.money(t.asking, cur), t.damage, t.suggestion and U.money(t.suggestion, cur) or "-"),
            icon = "right-left",
            disabled = t.status ~= "open",
            args = { id = t.id, suggestion = t.suggestion, asking = t.asking },
        }
    end
    U.menu(T("menu_tradeins"), options, function(args)
        local res = U.input(T("tradein_make_offer"), {
            { type = "number", label = T("tradein_offer_amount"), default = args.asking > 0 and args.asking or args.suggestion, min = 0, required = true },
        })
        if not res then
            return
        end
        if (tonumber(res[1]) or 0) <= 0 then
            rpc(shopId, "tradeins.decline", { tradeId = args.id })
        elseif rpc(shopId, "tradeins.offer", { tradeId = args.id, amount = tonumber(res[1]) }) then
            U.notify(T("tradein_offer_sent"), "success")
        end
    end, back)
end

local function openFinance(shopId, back)
    local list = rpc(shopId, "finance.list")
    if not list then
        return
    end
    local options = {}
    for _, f in ipairs(list) do
        options[#options + 1] = {
            label = ("%s · %s"):format(f.label or "-", f.buyerName or "-"),
            description = T("finance_staff_row", T("finance_status_" .. f.status), U.money(f.total - f.paid), f.missed),
            icon = f.status == "defaulted" and "triangle-exclamation" or "percent",
            disabled = f.status ~= "defaulted",
            args = { id = f.id, label = f.label },
        }
    end
    U.menu(T("menu_finances"), options, function(args)
        if U.confirm(T("finance_repossess"), T("finance_repossess_text", args.label or "")) and rpc(shopId, "finance.repossess", { financeId = args.id }) then
            U.notify(T("finance_repossessed"), "success")
        end
    end, back)
end

local function openAccount(shopId, back)
    local data = rpc(shopId, "account.ledger", { limit = 15 })
    if not data then
        return
    end
    local cur = (VS.shop(shopId) or {}).currency
    local options = {
        { label = T("account_balance", U.money(data.balance, cur)), icon = "building-columns", disabled = true },
    }
    if VS.can(shopId, "accountManage") then
        options[#options + 1] = { label = T("account_deposit"), icon = "arrow-down", args = { action = "deposit" } }
        options[#options + 1] = { label = T("account_withdraw"), icon = "arrow-up", args = { action = "withdraw" } }
    end
    for _, e in ipairs(data.entries) do
        options[#options + 1] = { label = ("%s %s"):format(e.amount >= 0 and "+" or "", U.money(e.amount, cur)), description = e.text or T("ledger_" .. e.kind), icon = "receipt", disabled = true }
    end
    U.menu(T("menu_account"), options, function(args)
        local res = U.input(args.action == "deposit" and T("account_deposit") or T("account_withdraw"), {
            { type = "number", label = T("amount"), min = 1, required = true },
        })
        if res and rpc(shopId, args.action == "deposit" and "account.deposit" or "account.withdraw", { amount = tonumber(res[1]) }) then
            U.notify(T("saved"), "success")
        end
        openAccount(shopId, back)
    end, back)
end

-- Main menu ---------------------------------------------------------------------------------

function VS.openStaffMenu(shopId)
    VS.refreshMe()
    if not VS.isStaff(shopId) then
        U.notify(T("err_not_dealer"), "error")
        return
    end
    local shop = VS.shop(shopId)
    local dash = rpc(shopId, "dashboard")
    if not dash then
        return
    end
    local c = dash.counts or {}
    local cur = shop and shop.currency
    local function main()
        VS.openStaffMenu(shopId)
    end
    local options = {
        {
            label = shop and shop.label or "-",
            description = T("staff_summary", dash.balance and U.money(dash.balance, cur) or "-", c.storage or 0, c.display or 0, (c.transit or 0) + (c.waiting or 0)),
            icon = "chart-simple", disabled = true,
        },
    }
    local function add(flag, label, action, icon, desc)
        if flag == nil or VS.can(shopId, flag) then
            options[#options + 1] = { label = label, description = desc, icon = icon, args = { action = action } }
        end
    end
    add("stockView", T("menu_stock"), "stock", "warehouse", T("menu_count", (c.storage or 0) + (c.display or 0) + (c.out or 0)))
    add("order", T("menu_order"), "order", "cart-plus")
    add("stockView", T("menu_deliveries"), "deliveries", "ship", T("menu_count", (c.transit or 0) + (c.waiting or 0) + (c.pickup or 0)))
    add("contracts", T("menu_contracts"), "contracts", "truck-fast", T("menu_count", dash.contractsOpen or 0))
    add("tradeIn", T("menu_tradeins"), "tradeins", "right-left", T("menu_count", dash.tradeinsOpen or 0))
    add("finance", T("menu_finances"), "finance", "percent", dash.financeDefaulted > 0 and T("finance_defaulted_count", dash.financeDefaulted) or nil)
    add("accountView", T("menu_account"), "account", "building-columns")
    if GetResourceState("papa_os_core") == "started" then
        options[#options + 1] = { label = T("menu_os_hint"), description = T("menu_os_hint_desc"), icon = "computer", disabled = true }
    end
    U.menu(T("menu_staff_title"), options, function(args)
        local a = args.action
        if a == "stock" then
            openStock(shopId, { "storage", "display", "out", "testdrive" }, T("menu_stock"), main)
        elseif a == "order" then
            openOrder(shopId, main)
        elseif a == "deliveries" then
            openStock(shopId, { "transit", "waiting", "pickup" }, T("menu_deliveries"), main)
        elseif a == "contracts" then
            openContracts(shopId, main)
        elseif a == "tradeins" then
            openTradeIns(shopId, main)
        elseif a == "finance" then
            openFinance(shopId, main)
        elseif a == "account" then
            openAccount(shopId, main)
        end
    end)
end

--- Staff menu at a display spot (put a stock vehicle here, take it away, set the showcase model).
function VS.openDisplayStaffMenu(displayId)
    local data = U.call("displayCandidates", displayId)
    if not data then
        return
    end
    local shopId = data.shopId
    local cur = data.currency
    local options = {}
    if data.display.kind == "showcase" then
        options[#options + 1] = { label = T("showcase_set_model"), icon = "car", args = { action = "showcase" } }
    elseif data.current then
        local v = data.current
        options[#options + 1] = { label = ("%s · %s"):format(v.label, v.plate or "-"), description = U.money(v.price, cur), icon = "car", disabled = true }
        options[#options + 1] = { label = T("action_vehicle_menu"), icon = "list", args = { action = "vehicle", id = v.id } }
        options[#options + 1] = { label = T("action_undisplay"), icon = "warehouse", args = { action = "undisplay", id = v.id } }
    else
        for _, v in ipairs(data.candidates) do
            options[#options + 1] = { label = T("display_put", v.label, v.plate or "-"), description = U.money(v.price, cur), icon = "square-parking", args = { action = "put", id = v.id } }
        end
        if #data.candidates == 0 then
            options[#options + 1] = { label = T("display_no_candidates"), description = T("display_drive_on_hint"), icon = "circle-info", disabled = true }
        end
    end
    local title = data.display.label ~= "" and data.display.label or T("display_number", data.display.id)
    U.menu(title, options, function(args)
        if args.action == "put" then
            if rpc(shopId, "stock.display", { stockId = args.id, displayId = displayId }) then
                U.notify(T("saved"), "success")
            end
        elseif args.action == "undisplay" then
            if rpc(shopId, "stock.undisplay", { stockId = args.id }) then
                U.notify(T("stock_undisplayed"), "success")
            end
        elseif args.action == "vehicle" then
            openVehicle(shopId, args.id)
        elseif args.action == "showcase" then
            local list = rpc(shopId, "catalog.list")
            if not list then
                return
            end
            local opts = { { label = T("showcase_none"), icon = "xmark", args = { model = "" } } }
            for _, e in ipairs(list) do
                if VS.typeAllowed(data.display.types, e.vtype) then
                    opts[#opts + 1] = { label = e.label, description = T("category_" .. e.category), icon = "car", args = { model = e.model } }
                end
            end
            U.menu(T("showcase_set_model"), opts, function(a)
                if rpc(shopId, "displays.showcase", { displayId = displayId, model = a.model }) then
                    U.notify(T("saved"), "success")
                end
            end)
        end
    end)
end

if Config.staffCommand then
    RegisterCommand(Config.staffCommand, function()
        VS.refreshMe()
        local shops = VS.me.shops or {}
        if #shops == 0 then
            U.notify(T("err_not_dealer"), "error")
            return
        end
        if #shops == 1 then
            VS.openStaffMenu(shops[1].id)
            return
        end
        local options = {}
        for _, s in ipairs(shops) do
            options[#options + 1] = { label = s.label, icon = "store", args = { id = s.id } }
        end
        U.menu(T("menu_choose_shop"), options, function(args)
            VS.openStaffMenu(args.id)
        end)
    end, false)
end
