# DLL (`PC2CoopDiagnostic.dll`)

Die DLL macht, was Lua im Spiel nicht kann: Steam (Lobby, Nachrichten, Dateien), Tasten
und Maus, Dateien im Spielordner. Lua spricht sie über `probe/PC2CoopProbe/Main/pc2coop/diagnostic.lua`
(`Diagnostic.NetCommand` = Befehl, `Diagnostic.NetPoll` = Ereignis) an. Befehle und Ereignisse:
`docs/architecture/NETWORKING.md`. Code: `native/steam_net.cpp`, `native/diagnostic.cpp`,
`native/string_probe.cpp`, `native/version.rc`.

### FEAT-190 – Steam-Lobby und Nachrichten
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Lobby erstellen/beitreten/verlassen, zuverlässige Textnachrichten an einen
  oder alle Spieler.
- **Technik:** Befehle `host`, `join`, `leave`, `send|sid|text`, `all|text`, `status`;
  Ereignisse `net:ready|sid|name`, `lobby:*`, `member:join/leave`, `msg|sid|text`,
  `net:error`, `net:refused`. Lobby: nur Freunde, höchstens 8 Spieler. Steam Networking
  Messages über die bereits geladene `steam_api64.dll` des Spiels (`GetProcAddress`).
- **Ohne Verbindung:** `Session.NetProblem` sagt warum: `dll` (DLL nicht geladen) oder `steam`
  (`net:error`, Steam-Schnittstellen nicht gebunden; dann ist `Session.Available` falsch).
  Beides gilt bis zum Neustart des Spiels; die Oberfläche nennt den Grund und was hilft, ohne
  Knopf „Erneut prüfen“ (UX-Overhaul P5).

### FEAT-191 – Dateiübertragung
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** Befehl `file|sid|name`; Ereignisse `file:queued`, `file:sending`,
  `file:progress|name|got|total`, `file:sent`, `file:done`, `file:error`. Nur feste
  Dateinamen (Park, Gelände, Bahn-Baupläne `pc2coop-ride-*.blueprint`), Größenprüfung.

### FEAT-192 – Notizdateien im Spielordner
- **Status:** Implemented · **Seit:** 1.7.0
- **Funktion:** Kleine Textdateien pro Park: Urheber, Brett, Bewertungen, Besuche, letzte Sitzung.
- **Technik:** Befehle `note-read`, `note-write`, `note-append`; Ereignisse `note:data`,
  `note:end`, `note:error`. Erlaubt sind nur `pc2coop-lastsession.txt`, `pc2coop-authors-*`,
  `pc2coop-ratings-*`, `pc2coop-board-*`, `pc2coop-visits-*` (Prüfung in `steam_net.cpp`).

### FEAT-193 – Schlüssel-Wert-Speicher
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** Befehl `kv|key|value`; Ereignis `kv|key|value` nach jedem Laden der Module (FEAT-047).

### FEAT-194 – Freunde, Einladungen, Profilbilder, Mod-Liste
- **Status:** Implemented · **Seit:** 1.8.0
- **Technik:** Befehle `friends`, `invite` (Overlay), `invite_user|sid`, `avatar|sid`, `mods`;
  Ereignisse `friends:begin`, `friend|...`, `friends:end`, `invite:accepted`, `avatar|sid|png`,
  `mods|...`. Das Profilbild kommt als unkomprimiertes PNG (gespeicherte zlib-Blöcke).

### FEAT-195 – Tasten und Maus im Besucher-Modus
- **Status:** Implemented · **Seit:** 1.12.0 (V statt G seit 1.13.0)
- **Funktion:** Tab, T, E, V, F, 1–6 als Tastenereignisse (F seit UX-Overhaul P4: Fahrgeschäfte;
  1–6 wertet Lua seit P6 nicht mehr aus); mit Maus-Look bleibt der Zeiger ausgeblendet in der
  Fenstermitte (`set_cursor_hidden`, `ShowCursor` einmal aus, einmal an), die Bewegung geht an Lua.
- **Technik:** Befehl `visitor|<tasten 0/1>|<maus 0/1>` (Erneuerung nötig, sonst Abschalten
  nach 2 s); `poll_visitor()`; Ereignisse `key:v|name|0/1`, `mouse|dx|dy`. Nur wenn das
  Spielfenster vorne ist.
- **Besonderheiten:** `GetAsyncKeyState`/`SetCursorPos` – Virenscanner-Heuristik (ADR-010).
- **Seit 2.2.0:** auch die Leertaste (`key:v|space`, Hüpfen der Figur). Der Mauszeiger wird
  über die Fensterprozedur des Spielfensters ausgeblendet (`WM_SETCURSOR`), `ShowCursor` allein
  wirkte nur im Lua-Thread. Die DLL pinnt sich beim Start und bleibt bis zum Prozessende geladen
  (Absturz beim Beenden, siehe DEVLOG 2026-11-22).

### FEAT-196 – Mittelklick, F7, F8, Enter
- **Status:** Implemented · **Seit:** 1.6.0
- **Technik:** Ereignisse `key:mdown`, `key:mup|ms|weg²` (nur im Spielfenster), `key:menu` (F7),
  `key:dev` (F8, nur mit `pc2coop-dev.flag`, `pc2_developer_mode`), `key:chat` (Enter, seit P1 des
  UX-Overhauls; ob der Chat aufgeht, entscheiden
  Lua und die Oberfläche, FEAT-116).

### FEAT-197 – Echtzeit-Uhr
- **Status:** Implemented · **Seit:** 1.12.0
- **Technik:** Befehl `now` → Ereignis `now|<GetTickCount64>`; für den Wettbewerb (FEAT-145).

### FEAT-198 – Diagnose-Kanal und String-Probe
- **Status:** Implemented · **Seit:** 1.4.1
- **Technik:** `native/diagnostic.cpp` (Log-Datei `pc2coop-diagnostic-<pid>.log`, Exporte),
  `native/string_probe.cpp` (findet die String-Routine des Spiels, FEAT-009),
  `probe/PC2CoopProbe/Main/pc2coop/stringprobe.lua` (`Probe.Run`, feste Rückgabewerte).

### FEAT-199 – Bahn-Dateien löschen
- **Status:** Implemented · **Seit:** 1.10.0
- **Technik:** Befehl `del|<name>` nur für `pc2coop-ride-<n>-<m>.blueprint` (FEAT-072).
