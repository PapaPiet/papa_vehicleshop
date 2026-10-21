--- Kaufvertrag als Dokument in den Papa-OS-Dateien des Käufers (und per Mail). Nur mit papa_os_core.

VS = VS or {}
VS.Documents = VS.Documents or {}

local U = VS.U
local Doc = VS.Documents

local function row(label, value)
    return ("<tr><td style=\"padding:6px 10px;color:#666;width:40%%\">%s</td><td style=\"padding:6px 10px\"><b>%s</b></td></tr>")
        :format(U.htmlEscape(label), U.htmlEscape(value))
end

local function body(shop, sale)
    local cur = shop.settings.currency
    local rows = {
        row(T("doc_vehicle"), sale.label or "-"),
        row(T("doc_plate"), sale.plate or "-"),
        row(T("doc_model"), sale.model or "-"),
        row(T("doc_price"), U.formatMoney(sale.price, cur)),
        row(T("doc_method"), T("method_" .. tostring(sale.method))),
        row(T("doc_buyer"), sale.buyerName or "-"),
        row(T("doc_seller"), sale.sellerName or shop.label),
        row(T("doc_date"), U.formatDateTime(U.now())),
    }
    if sale.finance then
        local f = sale.finance
        rows[#rows + 1] = row(T("doc_down_payment"), U.formatMoney(f.downPayment, cur))
        rows[#rows + 1] = row(T("doc_installments"), T("doc_installments_value", f.installments, U.formatMoney(f.rate, cur), f.intervalMinutes))
        rows[#rows + 1] = row(T("doc_interest"), U.formatMoney(f.interest, cur))
    end
    return ([[<div style="font-family:Inter,Arial,sans-serif;color:#111">
<h1 style="margin:0 0 4px">%s</h1>
<div style="color:#666;margin-bottom:18px">%s · %s</div>
<table style="border-collapse:collapse;width:100%%;border:1px solid #ddd">%s</table>
<p style="margin-top:18px;color:#444">%s</p>
<p style="margin-top:28px">______________________ &nbsp;&nbsp;&nbsp; ______________________<br>%s &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; %s</p>
</div>]]):format(
        U.htmlEscape(T("doc_title")),
        U.htmlEscape(shop.label),
        U.htmlEscape(T("doc_number", sale.id or 0)),
        table.concat(rows, ""),
        U.htmlEscape(T("doc_terms")),
        U.htmlEscape(T("doc_sign_seller")),
        U.htmlEscape(T("doc_sign_buyer"))
    )
end

function Doc.contract(shop, sale, buyerId)
    if not Config.documents.enabled or not U.coreHasExport("FsCreatePrivateDocument") then
        return
    end
    local src = PAPA.Functions.getPlayerSourceByCitizenId(buyerId)
    if not src then
        return
    end
    local name = T("doc_file_name", sale.plate or tostring(sale.id or ""))
    local nodeId = U.core():FsCreatePrivateDocument(src, { name = name, bodyHtml = body(shop, sale), readOnly = true, pageCount = 1 })
    if nodeId and Config.documents.mailToBuyer and U.coreHasExport("SendMailToPlayerId") then
        U.core():SendMailToPlayerId(buyerId, T("doc_mail_subject", sale.label or "", shop.label), T("doc_mail_body", sale.label or "", sale.plate or ""), {
            systemSender = true,
            mailType = "notification",
            attachmentNodeIds = { nodeId },
        })
    end
end
