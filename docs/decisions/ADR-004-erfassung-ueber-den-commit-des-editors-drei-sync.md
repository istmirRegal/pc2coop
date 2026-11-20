# ADR-004: Erfassung über den Commit des Editors, drei Sync-Wege

- **Status:** Akzeptiert
- **Datum:** 2026-11-14 (erweitert 2026-11-18)
- **Betrifft:** FEAT-060, FEAT-065, FEAT-072

## Kontext

Das Spiel hat keine Multiplayer-API. Änderungen müssen an einer Stelle erkannt werden, die
für alle Werkzeuge gleich ist.

## Entscheidung

1. **Szenerie-Teile:** `api.undo.CommitPreview` wird ummantelt (`capture.lua`); nach dem Commit
   wird der Endzustand der Teile gelesen und als `up`/`del` gesendet.
2. **Editor-Aufrufe** (Gelände, Wege, Seen, Stempel, Parkverwaltung): Whitelist-Replay (ADR-005).
3. **Bahnen** (Achterbahnen, Schienen, Rutschen): Bauplan-Datei (ADR-006).

## Alternativen

- Nur Endzustände für alles (Gelände und Wege sind keine Teile).
- Speicherstand regelmäßig übertragen (zu groß, zu langsam).

## Begründung

Jeder Weg passt zu einer Art von Daten des Spiels; Endzustände sind robust gegen
Zwischenschritte.

## Konsequenzen

- Neues Werkzeug = prüfen, welcher Weg passt (API-Rekorder FEAT-214); sonst Hinweis FEAT-077.
- Drei Codepfade, drei Testgruppen.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
