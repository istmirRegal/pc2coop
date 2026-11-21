# Code-Struktur

Wo was liegt. Zeilenzahlen grob (Stand 1.13.0), um die Größe einzuschätzen.

## Repository

| Pfad | Inhalt |
|---|---|
| `probe/PC2CoopProbe/` | die Mod (wird zur OVL gebaut): `Manifest.xml`, `.ovlpaths`, `Main/`, `ui/` |
| `probe/PC2CoopProbe/Main/database/pc2coopprobeluadatabase.lua` | ACSE-Einstieg: Manager, Hooks, `LuaDB.Init`, Mod-Version (`VERSION`) |
| `probe/PC2CoopProbe/Main/managers/pc2coopqa.lua` | Park-Manager `Managers.PC2CoopQA`: Init und Frame-Schleife |
| `probe/PC2CoopProbe/Main/pc2coop/` | alle Lua-Module (Tabelle unten) |
| `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js` | gesamte Oberfläche (Preact, ~2500 Zeilen) |
| `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/Texts.js` | englische Texte (`createTranslator`), geladen, wenn das Spiel nicht Deutsch läuft (ADR-022) |
| `probe/PC2CoopProbe/ui/UIGameface/js/common/debug/DebugToolImports.js` | ersetzt das gleichnamige Spielmodul, startet `CoopLayer.js`, Namensschild-Stil |
| `native/` | DLL-Quellen: `steam_net.cpp` (Steam, Dateien, Tasten), `diagnostic.cpp` (Log, Exporte), `string_probe.cpp`, `version.rc` |
| `alpha-dist/` | was in den Paketen landet: `INSTALL.cmd`, `UPDATE.cmd`, `UNINSTALL.cmd`, `install.ps1`, `update.ps1`, `LIESMICH.txt` (+ Legacy `START.cmd`, `start.ps1`) |
| `tools/` | Build, Pakete, QA (siehe unten) |
| `tests/` | Unit-Tests (Python + `lupa`), `tests/native/test_outbox.cpp` |
| `pc2coop/` | Legacy-Python (FEAT-218), nicht ausgeliefert |
| `profiles/` | bekannte Spielbuilds (`steam-26255360.json` …) für FEAT-009 |
| `docs/` | diese Dokumentation (Einstieg `docs/README.md`) |
| `release.json` | Repository für den Updater |
| `CLAUDE.md`, `README.md`, `LICENSE` | KI-Einstieg, Projekt-Readme, MIT |

## Lua-Module (`probe/PC2CoopProbe/Main/pc2coop/`)

| Datei | Zeilen | Aufgabe | Wichtige Funktionen |
|---|---|---|---|
| `session.lua` | 2540 | Sitzung: Lobby, Beitritt, Rollen, Host-Autorität, alle Spieler-Nachrichten, Team, Besuch-Netz | `Session.Init`, `Session.Tick`, `Session.OnSyncLine`, `Session.Host`, `Session.JoinFriend`, `Session.Answer`, `Session.View`, `Session.Leave`, `Session.Resync`, `Session.BuyPick`, `Session.Rate`, `Session.Emote` |
| `sync.lua` | 980 | Szenerie-Sync, Halten, Undo-Sperre, Anwenden fremder Teile | `Sync.Init`, `Sync.Tick`, `Sync.Receive`, `Sync.LocalPart`, `Sync.GidToEntity`, `Sync.EntityToGid`, `Sync.SetRemoteLocks`, `Sync.MayUndo`, `Handlers.BeforeCommit`, `Handlers.AfterCommit`, `Handlers.AfterUndo` |
| `replay.lua` | 725 | Whitelist-Replay von Editor-Aufrufen (Gelände, Wege, Stempel, Seen, Löschen) | `Replay.Install`, `Replay.OnPreview`, `Replay.OnCommit`, `Replay.OnCancel`, `Replay.Apply`, `Replay.Split`, `Replay.Remap` |
| `rides.lua` | 430 | Bahnen als Bauplan-Dateien | `Rides.Install`, `Rides.Tick`, `Rides.Apply`, `Rides.Editing`, `Rides.ValidKey`, `Rides.ValidFile`, `Rides.FileReady` |
| `capture.lua` | 120 | Hooks am Szenerie-Editor (`api.undo.CommitPreview` ummantelt) | `Capture.Install`, `Capture.InstallSelect` |
| `visitor.lua` | 660 | Besucher-Modus: Kamera, Figur, Steuerung, Ich-Sicht, Eingänge, Läden, Mitfahren | `Visitor.Start`, `Visitor.Stop`, `Visitor.Tick`, `Visitor.OnKey`, `Visitor.OnMouse`, `Visitor.ToggleView`, `Visitor.Interact`, `Visitor.Hint`, `Visitor.Shop`, `Visitor.Pick`, `Visitor.Ate`, `Visitor.Ride`, `Visitor.Rides` |
| `figure.lua` | 330 | animierte Gast-Figur (`api.entity.CompilePrefab`), Aussehen | `Figure.New`, `Figure.OwnLook`, `Figure.FromAvatar`, `Figure.LookText`, `Figure.ParseLook`, `Figure.Gait`, `Figure.Available` |
| `shop.lua` | 130 | Läden lesen und Geld buchen | `Shop.InFront`, `Shop.Items`, `Shop.Price`, `Shop.IsOpen`, `Shop.Credit`, `Shop.Kind` |
| `viz.lua` | 410 | Darstellung der Mitspieler im Park (Marker, Sichtkegel, Geister, Färbung, Figuren) | `Viz.Init`, `Viz.Update`, `Viz.Clear`, `Viz.SetEnabled` |
| `labels.lua` | 100 | Namensschilder über die Coaster-Labels des Spiels | `Labels.Init`, `Labels.Show`, `Labels.Pin`, `Labels.Clear` |
| `lang.lua` | 40 | Sprache für Schilder, die Lua zeichnet (ADR-022) | `Lang.Set`, `Lang.Code`, `Lang.World` |
| `ui.lua` | 540 | Zustand für die Oberfläche (DataStore `pc2coop`), Aktionen aus `Request` | `Ui.Init`, `Ui.Tick`, `Ui.Toggle`, `Ui.SetOpen`, `Ui._Request` |
| `world.lua` | 290 | Spiel-Zugriffe: Kamera, Zeit, Zahlen, HUD-/Meldungs-Hooks, DLC | `World.HookHUD`, `World.HookNotifications`, `World.Camera`, `World.SetCamera`, `World.FocusPoint`, `World.Time`, `World.SetTime`, `World.Numbers`, `World.RequiredDLC`, `World.LeaveTool` |
| `board.lua` | 160 | Brett-Daten (Gebiete, Aufgaben, Kommentare, Treffpunkte, Vorschläge) | `Board.Add`, `Board.Set`, `Board.Remove`, `Board.Apply`, `Board.Lines`, `Board.Tally` |
| `menu.lua` | 190 | F8-Entwicklerdialog (Spiel-Dialog) | `Menu.Init`, `Menu.Toggle`, `Menu.FranchiseInfo` |
| `frontend.lua` | 50 | Sitzung im Hauptmenü ohne Park | `Frontend.Tick`, `Frontend.Session`, `Frontend.Shutdown` |
| `parks.lua` | 60 | Parkliste, Park laden/neu | `Parks.List`, `Parks.Load`, `Parks.New` |
| `diagnostic.lua` | 80 | DLL laden, Log, Netz-Befehle | `Diagnostic.Init`, `Diagnostic.Write`, `Diagnostic.NetCommand`, `Diagnostic.NetPoll`, `Diagnostic.HasNet` |
| `shared.lua` | 13 | gemeinsame Tabelle über Modul-Instanzen (`api.ui2.__pc2coopShared`) | – |
| `qa.lua` | 1370 | QA-Befehle, Testpark-Schutz, Lua-Postfach (nur Dev-Flag) | `QA.Init`, `QA.Tick`, `QA.IsOwnTestPark`, `QA.HookManager`, `QA.HookFrontend` |
| `recorder.lua` | 110 | API-Rekorder | `Recorder.Install`, `Recorder.SetEnabled`, `Recorder.Mark` |
| `introspect.lua` | 100 | API-Namen auflisten | `Introspect.Run` |
| `live.lua` | 130 | Legacy-LAN-Alpha | `Live.Init`, `Live.Tick`, `Live.Enqueue` |
| `stringprobe.lua` | 36 | String-Probe beim Start | `Probe.Run` |

## Werkzeuge (`tools/`)

| Datei | Zweck |
|---|---|
| `tools/build_ui.py` | UI-Paket bauen |
| `tools/build_native.py` | DLL bauen (MSVC, Versionskopf, `version.rc`) |
| `tools/build_probe.py`, `tools/cobra_worker.py` | Mod-OVL mit Cobra Tools bauen und prüfen |
| `tools/verify_native.py` | DLL-Exporte prüfen |
| `tools/package_release.py` | Release-Zip und Nexus-Zip (`--nexus`) |
| `tools/game_bot.py`, `tools/qa_step.py`, `tools/qa_command.py`, `tools/qa_lua.py` | Testkopie steuern |
| `tools/e2e_real_game.py` | Ende-zu-Ende mit Python-Brücke (Legacy) |
| `tools/game_watchdog.ps1`, `tools/screenshot_game.ps1`, `tools/game_input.ps1`, `tools/dismiss_driver_dialog.ps1` | Testkopie überwachen, Bilder, Eingaben |
| `tools/scan_exe.py` | Spiel-EXE nach Strings durchsuchen (Forschung) |
| `tools/package_alpha.py` | Legacy-Alpha-Paket |
| `tools/check_docs.py` | Doku ↔ Code prüfen (FEAT-221) |

## Tests (`tests/`)

| Datei | prüft |
|---|---|
| `tests/test_session_lua.py` | Sitzung mit mehreren simulierten Spielern |
| `tests/test_join_security_lua.py` | Beitritt, Freigabe, Ablehnung |
| `tests/test_sync_lua.py`, `tests/test_editor_sync_lua.py`, `tests/test_capture_lua.py` | Szenerie-Sync, Replay, Erfassung |
| `tests/test_rides_lua.py` | Bahnen |
| `tests/test_visitor_lua.py`, `tests/test_figure_lua.py`, `tests/test_shop_lua.py` | Besucher-Modus |
| `tests/test_presence_extras_lua.py`, `tests/test_coop_play_lua.py` | Anwesenheit, Team-Funktionen |
| `tests/test_ui_lua.py` | Oberflächen-Zustand und Aktionen |
| `tests/test_texts_js.py`, `tests/test_lang_lua.py` | englische Texte (Node) und Schilder in Lua (ADR-022) |
| `tests/test_fuzz_session_lua.py` | Fuzzing der Sitzung über ein gestörtes Netz, bösartige Nachrichten (`SECURITY.md`) |
| `tests/test_viz_lua.py` | Markierungen verdecken nichts (Umriss, Punktring) |
| `tests/test_parks_lua.py`, `tests/test_diagnostic_lua.py`, `tests/test_probe_lua.py`, `tests/test_qa_lua.py`, `tests/test_live_lua.py` | übrige Module, Version, QA |
| `tests/test_native_outbox.py` | DLL-Warteschlange (C++) |
| `tests/test_alpha.py`, `tests/test_coop.py`, `tests/test_collaboration.py`, `tests/test_doctor.py`, `tests/test_model.py` | Legacy-Python |
| `tests/test_docs.py` | Dokumentation (FEAT-221) |
