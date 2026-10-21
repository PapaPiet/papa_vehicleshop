# papa_vehicleshop

Realistisches Autohaus-System für FiveM. Beliebig viele Autohäuser (NPC, Spieler, gemischt), echte Fahrzeuge im Besitz des
Inhabers, Bestellungen mit Lieferzeit, Abholung am Hafen oder Flugplatz, Transportaufträge für andere Spieler, Ausstellungsplätze
mit Preisschild (DUI), Direktkauf, Probefahrt, Finanzierung, Inzahlungnahme und ein Dashboard in Papa OS. Ohne Papa OS läuft alles
über die Menüs von papa_bridge.

*Seit Version 1.0.0. Benötigt papa_bridge ab Version 1.6.14.*

## Abhängigkeiten

- `oxmysql`
- `ox_lib` (nur Callbacks und Fahrzeug-Eigenschaften, keine Menüs und keine Benachrichtigungen)
- `papa_bridge` ab 1.6.14 (neue Funktionen `getOwnedVehicle`, `setOwnedVehicleGarage`, `updateOwnedVehicleProps`, `deleteOwnedVehicle`)
- optional `papa_os_core` (Dashboard-App, Admin-Bereich, Benachrichtigungen, Kaufvertrag als Dokument und Mail)
- optional `papa_os_banking` (Firmenkonto über `Config.accountProvider = "papa_os_banking"`)
- OneSync (der Server liest Spieler- und Fahrzeugpositionen)

Die Tabellen `papa_vehicleshop_*` legt das Script beim Start selbst an.

## Autohaus-Arten

| Art | Wer verkauft | Bestand |
| --- | --- | --- |
| NPC | ein NPC am Verkäuferpunkt, Katalogmodelle auf Vorführplätzen | kein Bestand, jedes Fahrzeug wird neu angelegt |
| Spieler | Spieler mit dem Job des Autohauses | echte Fahrzeuge des Inhabers |
| Gemischt | Spieler; sind weniger als `minStaffOnline` im Dienst, verkauft der NPC zu eigenen Preisen (`mixedNpcMultiplier`) | wie Spieler, der NPC verkauft Katalogfahrzeuge, die Marge geht auf das Firmenkonto |

Ausgestellte Fahrzeuge sind immer direkt kaufbar, auch ohne Personal.

## Einrichtung (Admin)

1. Mit Papa OS: OS-Admin → **Autohäuser**. Ohne Papa OS: Befehl `/vehicleshopadmin` (Admin = ACE `papa_bridge`).
2. **Neues Autohaus**: Name, Art und Job. Danach unter *Allgemein* den **Inhaber** eintragen (Identifier / Citizen-ID oder einen Spieler online wählen).
   Ohne Inhaber können bestellte Fahrzeuge nicht ankommen, weil sie im Framework jemandem gehören müssen.
3. **Punkte** an der eigenen Position setzen (im Fahrzeug zählt die Fahrzeugposition):
   - *Verwaltung*: Terminal für das Personal (Menü ohne Papa OS)
   - *Verkäufer / Empfang*: NPC-Verkäufer, Katalog, Bestellungen abholen, Personal rufen
   - *Übergabe*: gekaufte Fahrzeuge und Probefahrten starten hier
   - *Anlieferung*: Fahrzeuge einlagern, Transportaufträge abliefern, Ankauf
4. **Ausstellungsplätze**: Fahrzeug an die gewünschte Stelle fahren, Fahrzeugtypen wählen (Auto, Motorrad, LKW, Boot, Hubschrauber,
   Flugzeug ...) und *Platz an meiner Position* anlegen. Art *Bestand* (echte Fahrzeuge) oder *Vorführplatz* (Katalogmodell des NPC).
   Preisschild an, Versatz anpassen oder *Schild an meine Position* setzen.
5. **Katalog**: global im Reiter *Fahrzeugkatalog* (Preise, Lieferzeiten, sperren). Je Autohaus im Reiter *Katalog*: alle, Whitelist oder Blacklist
   aus Modellen, Kategorien und Fahrzeugtypen. `Config.globalBlacklist` sperrt Modelle überall.
6. **Häfen und Flugplätze**: Fahrzeugausgabe und Stellplätze (Land, Wasser, Rollfeld) setzen. Beim ersten Start kommen sie aus `Config.deliveryPoints`.

## Ablauf im Spieler-Autohaus

1. **Bestellen** (Dashboard *Bestellen* oder Menü am Terminal): Einkaufspreis = Listenpreis × `wholesaleMultiplier`, bezahlt vom Firmenkonto.
2. **Lieferung**: nach der Lieferzeit (echte Minuten, ± Streuung) kommt das Fahrzeug am gewählten Hafen oder Flugplatz an.
   Ab jetzt ist es ein echtes Fahrzeug des Inhabers im Framework. Nach `freeStorageHours` kostet der Stellplatz Standgeld.
3. **Abholen**: selbst an der Fahrzeugausgabe abholen oder einen **Transportauftrag** veröffentlichen. Jeder Spieler kann ihn am Hafen,
   Flugplatz oder an einer Auftragstafel annehmen, hat `deadlineMinutes` Zeit und wird beim Abliefern bezahlt (Abzug für Schäden).
4. **Anliefern**: in die Anlieferung des Autohauses fahren, *Einlagern*. Das Fahrzeug liegt im Lager (Framework-Garage `papa_vs_<id>`),
   mit allen Eigenschaften und Schäden. Auch Fahrzeuge des Inhabers aus einer normalen Garage können so in den Bestand.
5. **Ausstellen**: im Dashboard auf einen Platz stellen oder ein Fahrzeug direkt auf einen freien Platz fahren (*Hier ausstellen*).
   Das Fahrzeug steht so da, wie es ist, auch beschädigt. Das Preisschild zeigt Preis, Zustand, Kennzeichen oder Lieferzeit.
6. **Verkaufen**:
   - Direktkauf am Fahrzeug (bar oder Überweisung), Finanzierung, Probefahrt mit Kaution
   - Verkauf durch das Personal an einen Kunden in der Nähe (Rabatt bis `maxDiscountPercent`, Provision `commissionPercent`)
   - Reservierung für einen Kunden
   Beim Kauf wechselt der Besitzer im Framework, das Fahrzeug steht am Übergabepunkt (oder in der Garage) und der Käufer bekommt
   den Kaufvertrag in seine Papa-OS-Dateien und per Mail.

## Weitere Funktionen

- **Finanzierung**: Anzahlung, Raten in festen Abständen (echte Minuten, auch offline vom Bankkonto), Zinsen, vorzeitige Ablösung.
  Nach `maxMissed` verpassten Raten darf das Autohaus das Fahrzeug zurückholen (es kommt ins Lager).
- **Inzahlungnahme / Ankauf**: Kunde bietet sein Fahrzeug an der Anlieferung an. Mit Personal: Anfrage im Dashboard, Angebot, Annahme
  im Spiel. Ohne Personal: sofortiges NPC-Angebot nach Listenpreis und Zustand.
- **Personal rufen**: Kunden rufen das Personal per Knopf, alle Mitarbeiter im Dienst bekommen eine Benachrichtigung.
- **NPC-Katalog** mit Farbwahl und Wunschkennzeichen (Aufpreis), optional mit Lieferzeit (`npcDelivery`).
- **Firmenkonto** mit Kontobuch, Ein- und Auszahlung für den Chef, Statistik (Umsatz, Rohgewinn) im Dashboard.
- **Rechte** je Dienstgrad (14 Rechte), Chef und Inhaber dürfen alles.
- **Protokoll** aller Aktionen je Autohaus.

## Befehle

| Befehl | Wer | Zweck |
| --- | --- | --- |
| `/vehicleshopadmin` | Admin | Admin-Menü ohne Papa OS (`Config.adminCommand`) |
| `/dealer` | Personal | Personal-Menü überall (`Config.staffCommand`, `nil` = nur am Terminal) |
| `debugCloseUI` | alle | Notfall: Mauszeiger freigeben, Probefahrt beenden |

## Preisschild-Prop

Das Prop `papa_vehicleshop_sign` ist noch in Arbeit. Der Bildschirm wird per DUI (`html/sign.html`) auf die Fläche
`Config.sign.screen` gezeichnet (Ecken in Prop-Koordinaten). Fehlt das Modell, steht der Bildschirm frei im Raum auf einem Pfosten.
`Config.maxActiveSigns` begrenzt die gleichzeitig aktiven Bildschirme (jeder ist ein eigener Browser).

## Technik

- Server: `server/sv_*.lua`, Namensraum `VS`. Eine RPC-Schnittstelle für Dashboard, Admin-Bereich und Menüs (`sv_rpc.lua`).
- Weltzustand (Autohäuser, Plätze, Lieferorte) wird an alle Clients verteilt (`sv_sync.lua`); Ausstellungsfahrzeuge erzeugt jeder Client
  lokal (nicht vernetzt), eingefroren und abgeschlossen.
- Gefahrene Fahrzeuge (Abholung, Probefahrt, Übergabe) sind vernetzt und bekommen Schlüssel über papa_bridge.
- Status eines Bestandsfahrzeugs: `transit` → `waiting` → `pickup` → `storage` ⇄ `display` / `testdrive` / `out` → `sold` oder `removed`.
