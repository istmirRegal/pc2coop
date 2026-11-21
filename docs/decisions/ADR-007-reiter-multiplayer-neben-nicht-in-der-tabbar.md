# ADR-007: Reiter „Multiplayer“ neben, nicht in der TabBar

- **Status:** Abgelöst durch ADR-021 (2026-11-21)
- **Datum:** 2026-11-18
- **Betrifft:** FEAT-111

## Kontext

1.12.0 fügte einen Reiter in die TabBar der Bauleiste ein. Die TabBar ordnet jedem Reiter den
Browser-Abschnitt mit gleichem Index zu; unserer hatte keinen. Ein Klick sperrte die ganze HUD,
Beenden stürzte ab (1.12.1).

## Entscheidung

Der Reiter sitzt außerhalb der TabBar, absolut am rechten Ende der Zeile (wie der Spiel-Reiter
„zurück zum Browser“), und öffnet nur das Multiplayer-Fenster.

## Alternativen

- Eigenen Browser-Abschnitt anlegen (tiefer Eingriff in Spieldaten).
- Nur F7.

## Begründung

Kein Eingriff in die Datenstruktur der Bauleiste.

## Konsequenzen

- Bei Spiel-Updates prüfen, ob die Zeile der Bauleiste gleich bleibt (QA `bar-check`).
- Regel für alle Eingriffe: keine Elemente in Spiel-Listen, deren Index etwas bedeutet.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
