# Entwicklung und Tests

Werkzeuge für Entwickler und automatische Tests. Arbeitsweise: `docs/development/TESTING.md`.

### FEAT-210 – Dev-Flag und QA-Befehle
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Feste Testbefehle in der Testkopie des Spiels; nur aktiv mit
  `pc2coop-dev.flag` im Mod-Ordner (ausgelieferte Pakete enthalten die Datei nie).
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/qa.lua` (`QA.Init`, `QA.Tick`,
  `QA.IsOwnTestPark`, `QA.HookManager`, `QA.HookFrontend`, `QA.AttachLoaded`), Postfach
  `pc2coop-inbox-<pid>.txt`; `testWorld()` lehnt alles ab, was nicht der eigene Testpark
  „PC2Coop-Test“ ist (`qa:rejected:not-own-test-park`). Befehle (feste Liste):
  `bar-check`, `bar-end`, `bar-test`, `chat-test`, `coaster-probe`, `coaster-swap`,
  `commit-held-rock`, `coop-host`, `coop-invite`, `coop-leave`, `create-test-rock`,
  `delete-test-rock`, `dlc-probe`, `editor-hold-test`, `extras-test`, `flatride-test`,
  `focus-paths`, `gate-check`, `gate-test`, `ghost-sweep`, `ghost-test`, `held-delete-test`,
  `hold-test-rock`, `inspect-test-rock`, `join-dismiss`, `join-load-test`, `label-test`,
  `last-cmd`, `list-rocks`, `lobby-close`, `lobby-start-new`, `lobby-test`, `menu-lobby-close`,
  `menu-lobby-test`, `menu-test`, `move-test-rock`, `park-list-probe`, `park-name`,
  `path-test`, `profile-test`, `recorder-on`, `rejoin-go`, `rejoin-test`, `reload-test-park`,
  `rename-park`, `replay-last`, `ride-count`, `ride-delete-test`, `ride-probe`,
  `ride-quickdelete-test`, `save-probe`, `save-test-park`, `scale-probe`, `stale-invite-test`,
  `sync-stats`, `terrain-height`, `terrain-stroke`, `transfer-test`, `ui-test`,
  `verify-test-rock`, `viz-clean`, `viz-probe`, `world-probe`, `inspect` (welche Welt-APIs
  da sind), `introspect` (FEAT-215), außerdem `new-test-park` und `lua` (siehe FEAT-211).
- **Besonderheiten:** Kein `eval` aus dem Netz; nur lokale Dateien mit Dev-Flag.

### FEAT-211 – Lua-Skripte in der Testkopie
- **Status:** Implemented · **Seit:** 1.6.0
- **Technik:** `tools/qa_lua.py --mod-dir … --pid … skript.lua` legt ein Lua-Skript ins
  Postfach; es läuft als Coroutine mit `yield`, `emit`, `waitFor`, `testWorld`. Ausgaben
  `qa:...` im Log. Nur mit Dev-Flag.

### FEAT-212 – Game-Bot
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `tools/game_bot.py --game-dir <Testkopie> "<schritt>:<erwartete Logzeile>"`
  startet die Testkopie, schickt feste Befehle, wartet auf Logzeilen. `tools/qa_step.py`,
  `tools/qa_command.py` für einzelne Befehle; `tools/e2e_real_game.py` (Ende-zu-Ende mit
  simulierten Spielern, ältere Python-Brücke).

### FEAT-213 – Watchdog und Screenshots
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** `tools/game_watchdog.ps1 -ProcessId … -Log …` beendet die Testkopie bei zu viel
  Speicher oder hängendem Fenster (der PC des Eigners fror einmal ein); `tools/screenshot_game.ps1`
  (PrintWindow, keine Eingaben); `tools/game_input.ps1`, `tools/dismiss_driver_dialog.ps1`.
- **Besonderheiten:** Tests nie, während der Eigner sein eigenes Spiel offen hat; vorher freien
  Platz auf C: prüfen (voll = Absturz 0xFDEAD). Siehe `docs/development/TESTING.md`.

### FEAT-214 – API-Rekorder
- **Status:** Implemented · **Seit:** 1.6.0
- **Funktion:** Schreibt verändernde Editor-Aufrufe mit Argumenten ins Log, um neue Werkzeuge
  synchronisieren zu lernen.
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/recorder.lua` (`Recorder.Install`,
  `Recorder.SetEnabled`, `Recorder.Mark`); F8-Menü „API-Rekorder an/aus“.

### FEAT-215 – API-Introspektion
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/introspect.lua` (`Introspect.Run`): listet
  Namen und Typen der Spiel-APIs, ruft nichts Veränderndes auf.

### FEAT-216 – Diagnose-Log
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** `Win64\ovldata\PC2CoopProbe\pc2coop-diagnostic-<pid>.log` mit Ereignissen der
  Mod (`[PC2CoopSession] …`, `[PC2CoopSync] …`, `js|…`).
- **Technik:** `Diagnostic.Write` (`diagnostic.lua`) → DLL. Enthält Steam-Namen und -IDs.
  Seit 2.1.0 zweite Zeile `system|windows=…|ram-gb=…|cpus=…|game=…|steam-build=…|mods=…`
  (`native/report.cpp`), dazu FEAT-222. Höchstens 4 MB pro Spielstart.

### FEAT-222 – Fehler mit Fundstelle, Schnappschuss, Absturz-Notiz
- **Status:** Implemented · **Seit:** 2.1.0
- **Funktion:** Damit ein Log reicht, um einen Fehler zu finden: Fehler der Mod mit Datei, Zeile
  und Aufrufweg; alle 30 s eine Zeile zum Stand der Sitzung; die letzten 200 Netz-Ereignisse
  (nur Art und Größe) beim ersten Fehler und im Bericht; ein Sitzungscode, der bei Host und
  Gästen gleich ist; schwere Ausnahmen des Spiels (Zugriffsfehler, Stapelüberlauf …) vor dem
  Absturz.
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/guard.lua`: `Guard.Call` (xpcall mit
  `debug.traceback`) schreibt `error|<wo>|x<n>|<Stapel>` beim 1., 10., 100. und jedem 1000. Mal,
  höchstens 100 Arten; `Guard.Report` für Coroutinen (`Session._TaskError`). Benutzt in
  `Manager.Advance` (`managers/pc2coopqa.lua`: qa, live, sync, session, ui, presence), in
  `Frontend.Tick` und für jedes DLL-Ereignis in `Session.Tick`. `Session._Snapshot` →
  `session:snap|role=…|players=…|stage=…|context=…|conflicts=…|lang=…|faults=…|code=…|frame=…|acts=…`;
  `Session._Remember` (ein- und ausgehend, gleiche Folgen als `x<n>`), `Session._DumpRing` →
  `session:recent|<Grund>|…`; `Session._Code` (sechs Zeichen aus der Lobby-Id) →
  `session:code|…`. DLL (`native/diagnostic.cpp`): Vectored Exception Handler, höchstens
  8 Zeilen `exception|code=…|in=game+0x…|thread=…|first-chance …` je Spielstart, ohne zu
  warten (TryAcquire), Adressen relativ zu Spiel-EXE oder DLL.
- **Besonderheiten:** „first-chance“: Das Spiel kann eine solche Ausnahme noch selbst
  behandeln; erst die letzte Zeile vor dem Ende des Logs zählt. Der Befehlskanal schreibt
  `net-stage:command` nur noch dreimal. Tests: `tests/test_diagnosis_lua.py`,
  `tools/verify_native.py`.

### FEAT-223 – Problembericht
- **Status:** Implemented · **Seit:** 2.1.0 · **Hängt ab von:** FEAT-216, FEAT-222
- **Funktion:** „Problembericht erstellen“ legt die neuesten drei Logs dieses PCs als eine Datei
  auf den Desktop (`PC2Coop-Bericht-<Datum>-<Zeit>.txt`, englisch `PC2Coop-report-…`). Steam-IDs, Lobby-IDs, die Namen der Mitspieler und der
  Windows-Benutzername sind ersetzt (P0 = wer den Bericht erstellt, P1 … = die anderen,
  L1 … = Lobbys). Oben stehen Version, Windows und die auffälligen Zeilen. Nichts wird
  verschickt.
- **Technik:** UI-Aktion `report` → `Session.Report` (Ringpuffer und Fehlerliste ins Log, dann
  DLL-Befehl `report|<lang>|<Ordner>|<Version>|<sid>=<Name>|…`) → `native/report.cpp`
  (`pc2_write_report`; lange Logs: Anfang 256 KB und Ende 1,25 MB) → Ereignis `report:done|<Datei>`
  oder `report:error|logs|desktop|write` → `Session._ReportResult`; `Session.ReportState` im
  UI-Zustand `report`. Ohne Steam wartet `Session._ReportWait` trotzdem auf die Antwort,
  nach 15 s „Keine Antwort von der Mod-DLL.“. Einen eigenen Ordner gibt es nur mit Dev-Flag
  (QA). Auswerten: `tools/read_report.py`.
- **UI:** Im Park: Multiplayer → Einstellungen → „Für dich“; im Hauptmenü unten auf der Seite
  „Multiplayer“. Knopf des Spiels, darunter der Stand („Auf dem Desktop gespeichert:“ und der
  Dateiname in einer eigenen Zeile; daneben war im schmalen Fenster kein Platz).
- **Besonderheiten:** Der Desktop-Ordner wird nicht geöffnet (das Spiel bleibt im Vordergrund).
  Kein Chat im Log; Bewertungs-Kommentare können darin stehen. Tests:
  `tests/test_diagnosis_lua.py`, `tools/verify_native.py`, `tests/test_read_report.py`.

### FEAT-217 – LAN-Alpha im Spiel
- **Status:** Legacy · **Seit:** vor 1.4.1
- **Technik:** `probe/PC2CoopProbe/Main/pc2coop/live.lua` (`Live.Init`, `Live.Enqueue`,
  `Live.Tick`), schmale Szenerie-Synchronisation der frühen Alpha; nur noch von QA benutzt.

### FEAT-218 – Python-Forschungswerkzeuge
- **Status:** Legacy · **Seit:** vor 1.4.1
- **Technik:** `pc2coop/alpha.py` (LAN/VPN-Replikation), `pc2coop/coop.py` (Host/Client mit
  Browser-UI `pc2coop/coop_ui.py`), `pc2coop/doctor.py` (Steam/Spiel prüfen),
  `pc2coop/model.py`, `pc2coop/leases.py`, `pc2coop/social.py`; `tools/package_alpha.py`.
  Tests `tests/test_alpha.py` u. a. Werden nicht ausgeliefert.
- **Besonderheiten:** Nicht erweitern. Bei Gelegenheit mit FEAT-010 entfernen (eigene Entscheidung, ADR).

### FEAT-219 – Build-Pipeline
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `tools/build_ui.py` (UI-Paket `pc2coopui.ppuipkg` in den Mod-Ordner),
  `tools/build_native.py` (DLL mit MSVC + `version.rc`), `tools/build_probe.py` +
  `tools/cobra_worker.py` (OVL mit Cobra Tools, Lua-Rundlauf-Prüfung), Build-Reports mit
  SHA-256 unter `build/`. `tools/verify_native.py` führt DLL-Exporte in einem Kindprozess aus.

### FEAT-220 – Automatische Tests
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `tests/` – Lua-Module laufen unter `lupa` (Lua 5.3) gegen nachgebaute
  Spiel-APIs; mehrere Spieler werden als eigene Lua-Laufzeiten simuliert
  (`tests/test_session_lua.py` `Peer`, `pump`). Aufruf siehe `docs/development/TESTING.md`.

### FEAT-221 – Dokumentations-Prüfung
- **Status:** Implemented · **Seit:** 1.13.0
- **Funktion:** Prüft, dass Dokumentation und Code zusammenpassen.
- **Technik:** `tools/check_docs.py`; läuft als Test `tests/test_docs.py`.
