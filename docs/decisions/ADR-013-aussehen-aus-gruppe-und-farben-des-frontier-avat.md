# ADR-013: Aussehen aus Gruppe und Farben des Frontier-Avatars

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-162

## Kontext

Jeder Spieler hat einen Frontier-Avatar (`Database.GameDatabase.tPlayers[k]:GetData("AvatarData","Main")`).

## Entscheidung

`Figure.FromAvatar` liest Altersgruppe und Kleidungsfarben und baut daraus ein kurzes Aussehen
(`Figure.LookText`), das per `look` an den Host und im `roster` an alle geht – erst nachdem der
Spieler dem Beitritt zugestimmt hat. Empfänger prüfen es (`Figure.ParseLook`).

## Alternativen

- Avatar-Modelle 1:1 (siehe ADR-012).
- Zufälliges Aussehen.

## Begründung

Wiedererkennbar, klein über das Netz, sicher geprüft.

## Konsequenzen

- Kein Aussehen vor der Zustimmung (Datenschutz beim Beitritt).
- Gruppen ohne passende Modelle fallen auf Standard zurück.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
