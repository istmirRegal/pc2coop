# ADR-019: Dokumentation im Repository mit Feature-Registry und Prüfung

- **Status:** Akzeptiert
- **Datum:** 2026-11-20
- **Betrifft:** FEAT-221

## Kontext

Wissen über Funktionen, Entscheidungen und Fallstricke lag in Gesprächen und Commit-Texten.
Eine neue KI oder ein neuer Entwickler musste alles neu herausfinden.

## Entscheidung

`docs/` ist die Wissensbasis: Feature-Registry mit festen IDs, Bereichsdateien pro Funktion,
Architektur, UI-Inventar, ADRs, Entwicklung, Changelog/Devlog. `CLAUDE.md` ist der Einstieg.
Doku-Pflege ist Teil jeder Änderung (`docs/development/AI_WORKFLOW.md`). `tools/check_docs.py`
prüft Doku gegen Code und läuft als Test.

## Alternativen

- Wiki außerhalb des Repositories (läuft dem Code davon).
- Nur Code-Kommentare.

## Begründung

Doku wird mit dem Code versioniert und automatisch geprüft. Git bleibt die technische Wahrheit.

## Konsequenzen

- Jede Änderung ändert auch Doku; ein fehlender Eintrag lässt die Tests scheitern.
- Entfernte Funktionen bleiben dokumentiert (Status Removed/Replaced).
