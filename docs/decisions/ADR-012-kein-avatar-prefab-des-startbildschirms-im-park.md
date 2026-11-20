# ADR-012: Kein Avatar-Prefab des Startbildschirms im Park

- **Status:** Akzeptiert
- **Datum:** 2026-11-18
- **Betrifft:** FEAT-172, FEAT-162

## Kontext

Naheliegend war, den Frontier-Avatar des Startbildschirms direkt als Figur zu benutzen.

## Entscheidung

Das Avatar-Prefab des Startbildschirms wird im Park nicht erzeugt. Die Figur kommt aus der
Gast-Vorlage (ADR-011); vom Avatar wird nur das Aussehen übernommen (ADR-013).

## Alternativen

- Avatar-Prefab im Park laden.

## Begründung

Getestet: das Spiel stürzt im Park ab.

## Konsequenzen

- Das Aussehen ist eine Annäherung (Gruppe, Farben), kein exakter Avatar.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
