# AGENTS.md - papa_vehicleshop

Regeln für jeden KI-Agenten (Claude Code, Cursor, Codex, Windsurf, ...) in diesem Repo.
`CLAUDE.md` bindet diese Datei nur ein. Sprache: Deutsch, Code-Bezeichner: Englisch.

## 1. Zuerst das Second Brain
Piets Second Brain (MCP-Server `second-brain`) enthält die verbindlichen Regeln.
Zu Beginn jeder Sitzung:
1. `brain_context("papa_vehicleshop: <Aufgabe>")` - Kern (Profil, Prinzipien, Aktuelles). Hat Vorrang vor Annahmen.
2. `brain_rules()` - aktuelle globale Regel (`_system/Rules/GLOBAL.md`) mit Fassungsnummer. Befolgen,
   nicht in dieses Repo kopieren, immer frisch abrufen.
3. `brain_claim("papa_vehicleshop", "<woran>")` vor der Arbeit, `brain_release("papa_vehicleshop")` am Ende.
4. Nach der Arbeit: Changelog und Modulnotiz im Brain, `brain_pruefung(...)` für Piets Abnahme.
5. **Rollen:** Sagt Piet „Du bist jetzt FiveM Coder" (oder `/fivem`), sofort `brain_skill("fivem-coder")` laden und dessen Schritte ausführen
   (alle Papa-Modding-Repos holen, Regeln, `bridge.md`, `exports.MD`, `versions.json`). Weitere Rollen: GLOBAL.md, Abschnitt „Rollen".

## 2. Git-Ablauf (verbindlich, Piet 30.09.2026)
Auslieferungs-Branch dieses Repos: **`main`**. Piet pullt und mergt nie selbst.
1. Während der Arbeit immer auf einem eigenen Branch arbeiten (z. B. `claude/<thema>`, `cursor/<thema>`), nie direkt auf `main`.
2. **Nach jeder Aufgabe selbst mergen und pushen, ohne Rückfrage:**
   `git fetch origin` → `git checkout main` → `git pull --rebase origin main` →
   `git merge --no-ff <arbeits-branch>` → prüfen → `git push origin main`.
3. Erzwingt die Umgebung einen Pull Request, mergt der Agent ihn selbst. Kein PR bleibt offen liegen.
4. Selbst prüfen: `git fetch origin && git merge-base --is-ancestor HEAD origin/main`.
5. Geht der Merge nicht (Rechte, Konflikt mit fremder Logik): in der Abschlussantwort im Klartext sagen, warum, und welcher Branch offen ist.

## 3. Pflicht-Werkzeuge
- **Codegraph:** Vor jedem Lesen, Suchen oder Ändern von Code zuerst `codegraph_explore` aufrufen
  (`projectPath` = Repo-Wurzel). Grep und Datei-Lesen nur, wenn Codegraph nichts findet.
  Fehlt der Index: `codegraph init`. `.codegraph/` steht in `.gitignore`, nie committen.
- **Caveman:** Knappe Chat-Antworten (Plugin `caveman@caveman`, Stufe `full`). Keine Füllwörter, keine Einleitung.
  Commits, PR-Texte, Code-Kommentare und Doku in normaler Sprache. Agenten ohne Plugin halten den Stil von Hand ein.
- Nie das Zeichen „—" benutzen, stattdessen „-".

## 4. Regeln für FiveM-Systeme (PapaPiet / Papa Modding)

- **Niemals `pcall` verwenden.**
- **Alle Labels und Texte** gehören in die Language-Files (`locales/`) und werden dort mit `T()` geholt. Keine hartcodierten Texte.
- **Nur papa_bridge, ox_lib und oxmysql nutzen.** Niemals ein Fremdsystem (Framework, Inventory, Notify, Target, …) direkt ansteuern – 99 % läuft über die Bridge (Doku lokal: `D:\GitHub\Papa-Modding\papa_bridge\papa_bridge\bridge.md`).
  - ox_lib **nicht** für Menüs, Notifys usw. verwenden (das läuft über die Bridge).
- **Niemals Dateien zu `escrow_ignore` hinzufügen** ohne ausdrückliche Erlaubnis. So wenig Dateien wie möglich sollen einsehbar sein; Piet verwaltet die Freigabe selbst.
- **Terminal:** Bei `cd` (PowerShell) immer `-LiteralPath` verwenden.
- **`papa_os*`-Systeme:** Immer um die bestmögliche Integration in `papa_os_core` (Hauptsystem) bemühen.
- **Neue Systeme** nutzen die Boilerplate: `F:\PapaPiet\Papa Modding\papa_react_ts_boilerplate`.
- **Icons:** Heroicons verwenden, wo es passt.
- **GitBook-Doku:** Wenn passend immer ergänzen, Aufbau wie bei `papa_os_core`.
  - In der Installation steht **nie** etwas zur UI (wird von Piet persönlich gebuildet).
  - Neu erstellte Seiten für ein System sind immer **nicht einsehbar** (versteckt).
  - Jede neue Funktion, Option oder Änderung im Verhalten bekommt in der Doku direkt unter der Überschrift einen kurzen Hinweis,
    ab welcher Version sie drin ist: `*Seit Version 1.2.9.*` (bei Abhängigkeiten zusätzlich z. B. `Benötigt papa_bridge ab Version 1.6.14.`).
  - Doku-Änderungen (Change Requests) gleich selbst mergen, nicht als Entwurf liegen lassen.
- **Versionierung bei jeder Änderung** (wenn das System ein GitHub-Repo hat):
  1. Zuerst `https://github.com/PapaPiet/papa_modding/blob/main/versions.json` prüfen. Ist das Script dort mit Version hinterlegt, hat diese **Priorität**: Ist die lokale `fxmanifest.lua`-Version gleich dieser Version → letzte Ziffer um 1 erhöhen. Ist sie bereits höher → so lassen.
  2. Sonst: Version in der `fxmanifest.lua` der neuesten Version im Git (`origin/main`) prüfen. Ist sie gleich der aktuellen lokalen Version → letzte Ziffer um 1 erhöhen.
  - Immer **nur die letzte Ziffer** anpassen; die anderen Stellen macht Piet manuell bei größeren Updates.
- **Mindestversionen von Abhängigkeiten:** Nutzt eine Änderung etwas, das es erst ab einer bestimmten Version eines anderen Scripts gibt
  (z. B. eine neue Funktion in `papa_bridge` oder ein neuer Export in `papa_os_core`), trägt der Agent die Mindestversion in die `fxmanifest.lua` ein:
  `papa_requires 'papa_bridge@1.6.14'` (eine Zeile je Abhängigkeit; die Ressource steht zusätzlich in `dependencies`).
  FiveM prüft Versionen in `dependencies` nicht. Deshalb braucht das Script `server/sv_dependency_check.lua` (Vorlage: `papa_licensecreator`),
  das beim Start einen Fehler in die Server-Konsole schreibt. Fehlt die Datei, anlegen und in `server_scripts` eintragen.
  Mindestversionen nur anheben, nie senken. Im Abschlussbericht nennen, welches Script zuerst veröffentlicht werden muss.

## 5. Projekt
- FiveM-Ressource `papa_vehicleshop`: realistisches Autohaus-System (beliebig viele Autohäuser, NPC/Spieler/gemischt) mit Papa-OS-Dashboard
  und Admin-Bereich, funktioniert ohne Papa OS über papa_bridge-Menüs. Version in `fxmanifest.lua`.
- Kernidee: Jedes Fahrzeug im Bestand ist ab Ankunft ein **echtes Fahrzeug des Inhabers** im Framework (papa_bridge `addOwnedVehicle`,
  `transferVehicleOwnership`, `setOwnedVehicleGarage`, `updateOwnedVehicleProps`, ab papa_bridge 1.6.14). Ausgestellte Fahrzeuge stehen mit
  ihren gespeicherten Eigenschaften und Schäden auf dem Platz und sind direkt kaufbar.
- Ablauf: Bestellung beim Hersteller (Firmenkonto) → Ankunft am Hafen/Flugplatz nach Lieferzeit → Abholung (selbst oder Transportauftrag
  für andere Spieler) → Anlieferung im Autohaus (Lager) → Ausstellung (Preisschild mit DUI) → Verkauf (Direktkauf, Personal, NPC, Finanzierung).
- Server: `server/sv_*.lua` (Namensraum `VS`), eine RPC-Schnittstelle `papa_vehicleshop:server:rpc` für App, Admin-Panel und die Menüs
  (Menüs über ox_lib-Callback `papa_vehicleshop:rpc`). Tabellen `papa_vehicleshop_*` in `sv_db.lua` (fehlende Spalten werden ergänzt).
- Texte: `locales/translations/de.lua` (vollständig) und `en.lua`; die UI bekommt dieselben Keys über die Session.
- UI: React + TypeScript in `ui/src/` (Dashboard `main.tsx`, Admin `admin.tsx`), Build `npm run build` → `ui/dist/` (nicht committen).
  Preisschild `html/sign.html` (DUI, ohne Build). Design: Dark Mode, Blau als einziger Akzent.
- Doku: `docs/` (Aufbau, Ablauf, Konfiguration). Preisschild-Prop `papa_vehicleshop_sign` ist WIP (Bildschirmfläche in `Config.sign.screen`).
