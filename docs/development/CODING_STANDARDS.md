# Code-Regeln

## Allgemein

- Eigener Code ist MIT (`LICENSE`); Dateien beginnen mit „Original MIT code“.
- **Keine Spieldateien, Assets oder Auszüge aus Spieldateien** im Repository (auch nicht in Tests).
- Kommentare und Commit-Texte auf Englisch, Texte für Spieler auf Deutsch (ADR-018).
- Zeilenenden der Datei erhalten (ADR-017); neue Dateien LF.
- Kleine, gezielte Änderungen; kein Umformatieren nebenbei.

## Lua (Mod)

- `local global = _G`; alles Globale über `global.` (ACSE-Umgebung).
- Modul = Tabelle (`local Visitor = {}` … `return Visitor`). Öffentlich: `Modul.Funktion`;
  `Modul._Funktion` = intern/Test-Naht (darf von Tests aufgerufen werden).
- **Jeder Aufruf von Spiel-APIs in `global.pcall`.** Ein Fehler darf nie das Spiel stoppen;
  Fehler ins Log (`emit`/`Diagnostic.Write`).
- Zustand über Parkwechsel: `shared.lua` oder DLL-`kv`, nicht in Modul-Variablen.
- Netz-Eingaben prüfen: `clean`/`cleanText` (Länge, Zeichen), `validGid`, `validResource`,
  `validRideKey`, Zahlen mit `tonumber` + Bereich. Nie `load`/`loadstring` auf Netzdaten (ADR-005).
- Host-Logik nur in `session.lua` (`hostChange`, `authority*`); Basismodule ohne Sitzungswissen.
- Frames statt Zeit (`frames`); Echtzeit nur über DLL `now` (FEAT-197).
- Log-Zeilen: `[PC2Coop<Modul>] <art>:<detail>`; häufige Zeilen (pres, cmd) nicht loggen.

## JavaScript (Oberfläche)

- Nur `CoopLayer.js`; Preact `h()` ohne JSX, Inline-Styles (DESIGN_SYSTEM.md).
- Komponenten des Spiels benutzen (`Button`, `Dialog`, `InputField`, `Icon`).
- Texte an Spiel-Komponenten über `literal()`, Spieltexte über `shown()`.
- Kein Zustand, der Lua widerspricht: die Oberfläche zeigt `state.coop`, Aktionen gehen über
  `request()`. Neue Aktion → Eintrag in der Tabelle in `ui.lua` und in UI_INVENTORY.md.
- Eingriffe in Spiel-Komponenten (`patch*`) immer in `try/catch`, Markierung `__pc2coop`,
  nie Elemente in Listen einfügen, deren Index Bedeutung hat (ADR-007).

## C++ (DLL)

- So klein wie möglich: nur Steam, Dateien, Tasten/Maus, Log.
- Dateinamen nur nach fester Liste (`pc2coop-…`), Größen begrenzen.
- Tasten/Maus nur, wenn das Spielfenster vorne ist und Lua es angefordert hat (Abschalten nach 2 s).
- Nach jeder Änderung der DLL: `tools/build_native.py`, Version stimmt mit `Session.VERSION`.

## Python (Werkzeuge, Tests)

- Standardbibliothek + `lupa`; keine neuen Abhängigkeiten ohne Rückfrage.
- Tests mit `unittest`; Lua-Module laufen unter `lupa` gegen nachgebaute Spiel-APIs.
- Mehrere Spieler = mehrere Lua-Laufzeiten (`tests/test_session_lua.py`).

## Benennung

- Funktionen: `FEAT-nnn` (Registry), Entscheidungen: `ADR-nnn`, UX-Befunde: `UX-<Gruppe><n>`.
- Dateien der Mod im Spielordner beginnen mit `pc2coop-`.
