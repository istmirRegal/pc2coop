# ADR-016: Essen und Trinken beim Gehen

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-170

## Kontext

Die Steh-Animationen fürs Essen/Trinken sind Teil-Animationen und zeigen allein nichts.

## Entscheidung

Die Figur nutzt die Geh-Varianten (`walkeat`, `walkdrink`), etwa 20 s (`MEAL_FRAMES` 1200).

## Alternativen

- Steh-Animation mit Grundpose mischen (kein Mischen in der kompilierten Figur).

## Begründung

Funktioniert mit einer Entität pro Zustand.

## Konsequenzen

- Beim Stehen während des Essens wird die Gehanimation gezeigt.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
