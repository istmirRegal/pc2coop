# ADR-002: Steam Networking Messages als Transport

- **Status:** Akzeptiert
- **Datum:** 2026-11-14
- **Betrifft:** FEAT-190, FEAT-191

## Kontext

Spieler sind Steam-Freunde; das Spiel hat `steam_api64.dll` bereits geladen.

## Entscheidung

Lobby über Steam Matchmaking (nur Freunde, 8 Plätze), Nachrichten zuverlässig über Steam
Networking Messages, Dateien in Stücken über denselben Kanal. Stern-Topologie: Gäste reden nur
mit dem Host.

## Alternativen

- Direkte UDP/TCP-Verbindungen (NAT, Firewall, Ports).
- Mesh zwischen allen Spielern.

## Begründung

Steam übernimmt NAT-Traversal und Relay, Freundes-Einladungen funktionieren über das Overlay.
Der Stern passt zur Host-Autorität (ADR-003).

## Konsequenzen

- Nachrichten sind Text mit `|`-Feldern, max. ~3900 Zeichen pro `ops`-Block.
- Ohne Steam (oder ohne DLL) gibt es keinen Multiplayer; die Mod zeigt das an.
- Alle Formate in `docs/architecture/NETWORKING.md`.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
