# Arbeitsablauf für KI (und Menschen)

Verbindlich für **jede** Änderung, auch kleine. Ziel: Wer ohne Gesprächsverlauf einsteigt,
findet im Repository alles, was er braucht, und hinterlässt es so.

## 1. Kontext verstehen

- `CLAUDE.md` lesen, dann `docs/README.md`.
- Betroffene Funktionen in `docs/project/FEATURES.md` suchen und ihre Abschnitte in
  `docs/features/*.md` lesen (Status, Abhängigkeiten, Besonderheiten).
- Passende ADRs in `docs/decisions/` lesen. Eine Änderung, die einem akzeptierten ADR
  widerspricht, braucht ein neues ADR (und die Zustimmung des Eigners).
- `docs/changelog/DEVLOG.md` (letzte Einträge, bekannte Probleme) und `docs/project/ROADMAP.md`.
- Erst dann den Code lesen.

## 2. Auswirkungen prüfen

- `docs/architecture/DEPENDENCIES.md`: Was hängt an dem, was du änderst?
- Netzformat geändert? → alte Gäste/Hosts (FEAT-029 lehnt andere Versionen ab), `NETWORKING.md`.
- UI geändert? → `docs/ui-ux/UI_INVENTORY.md`, `NAVIGATION.md`, `COMPONENTS.md`.
- Sicherheit: kommt neue Eingabe aus dem Netz? Prüfen wie in ADR-005 (keine Ausführung,
  Felder prüfen, Längen begrenzen).
- „Darf nie brechen“ in `docs/architecture/SYSTEM_ARCHITECTURE.md`.

## 3. Umsetzen

- `docs/development/CODING_STANDARDS.md` einhalten.
- Unit-Test für das neue Verhalten schreiben (`tests/`).
- Zeilenenden erhalten (ADR-017).

## 4. Dokumentation aktualisieren (Pflicht)

Eine Änderung ist erst fertig, wenn die Doku stimmt:

| Wenn … | dann … |
|---|---|
| neue Funktion | neue ID in `docs/project/FEATURES.md` + Abschnitt `### FEAT-nnn` in der Bereichsdatei (Funktion, Technik, UI, Besonderheiten, Status, Seit, Hängt ab von) |
| Funktion geändert | Abschnitt anpassen; Status ggf. `Implemented-Untested`, bis im Spiel geprüft |
| Funktion entfernt/ersetzt | **nicht löschen**: Status `Removed`/`Replaced`, Grund und Nachfolger eintragen |
| neue Nachricht, DLL-Befehl, Ereignis | `docs/architecture/NETWORKING.md` |
| neue UI-Aktion oder Bedienelement | `docs/ui-ux/UI_INVENTORY.md` (+ NAVIGATION/COMPONENTS) |
| neuer QA-Befehl | `docs/features/dev-and-qa.md` (FEAT-210) |
| Datei/Modul neu, verschoben, umbenannt | `docs/architecture/CODE_STRUCTURE.md`, `DEPENDENCIES.md`, alle Pfade in der Doku |
| wichtige Entscheidung (auch Gestaltung) | neues ADR |
| für Spieler sichtbar | `docs/changelog/CHANGELOG.md` (Abschnitt „Unveröffentlicht“) und ggf. `alpha-dist/LIESMICH.txt` |
| intern (Refactor, Werkzeug, Fund) | `docs/changelog/DEVLOG.md` |
| Plan oder offener Punkt | `docs/project/ROADMAP.md` |

## 5. Validieren

```powershell
..\..\work\toolchain\python311\python.exe -c "import sys; sys.path.insert(0,'.'); import unittest; unittest.main(module=None, argv=['t','discover','-s','tests'])"
```

(im Ordner `outputs/pc2-coop`; das Python liegt im Arbeitsordner unter `work/toolchain/python311`). Das schließt
`tests/test_docs.py` ein; einzeln: `python tools/check_docs.py`.

- Alle Tests grün, `check_docs` ohne Fehler.
- Spielverhalten in der Testkopie prüfen, wenn möglich (`docs/development/TESTING.md`).
- `git diff --stat` mit und ohne `--ignore-cr-at-eol` vergleichen.
- Nichts Privates im Diff (`docs/development/RELEASE.md`, Abschnitt Datenschutz).
- Commit lokal; **Push, Release, Veröffentlichen nur nach Rückfrage beim Eigner.**

## Regelmäßige Abgleiche

- Vor jedem Release: `tools/check_docs.py`, Status-Spalte der Registry gegen den Test-Stand
  prüfen (was ist wirklich im Spiel getestet?), `UX_AUDIT.md` und `ROADMAP.md` durchsehen.
- Nach Refactors: alle in der Doku genannten Pfade und Funktionen existieren noch
  (`check_docs` prüft das).
- Git bleibt die technische Wahrheit: Bei Widerspruch gilt der Code; dann die Doku korrigieren
  und im DEVLOG vermerken.
