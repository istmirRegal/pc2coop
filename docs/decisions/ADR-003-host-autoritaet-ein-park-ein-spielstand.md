# ADR-003: Host-Autorität: ein Park, ein Spielstand

- **Status:** Akzeptiert
- **Datum:** 2026-11-14
- **Betrifft:** FEAT-061, FEAT-063, FEAT-048, FEAT-030

## Kontext

Mehrere Spieler ändern gleichzeitig denselben Park. Ohne Ordnung entstehen widersprüchliche
Stände.

## Entscheidung

Der Host besitzt den Park und den einzigen gültigen Spielstand. Jede Änderung geht zum Host,
bekommt eine Revision und wird in seiner Reihenfolge verteilt. Konflikte (veraltete Revision,
gelöschtes Objekt, gesperrt, Regel) werden zugunsten des Host-Stands aufgelöst (`restore`).
Gäste spielen den Park des Hosts, ihr eigener Spielstand wird nicht verändert.

## Alternativen

- Gleichberechtigte Peers mit Konfliktlösung (CRDT): für Spiel-Objekte ohne stabile IDs zu aufwendig.
- Jeder speichert eigene Kopien: Stände laufen auseinander.

## Begründung

Einfach zu verstehen, deterministisch, passt zum Spiel (ein Spielstand). Simulation (Gäste,
Geld) läuft nur beim Host.

## Konsequenzen

- Verlässt der Host, endet die Sitzung für alle.
- Geld, Zahlen und Meldungen kommen vom Host (FEAT-079); Käufe bucht der Host (ADR-015).
- Gast-Profil beim Mitspieler (FEAT-048) statt eigenem Gast-Spielstand.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
