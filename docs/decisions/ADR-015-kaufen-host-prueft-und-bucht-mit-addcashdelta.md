# ADR-015: Kaufen: Host prüft und bucht mit AddCashDelta

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-169

## Kontext

Besucher sollen an Läden kaufen können; Geld gibt es nur im Park des Hosts (ADR-003).

## Entscheidung

`shop.lua` liest die Waren wie das Info-Fenster des Spiels. Der Gast schickt `buy|shop-gid|index`;
der Host prüft Laden (offen, Ware), bucht den Preis mit `AddCashDelta` in der passenden
Kategorie (`ExpenditureCategory_FoodSales`/`DrinkSales`/`FacilitySales`) und meldet `sold` und
`em` (essen/trinken). Höchstens ein Kauf pro 2 s und Spieler.

## Alternativen

- Echten Gast kaufen lassen.
- Kaufen ohne Geld (nur Animation).

## Begründung

Wirkt im Park wie ein Verkauf, keine Manipulation durch Gäste möglich.

## Konsequenzen

- Bestand und Gast-Statistiken des Ladens ändern sich nicht (nur Kasse).
- Ohne Sitzung bucht der Spieler in seinen eigenen Park.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
