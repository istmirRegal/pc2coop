# ADR-001: Alles im Spiel: Lua über ACSE plus eine kleine DLL

- **Status:** Akzeptiert
- **Datum:** 2026-11-14
- **Betrifft:** alle; FEAT-190, FEAT-218

## Kontext

Frühe Fassungen (Python-Alpha, FEAT-218) liefen als eigenes Programm neben dem Spiel und
sprachen über Dateien/Netz mit einer kleinen Mod. Das brauchte Ports, VPN oder LAN, ein zweites
Fenster und machte Einrichtung und Fehlersuche schwer.

## Entscheidung

Die Mod läuft vollständig im Spielprozess: Lua-Module über ACSE, Oberfläche im Gameface-UI
des Spiels, und eine DLL (`PC2CoopDiagnostic.dll`) nur für das, was Lua nicht kann (Steam,
Dateien, Tasten, Maus, Log).

## Alternativen

- Externes Programm (Python/Electron) mit Socket zur Mod.
- Nur Lua ohne DLL (kein Netz möglich).
- Eigener Server.

## Begründung

Ein Programm, ein Start, keine offenen Ports, Steam-Freunde als einzige Voraussetzung.
Die Spiel-APIs sind nur in Lua erreichbar; die DLL hält die Brücke klein.

## Konsequenzen

- Code muss gegen Spiel-Updates robust sein (`pcall`, Prüfungen, ADR-008-Tests).
- Die DLL ist native Software im Spielprozess: klein halten, keine Netzwerk-Logik außer Steam.
- Legacy-Python bleibt nur als Forschung (FEAT-218).

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
