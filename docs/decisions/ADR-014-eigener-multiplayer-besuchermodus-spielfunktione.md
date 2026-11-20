# ADR-014: Eigener Multiplayer-Besuchermodus, Spielfunktionen nur technisch nutzen

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-160–174

## Kontext

Planet Coaster 2 hat eigene Besucher-Funktionen (Laufmodus, Gast-Kamera). 1.13-Entwicklung
fügte kurz „G – Gast begleiten“ hinzu; der Eigner fand das verwirrend und doppelt zum
Radialmenü des Spiels. Klarstellung des Eigners: Wir bauen einen Multiplayer-Modus, die
Einzelspieler-Funktionen bleiben, wie sie sind.

## Entscheidung

Der Besucher-Modus ist ein Multiplayer-Modus mit Ansicht von hinten (eigene Figur) und
Ich-Sicht. Die Ich-Sicht **ist** der Laufmodus des Spiels (`VisitorCamera`); Eingänge nutzen die
Interaktionen des Spiels (`Helpers.VisitorCameraTargetUtils`) mit dessen Texten. Mehrwert
entsteht nur durch Multiplayer: Mitspieler sehen dich, Emotes, gemeinsames Mitfahren,
Bewertungen, Kaufen mit Buchung beim Host. „G“ wurde entfernt.

## Alternativen

- Einzelspieler-Funktionen erweitern (G, eigene Gast-Kamera).
- Alles selbst bauen (eigene Ich-Sicht).

## Begründung

Keine Doppelungen, fühlt sich wie das Spiel an, weniger Code.

## Konsequenzen

- Neue Besucher-Funktionen nur, wenn sie für Mitspieler etwas bringen.
- Nach dem Laufmodus setzt das Spiel die Kamera zurück: Kamera erst später anfordern (`toFigure`).

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
