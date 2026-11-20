# ADR-017: Zeilenenden jeder Datei bleiben, wie sie sind

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** alle

## Kontext

Das Repository hat gemischte Zeilenenden (manche Lua-Dateien CRLF, andere LF);
`.gitattributes` ist `* -text`. Werkzeuge wie `sed -i` oder Python `write_text` drehten
Zeilenenden um, Diffs wurden riesig.

## Entscheidung

Jede Datei behält ihre Zeilenenden. Neue Dateien: LF. Vor jedem Commit `git diff --stat` mit
und ohne `--ignore-cr-at-eol` vergleichen.

## Alternativen

- Alles auf LF umstellen (großer Diff, Risiko für Spiel-Dateien).

## Begründung

Kleine, prüfbare Diffs.

## Konsequenzen

- Für Änderungen Werkzeuge nehmen, die Zeilenenden erhalten (Edit-Tool).

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
