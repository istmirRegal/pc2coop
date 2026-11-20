# ADR-006: Bahnen als Bauplan-Dateien

- **Status:** Akzeptiert
- **Datum:** 2026-11-18
- **Betrifft:** FEAT-072, FEAT-073, FEAT-199

## Kontext

Strecken bestehen aus vielen Editor-Schritten mit internem Zustand; Replay war unzuverlässig.

## Entscheidung

Eine geänderte Bahn wird mit `SaveBlueprintToFile` gespeichert, die Datei übertragen und beim
Mitspieler in einer Change-List gegen die alte Bahn getauscht. Während eine Bahn im
Streckeneditor offen ist, ist sie für andere gesperrt.

## Alternativen

- Replay jedes Streckenstücks.
- Nur Endzustand der Teile (Bahnen sind keine Szenerie-Teile).

## Begründung

Der Bauplan ist das Format des Spiels für genau diesen Zweck und enthält alles.

## Konsequenzen

- Dateien `pc2coop-ride-<n>-<m>.blueprint` im Mod-Ordner, max. 16 MB, nur vom Host.
- Änderungen erscheinen beim Verlassen des Editors, nicht live.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
