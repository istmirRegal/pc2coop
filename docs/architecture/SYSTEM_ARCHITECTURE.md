# Systemarchitektur

PC2Coop läuft vollständig **im Spiel** (ADR-001): Lua-Module über ACSE, eine Preact-Oberfläche
im Gameface-UI des Spiels und eine kleine DLL für Steam, Tasten und Dateien. Kein Programm
läuft daneben, kein Server, kein Port.

```
             ┌──────────────────────── Planet Coaster 2 (ein Prozess) ────────────────────────┐
             │                                                                                │
  Spieler ──►│  Gameface-UI (HTML/JS)                Lua (ACSE)                     DLL       │
  (Maus,     │  ┌───────────────────┐  DataStore   ┌──────────────────────┐ NetCmd ┌────────┐ │
  Tasten)    │  │ CoopLayer.js      │◄─'pc2coop'───┤ ui.lua               │───────►│steam_  │ │◄──► Steam
             │  │ (Leiste, Fenster, │              │ session.lua (Sitzung)│◄───────│net.cpp │ │    Networking
             │  │  Lobby, Chat)     │──Request────►│ sync/replay/rides    │ NetPoll└────────┘ │    Messages
             │  └───────────────────┘ 'n|cmd|arg'  │ visitor/figure/shop  │                   │
             │                                     │ viz/labels/world     │──► Spiel-APIs     │
             │                                     └──────────────────────┘    (api.*)        │
             └────────────────────────────────────────────────────────────────────────────────┘
```

## Schichten

| Schicht | Aufgabe | Dateien |
|---|---|---|
| Einstieg | ACSE-Datenbank meldet Manager und Hooks an | `probe/PC2CoopProbe/Main/database/pc2coopprobeluadatabase.lua`, `probe/PC2CoopProbe/Main/managers/pc2coopqa.lua` |
| Sitzung | Lobby, Beitritt, Rollen, Host-Autorität, Nachrichten, Team-Funktionen | `probe/PC2CoopProbe/Main/pc2coop/session.lua`, `board.lua`, `parks.lua` |
| Bauen | Änderungen erfassen, senden, anwenden | `capture.lua`, `sync.lua`, `replay.lua`, `rides.lua` |
| Darstellung im Park | Namensschilder, Marker, Geister, Figuren | `viz.lua`, `labels.lua`, `figure.lua` |
| Besuchen | Besucher-Modus, Läden | `visitor.lua`, `shop.lua`, `figure.lua` |
| Spiel-Oberfläche | Fenster-Zustand, Aktionen, HUD-Hooks, F8-Menü | `ui.lua`, `world.lua`, `menu.lua`, `frontend.lua` |
| Oberfläche | Darstellung in Gameface | `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js`, `probe/PC2CoopProbe/ui/UIGameface/js/common/debug/DebugToolImports.js` |
| DLL | Steam, Dateien, Tasten, Maus, Log | `native/steam_net.cpp`, `native/diagnostic.cpp`, `native/string_probe.cpp` |
| Entwicklung | QA, Rekorder, Introspektion | `qa.lua`, `recorder.lua`, `introspect.lua`, `live.lua`, `stringprobe.lua` |

(Ohne Pfad: alle unter `probe/PC2CoopProbe/Main/pc2coop/`.)

## Lebenszyklus

1. **Spielstart:** ACSE lädt `pc2coopprobeluadatabase.lua`. `LuaDB.AddLuaHooks` hängt sich an
   `Editors.Scenery.SubModeBase`/`SubModeSelect` (Erfassung, FEAT-060), `Managers.ParkLoadSaveManager`
   (QA, Laden/Speichern), `Windows.MainHUDGameface` und `Managers.NotificationManager` (`world.lua`),
   `StartScreen.Shared.SandboxMenuHUD` (Startbildschirm). `LuaDB.Init` lädt die DLL (`diagnostic.lua`).
2. **Startbildschirm:** `Frontend.Tick` (aus dem Hauptmenü-Hook) baut eine Sitzung ohne Park
   (`idleSync`): Lobby, Einladungen, Parkwahl, Wiederbeitritt (FEAT-033, FEAT-045).
3. **Im Park:** `Managers.PC2CoopQA` (`pc2coopqa.lua`) – `Manager.Init` startet sync, session,
   labels, viz, recorder, menu, ui; `Manager.Advance` ruft jeden Frame `qa.Tick`, `live.Tick`,
   `sync.Tick`, `session.Tick`, `ui.Tick` und zeichnet die anderen Spieler (Viz). Jeder Aufruf in
   `pcall`: ein Fehler stoppt nie das Spiel.
4. **Parkwechsel:** Das Spiel baut die Lua-Module neu; gemeinsamer Zustand liegt in
   `shared.lua` (an `api.ui2` gehängt) und in der DLL (`kv`, FEAT-047).

## Rollen

- **Host:** besitzt den Spielstand und die Reihenfolge (ADR-003). Jede Änderung geht zum Host,
  bekommt eine Revision und wird an alle verteilt (`ops`). Der Host prüft Urheberschaft, Halten,
  Regeln, Grabsteine (gelöschte gids) und stellt bei Konflikten den Host-Stand wieder her.
- **Gast:** lädt den Park des Hosts (Datei-Übertragung), sendet eigene Änderungen und wendet
  die des Hosts an. Gäste sprechen nie direkt miteinander.

## Wichtige Regeln (dürfen nie brechen)

1. Nichts aus dem Netz wird als Code ausgeführt (ADR-005). Nur Whitelist-Aufrufe, geprüfte Felder.
2. Ein Fehler in der Mod darf das Spiel nicht abstürzen lassen: alles in `pcall`.
3. Der Spielstand des Gastes wird nicht verändert; gespielt wird der Park des Hosts.
4. QA-Befehle laufen nur mit Dev-Flag und nur im eigenen Testpark (ADR-008).
5. Pakete enthalten kein ACSE und keine Spieldateien (ADR-009).
6. Keine Erweiterung von Einzelspieler-Funktionen; die Mod nutzt sie technisch für Multiplayer (ADR-014).

Weiter: `docs/architecture/DATA_FLOW.md` (Wege einer Änderung), `docs/architecture/NETWORKING.md`
(alle Nachrichten), `docs/architecture/CODE_STRUCTURE.md` (Dateien und Funktionen),
`docs/architecture/DEPENDENCIES.md` (wer braucht wen).
