# ADR-005: Replay nur über Whitelist, nichts aus dem Netz wird Code

- **Status:** Akzeptiert
- **Datum:** 2026-11-15
- **Betrifft:** FEAT-065–071

## Kontext

Gelände und Wege lassen sich nur nachbauen, indem dieselben Editor-Aufrufe beim Mitspieler
wiederholt werden.

## Entscheidung

`replay.lua` ummantelt eine feste Liste von API-Methoden (`OPERATION_METHODS`,
`CHANGELIST_METHODS`, `OBJECT_METHODS`, `HIER_METHODS`, `IMMEDIATE_METHODS`) und sendet Aufrufe
als Text. Beim Empfänger wird der Text geparst, die Methode muss in der Liste stehen, die
Argumente müssen Zahlen/Vektoren/bekannte Kennungen sein. Kein `load`, kein `eval`.

## Alternativen

- Lua-Code senden und ausführen (Sicherheitslücke: jeder Mitspieler könnte Code ausführen).
- Alle Methoden erlauben.

## Begründung

Mitspieler sind Freunde, aber eine Mod darf keine Fernausführung öffnen.

## Konsequenzen

- Jede neue Methode muss bewusst in die Liste und braucht einen Test.
- Unbekannte Aufrufe werden nicht synchronisiert (Hinweis an den Spieler).

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
