# ADR-011: Gast-Figur aus der Gast-Vorlage des Spiels (CompilePrefab)

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-161, FEAT-171, FEAT-172

## Kontext

Im Besucher-Modus sollen Mitspieler einander als Person sehen. 1.12.0 nutzte eine Statue
(ADR-012). Der Eigner wollte ein animiertes Modell.

## Entscheidung

`figure.lua` nimmt die Gast-Vorlage `peep` (`FindPrefab`), entfernt Gast-Logik und Root-Motion
(`Guest*`, `BakedMotionApplication`, `BakedAnimTree`, `LevelOfDetail`, `SwimBody`), setzt feste
Grundspiel-Modelle und je Zustand eine gebackene Animation (`<gruppe>$<anim>`), und kompiliert
das zur Laufzeit mit `api.entity.CompilePrefab`. Eine Figur hat eine Entität pro Zustand; die
anderen liegen versteckt bei y = −500.

## Alternativen

- Echte Gäste steuern (Spiel-KI greift ein).
- Eigenes Modell (Spieldateien/Assets dürfen nicht ins Repository).

## Begründung

Nur Spiel-eigene Daten, zur Laufzeit; nichts wird ausgeliefert. Sieht aus wie ein Gast.

## Konsequenzen

- Fehlende Animationen pro Gruppe werden ersetzt (`MISSING`).
- Statue bleibt als Rückfall, wenn Kompilieren scheitert.
- Abhängig von Prefab-Namen des Spiels; nach Updates prüfen.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
