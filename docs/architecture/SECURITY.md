# Sicherheit und Stabilität

Stand 2.0.0 (Prüfung 2026-11-21). Was die Mod aus dem Netz annimmt, was sie damit tut, was
bei Fehlern passiert und wie das geprüft wird. Netzformat: `NETWORKING.md`, Grundsätze: ADR-003
(Host-Autorität), ADR-005 (nichts aus dem Netz wird ausgeführt).

## Wem die Mod vertraut

| Wer | darf | darf nicht |
|---|---|---|
| Steam | sagt, wer wer ist; Lobby nur für Steam-Freunde des Hosts | – |
| Host | bestimmt den Park (Datei wird geladen wie ein Workshop-Park), Reihenfolge, Regeln, Texte der Sitzung | Code ausführen, Dateien außer den festen Namen schreiben |
| Mitspieler | bauen und abreißen (gewollt; Regel „erst fragen“), chatten, markieren, bewerten | Dateien anderer überschreiben, Code ausführen, die anderen fluten |
| Fremde (keine Lobby-Mitglieder) | nichts: die DLL nimmt ihre Verbindung nicht an | – |
| der eigene PC | wer im Spielordner schreiben darf, kann jede Mod ersetzen – wie bei jeder Mod | – |

Spieler-Text dazu in `alpha-dist/LIESMICH.txt` („Lade nur Leute ein, denen du deinen Park
anvertraust“).

## Was aus dem Netz kommt

| Weg | Prüfung |
|---|---|
| Verbindung | `on_session_request`: nur Lobby-Mitglieder (`is_member`); Nachrichten anderer verwirft die DLL. |
| Nachrichten | Clients glauben nur dem Host (`from == hostId`), der Host nur Spielern der Sitzung. Unbekannte Arten werden ignoriert. Texte ohne Trennzeichen und Zeilenumbrüche, gekürzt (Namen 32, Chat 200, Brett 60/160, Kommentare 120 Bytes, UTF-8-sicher). Zahlen endlich und begrenzt (`numbers`, `Session._Finite`, Brett `number`). Mengenlimits je Spieler und Art (`Session.RATE_LIMITS`). |
| Bau-Befehle (Replay) | Nur registrierte Bau-Methoden (`raw[name]`) und vier Objekt-Methoden; Argumente getypt: Zahlen endlich < 1e7 (auch in Vektoren), Wörter `[%w_]`, Text als Hex ≤ 128 Bytes, Objekte nur über geteilte Ids. Kein `load`, kein Lua-Code. |
| Dateien (DLL) | Namen nur `pc2coop-…` aus `[A-Za-z0-9._-]`, ≤ 64 Zeichen, kein Pfad (`safe_name`). Park: nur vom Lobby-Besitzer, nur `pc2coop-join.bin/.trn`, ≤ 256 MB, nicht während des Ladens. Baupläne: nur `pc2coop-ride-<Absender-Id>-<n>.blueprint` (beim Host), ≤ 16 MB, ≤ 400 je Spieler und Spielstart. Notizen: nur feste Namen, ≤ 2 MB. Löschen nur `pc2coop-…`. |
| Oberfläche | Preact-Textknoten, kein `innerHTML`/`eval`; Chat und Brett gehen durch `keep()` (nicht übersetzt, als Text). Spiel-Komponenten bekommen `literal()` ohne `|[]`. Chat kann also kein HTML/JavaScript einschleusen. |
| Entwicklerkanal (QA) | Nur mit `pc2coop-dev.flag` neben der DLL; die Pakete enthalten sie nicht, das Netz kann sie nicht anlegen (Dateinamen). F8 nur damit. |
| Updates | `UPDATE.cmd` lädt nur vom GitHub-Release und nur mit passender SHA-256-Datei. |

## Was bei Fehlern passiert

| Fall | Verhalten |
|---|---|
| Lua-Fehler | Jeder Spiel-API-Aufruf in `pcall`; Tick in `frontend.lua`/Manager geschützt, Fehler ins Log (`tick-error`), das Spiel läuft weiter. `viz.lua` schaltet sich bei einem Fehler ab und räumt seine Entitäten weg. |
| JavaScript-Fehler | `render`/`poll` mit try/catch; die Ebene zeichnet dann nichts, die Oberfläche des Spiels bleibt. |
| DLL | Ausnahmen in Befehlen und Poll abgefangen (`net:error|command-exception`); verweigerte Sends warten in der Ausgangsschlange; nimmt ein Spieler 60 s nichts an: `net:peer-stalled`. |
| Spieler stürzt ab / geht | Der Host sieht ihn gehen, der Platz wird frei; er kann wieder beitreten (Dialog „Wieder beitreten?“). |
| Host stürzt ab / geht | Pille „Keine Verbindung zum Host · m:ss“, nach 30 s Frage „Warten/Verlassen“; „Die Sitzung ist beendet“; der Park bleibt beim Spieler offen. |
| Daten unterwegs verloren | Der Host markiert den Spieler, schickt beim nächsten Kontakt `resync`, der Park kommt neu. Seit 2.0.0: kommt der Park 20 s nicht voran, fragt der Spieler neu (3×), dann „Erneut versuchen“; nach jedem Laden schickt der Host Brett, Regeln, Bewertungen, Tempo, Wettbewerb und wer was hält (`Session._SendTeam`). |
| Nicht synchron | Lässt sich eine Änderung nicht anwenden: Markierung `desync`, der Host erfährt es, Pille/Knopf „Neu synchronisieren“ lädt den Park des Hosts neu. |
| Nicht unterstütztes Werkzeug | Hinweis „… wird noch nicht übertragen“, die Änderung bleibt lokal (Abhilfe: Neu synchronisieren). |
| Unerwartetes | Unbekannte Nachrichten werden ignoriert, Werte außerhalb der Grenzen verworfen; ein Mitspieler über dem Limit wird gebremst, nicht getrennt. |

## Wie es geprüft wird

- `tests/test_fuzz_session_lua.py` nach der Methode von coop-anything (dort tools/fuzz und
  tools/chaos, Playbooks *fuzzing-coop-sync*, *network-chaos-testing*): drei Lua-Runtimes,
  Sitzungen aus festen Seeds (Chat, Brett, Abstimmungen, Regeln, Markierungen, Emotes,
  Einladungen, Neu synchronisieren), Netzprofile `lan`, `bad_wifi`, `hell` (Verzögerung,
  Schwankung, Abbrüche mit Datenverlust wie der DLL-Stall); bei jedem Laden starten die
  Lua-Module neu wie im Spiel. Orakel: kein Lua-Fehler; Brett, Regeln und Spieler wie beim
  Host; nichts doppelt; Chat in der Reihenfolge des Hosts; nach dem Heilen Ruhe. Dazu über
  5000 bösartige Nachrichten an Host und Spieler: kein Fehler, keine Dateinamen außerhalb, alle
  Grenzen halten.
- `tests/test_sync_lua.py`: bösartige Bau-Befehle (fremde Funktionen, NaN/∞, falsche
  Referenzen) – nichts außerhalb der Liste wird aufgerufen.
- `tests/test_session_lua.py`: Fluten (Chat, Brett), kaputte Zahlen, Markierungs-Ids.
- Funde des Fuzzers (2026-11-21), behoben: (1) wer den Park zweimal kurz nacheinander lud,
  hatte danach kein Brett und keine Regeln; (2) ging die Park-Übertragung unterwegs verloren,
  wartete der Spieler für immer auf „Park kommt“.
- Nicht abgedeckt: echtes Steam (nur in der Abnahme mit zwei PCs), der Flugschreiber
  (coop-anything tools/flight, C++-Format; unser Log hat die Sitzungszeilen) – Kandidat für später. Das
  Chaos-Relay von coop-anything kann nicht zwischen zwei Steam-Spieler (Steam-Relay); die
  Störungen werden deshalb in den Lua-Tests nachgestellt.

## Bekannte Restrisiken

- Ein böswilliger Host kann alles, was eine Park-Datei kann (der Lader des Spiels liest sie
  wie einen Workshop-Park), und beliebige Texte zeigen. Nur Sitzungen von Leuten beitreten,
  denen man vertraut.
- Ein böswilliger Mitspieler kann abreißen (Regel „erst fragen“ hilft), innerhalb der Limits
  stören und erlaubte Bau-Funktionen mit großen, endlichen Werten aufrufen (der Host wird
  langsam). Nur vertrauenswürdige Freunde einladen.
- Steam-Namen, die mit „[“ beginnen, laufen im Verlauf durch die Textübersetzung des Spiels
  (`shown`) – nur Anzeige.
- Logs enthalten Steam-Namen und -IDs: nur privat weitergeben, nie ins Repository.
- Die DLL ist nicht signiert (SmartScreen-Hinweis); Integrität über die SHA-256 des Releases.
