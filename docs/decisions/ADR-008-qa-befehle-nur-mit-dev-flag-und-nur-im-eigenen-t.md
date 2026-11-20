# ADR-008: QA-Befehle nur mit Dev-Flag und nur im eigenen Testpark

- **Status:** Akzeptiert
- **Datum:** 2026-11-14
- **Betrifft:** FEAT-210–213

## Kontext

Automatische Tests im echten Spiel sind nötig, dürfen aber nie Spielstände oder das Spiel des
Eigners verändern.

## Entscheidung

QA-Befehle und Lua-Skripte laufen nur, wenn `pc2coop-dev.flag` im Mod-Ordner liegt (nie in
Paketen), und nur in einem Park, den QA selbst in dieser Sitzung neu angelegt hat
(„PC2Coop-Test“). Getestet wird in einer Testkopie des Spiels, nie in der Installation des
Eigners, mit Watchdog.

## Alternativen

- Tests mit dem Eigner als Mitspieler.
- QA über das Netz steuerbar.

## Begründung

Schutz der Spielstände und des PCs des Eigners (der PC fror einmal bei einem Test ein).

## Konsequenzen

- Siehe `docs/development/TESTING.md`.
- Mitspieler werden in Tests nachgestellt; echte Zwei-PC-Tests macht der Eigner selbst.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
