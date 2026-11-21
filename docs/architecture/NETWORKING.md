# Netzwerk und Nachrichten

Alle Nachrichten sind Text, Felder mit `|` getrennt. Transport: Steam Networking Messages
(zuverlässig) über die DLL. Es gibt drei Ebenen:

1. **DLL-Befehle** (Lua → DLL, `Diagnostic.NetCommand`) und **DLL-Ereignisse** (DLL → Lua,
   `Diagnostic.NetPoll`).
2. **Spieler-Nachrichten** zwischen Gast und Host (in DLL `send`/`msg`). Gäste reden nur mit
   dem Host; der Host verteilt (Stern, ADR-002).
3. **sync-Zeilen** zwischen `sync.lua`/`replay.lua`/`rides.lua` und `session.lua` (im Spiel, kein Netz).

Jede neue Nachricht muss hier eingetragen werden; `tools/check_docs.py` vergleicht diese
Datei mit dem Code. Sicherheitsregel: keine Nachricht wird als Code ausgeführt; Felder werden
geprüft (`clean`, `cleanText`, `validGid`, `validRideKey`, `Figure.ParseLook` …).

## Gast → Host

| Nachricht | Felder | Zweck | Funktion |
|---|---|---|---|
| `hello` | name, baseline, mode, version, game, dlc, mods | Anmelden; mode = lobby/needpark/loaded/live | FEAT-025, FEAT-029 |
| `up` | Teil-Zustand (13+ Felder) | Szenerie-Teil neu/geändert | FEAT-060 |
| `del` | gid, … | Szenerie-Teil gelöscht | FEAT-060 |
| `cmd` | Batch | abgespielte Editor-Aufrufe | FEAT-065 |
| `ride` | key, Datei | Bahn als Bauplan-Datei | FEAT-072 |
| `base` | Anzahl | Baseline nach dem Laden | FEAT-030 |
| `pres` | Kamera, Blickpunkt, Aktivität, Fokus | Anwesenheit (mehrmals pro Sekunde) | FEAT-090–099 |
| `hold` | label, gids, items | Objekt in der Hand (leer = losgelassen) | FEAT-062 |
| `ping` | x, y, z, gid (leer oder Teil-Id, seit 2.0.0) | Ping | FEAT-095 |
| `who` | gid | Urheber erfragen | FEAT-098 |
| `time` | paused, index | Pause/Tempo | FEAT-078 |
| `board` | add/set/del … | Brett ändern | FEAT-130–135 |
| `comp-rate` | id, ziel, design, technik | Wettbewerb bewerten | FEAT-147 |
| `take-ask` | sid | Übernahme anfragen | FEAT-137 |
| `ride-invite` | key, name | Testfahrt-Einladung | FEAT-138 |
| `vote-answer` | id, 0/1 | Abstimmung | FEAT-141 |
| `emote` | kind | Emote | FEAT-168 |
| `rate` | key, sterne, name, text | Bewertung | FEAT-167 |
| `buy` | shop-gid, item-index | Kauf | FEAT-169 |
| `look` | Aussehen (Figure.LookText) | Aussehen der Figur | FEAT-162 |
| `chat` | text | Chat | FEAT-035 |
| `info` | dlc, mods | Inhalte für den Vergleich | FEAT-037 |
| `desync` | grund | nicht übernehmbar | FEAT-076 |
| `loadfailed` | – | Park ließ sich nicht laden | FEAT-031 |

## Host → Gast

| Nachricht | Felder | Zweck | Funktion |
|---|---|---|---|
| `stage` | lobby / park, token, name, guard | wo die Sitzung ist | FEAT-033 |
| `reject` | host-version / grund | Beitritt abgelehnt (Version) | FEAT-029 |
| `wait` / `welcome` / `denied` | farbe … | Beitrittsfreigabe | FEAT-027 |
| `park` | beschreibung | Park kommt | FEAT-030 |
| `ops` | Zeilen | geordnete Änderungen (Block) | FEAT-061, FEAT-064 |
| `roster` | spieler; statistik; konflikte; zahlen; stage; wahl | Spielerliste (alle 30 Frames), 15. Spielerfeld = Aussehen | FEAT-043, FEAT-079, FEAT-162 |
| `feed` | text | Verlaufszeile | FEAT-044 |
| `p` | sid, fokus, aktivität, kamera | Anwesenheit eines anderen | FEAT-091–099 |
| `h` | sid, label, gids, items | was ein anderer hält | FEAT-062 |
| `deny` | name, gid | dein Halten abgelehnt (gid für die Meldung am Objekt) | FEAT-062, FEAT-082 |
| `time` | paused, index | Pause/Tempo | FEAT-078 |
| `note` | x, y, z, text | Park-Meldung mit Ort | FEAT-140 |
| `pg` | sid, x, y, z, gid | Ping eines anderen (gid: Objekt zum Umranden) | FEAT-095 |
| `who` | gid, creator, last | Urheber-Antwort | FEAT-098 |
| `em` | sid, kind, [q] | Emote/Essen (q = ohne Toast) | FEAT-168, FEAT-170 |
| `sold` | ok/no, kind/grund, name, preis | Antwort auf `buy` | FEAT-169 |
| `rt` | sid, key, sterne, name, wer, text, neu | Bewertung | FEAT-167 |
| `bd` / `bd-` | Brettzeile / Löschung | Brett | FEAT-130–135 |
| `rules` | werte, label | Regeln | FEAT-142 |
| `ruledeny` | text | Regel verbietet das | FEAT-143 |
| `cp` | id, modus, phase, rest, thema, namen, wertungen | Wettbewerb | FEAT-145–147 |
| `tk` | name, label | Übernahme-Bitte | FEAT-137 |
| `iv` | name, key, bahn | Testfahrt-Einladung | FEAT-138 |
| `since` | text | seit dem letzten Besuch | FEAT-139 |
| `vote` | id, art, text … | Abstimmung | FEAT-141 |
| `content` | guard | Content Guard | FEAT-038 |
| `resync` | – | Park neu holen | FEAT-040, FEAT-041 |
| `chat` | name, farbe, text | Chat | FEAT-035 |

## Zeilen in `ops` (Host → Spiel, über `Sync.Receive`)

Der Host schickt Änderungen als `ops\n<Zeile>\n<Zeile>…`. Beim Empfänger nummeriert
`toGame` jede Zeile (`<Art>|<Folge-Nr.>|…`), `Sync.Tick` arbeitet sie in Reihenfolge ab.

| Zeile | Felder | Bedeutung |
|---|---|---|
| `U` | gid, owner, rev, res, x, y, z, qx, qy, qz, qw, scale | Teil anlegen oder setzen |
| `D` | gid, wer, rev | Teil löschen |
| `M` | gid, part, rev | eigene Änderung angenommen (rev 0 = eigenes Löschen) |
| `A` | gid, part, rev | Alias aus dem Park-Manifest nach dem Laden |
| `R` | gid, grund, wer | eigene Änderung abgelehnt (`veraltet`, `geloescht`, `fremd`, `gesperrt`, `unbekannt`); wer = wer zuletzt geändert hat oder hält (FEAT-082) |
| `Y` | alt, neu, datei | Bahn gegen Bauplan tauschen |
| `K` | batch | abgespielte Editor-Aufrufe |

Steuerzeilen ohne Nummer: `S|<name>` (Synchronisation starten), `X` (stoppen), `C|…` (Kamera setzen).

## DLL-Befehle (Lua → DLL)

| Befehl | Zweck | Funktion |
|---|---|---|
| `status` | Netzstatus | FEAT-190 |
| `host` | Lobby erstellen | FEAT-020 |
| `join` | Lobby beitreten | FEAT-025 |
| `leave` | Lobby verlassen | FEAT-042 |
| `send` | Nachricht an einen Spieler | FEAT-190 |
| `all` | Nachricht an alle | FEAT-190 |
| `file` | Datei senden | FEAT-191 |
| `del` | Bahn-Datei löschen | FEAT-199 |
| `kv` | Wert merken | FEAT-193 |
| `note-read` / `note-write` / `note-append` | Notizdatei | FEAT-192 |
| `friends` | Freundesliste | FEAT-024 |
| `invite` | Steam-Overlay-Einladung | FEAT-023 |
| `invite_user` | Freund einladen | FEAT-023 |
| `avatar` | Profilbild holen | FEAT-036 |
| `mods` | Mod-Ordner | FEAT-037 |
| `visitor` | Tasten/Maus im Besucher-Modus | FEAT-195 |
| `now` | Echtzeit | FEAT-197 |

## DLL-Ereignisse (DLL → Lua)

| Ereignis | Funktion |
|---|---|
| `net:ready`, `net:error`, `net:refused`, `net:peer-stalled` | FEAT-190, FEAT-040 |
| `lobby:created`, `lobby:entered`, `lobby:left`, `lobby:join-failed`, `lobby:error` | FEAT-020, FEAT-025 |
| `member:join`, `member:leave` | FEAT-027 |
| `msg` | FEAT-190 |
| `invite:accepted` (Einladung im Steam-Overlay angenommen), `invite:sent`, `invite:failed` (Antwort auf `invite_user`) | FEAT-023, FEAT-025 |
| `friends:begin`, `friend`, `friends:end` | FEAT-024 |
| `avatar`, `mods` | FEAT-036, FEAT-037 |
| `file:queued`, `file:sending`, `file:progress`, `file:sent`, `file:done`, `file:error` | FEAT-191 |
| `note:data`, `note:end`, `note:error` | FEAT-192 |
| `kv` | FEAT-193 |
| `key:v`, `mouse` | FEAT-195 |
| `key:mdown`, `key:mup`, `key:menu`, `key:dev`, `key:chat` | FEAT-196 (`key:dev` nur mit Dev-Flag) |
| `key:ping` | nur noch Lua-Zweig, DLL sendet es nicht mehr (FEAT-095) |
| `now` | FEAT-197 |

## sync-Zeilen (sync.lua → session.lua, `sync:<art>|…`)

| Zeile | Bedeutung |
|---|---|
| `ready`, `started`, `stopped`, `not-ready`, `baseline` | Zustand der Synchronisation |
| `hooks-installed`, `hook-error` | Editor-Hooks installiert / Fehler darin (FEAT-060) |
| `pres` | eigene Anwesenheit (Kamera, Blickpunkt; nicht im Log) (FEAT-090) |
| `up`, `del` | lokaler Teil-Endzustand (FEAT-060) |
| `cmd` | lokaler Replay-Batch (FEAT-065) |
| `ride`, `ridedel` | Bahn-Bauplan fertig / Datei löschen (FEAT-072) |
| `hold`, `hold-denied`, `hold-lost` | Halten (FEAT-062, FEAT-080); `hold-denied` mit Name und gid, `hold-lost` mit wer und gid (FEAT-082) |
| `applied`, `apply-error`, `read-error`, `run-split`, `preview-resumed`, `commit-refused` | Anwenden fremder Änderungen |
| `desync` | nicht übernehmbar (FEAT-076) |
| `rejected` | beim Host abgelehnt, mit gid, Grund und wer (FEAT-075, FEAT-082) |
| `undo-blocked` | Rückgängig gesperrt (FEAT-074) |
| `unsupported` | nicht synchronisiertes Werkzeug (FEAT-077) |

## Werte innerhalb von Nachrichten

| Feld | Werte |
|---|---|
| Emote-Art (`emote`, `em`) | `wave`, `cheer`, `laugh`, `up`, `down`, `sick`; beim Kaufen zusätzlich `eat`, `drink` |
| Brett-Art (`board`, `bd`) | `task`, `area`, `proposal`, `comment`, `meet` |
| Abstimmungs-Art (`vote`) | `restore` (Sicherungspunkt zurückholen) |
| Ablehnungsgrund (`R`) | `veraltet`, `geloescht`, `fremd`, `gesperrt`, `unbekannt` |
| Beitritts-Modus (`hello`) | `lobby`, `needpark`, `loaded`, `live` |

## Sitzungs-Logzeilen (`session:<art>`)

`session:init`, `net-ready`, `lobby`, `lobby-created`, `member`, `hosting`, `joining`,
`joined`, `join-request`, `join-confirm`, `join-refused`, `join-failed`, `join-cancelled`, `awaiting-park`,
`loading-park`, `park-sent`, `park-note`, `peer-stalled`, `rejected-version`,
`content-refused`, `ride-refused`, `resync`, `host-gone`, `host-in-menu`, `feed`, `error`,
`task-error`, `park-retry` (Park kam nicht, neu angefragt), `rate-limited` (ein Mitspieler über
dem Limit einer Nachrichtenart) – Diagnose im Log
(FEAT-216), werden von QA-Werkzeugen als erwartete Zeilen benutzt.

## Schutz gegen Fluten und kaputte Werte (seit 2.0.0)

Der Host nimmt je Mitspieler und Art höchstens so viele Nachrichten pro Zeitfenster an
(`Session.RATE_LIMITS`, Frames bei 60 fps): `chat` 8/5 s, `board` 20/5 s, `ride-invite`
2/10 s, `rate` 10/10 s, `time` 10/5 s, `who` 30/1 s, `take-ask` 6/5 s. Was darüber liegt, wird
verworfen (einmal `session:rate-limited|<sid>|<art>` im Log). Der Host selbst ist nicht
begrenzt. Zahlen für Orte und Winkel (`pres`, `ping`, `pg`, Replay-Vektoren) müssen endlich und
höchstens 1e6 (Replay 1e7) groß sein. Bauplan-Dateien (`pc2coop-ride-<id>-<n>.blueprint`) nimmt
der Host nur mit der Steam-Id des Absenders an, höchstens 400 je Spieler und Spielstart (DLL).
Sicherheits- und Stabilitätsübersicht: `docs/architecture/SECURITY.md`.
