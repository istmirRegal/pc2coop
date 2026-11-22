# Architekturentscheidungen (ADR)

Jede wichtige Entscheidung – technisch oder gestalterisch – bekommt eine Datei
`ADR-nnn-<kurzname>.md`. Nummern werden nie neu vergeben. Eine überholte Entscheidung bleibt
stehen und bekommt den Status `Ersetzt durch ADR-nnn`.

**Wann ein ADR?** Wenn eine Entscheidung schwer rückgängig zu machen ist, mehrere Funktionen
betrifft, eine Alternative bewusst verworfen wurde oder der Eigner eine Richtung vorgibt.

**Status-Werte:** `Vorgeschlagen`, `Akzeptiert`, `Ersetzt durch ADR-nnn`, `Verworfen`.

| ADR | Entscheidung | Status | Datum |
|---|---|---|---|
| [ADR-001](ADR-001-alles-im-spiel-lua-ueber-acse-plus-eine-kleine-d.md) | Alles im Spiel: Lua über ACSE plus eine kleine DLL | Akzeptiert | 2026-11-14 |
| [ADR-002](ADR-002-steam-networking-messages-als-transport.md) | Steam Networking Messages als Transport | Akzeptiert | 2026-11-14 |
| [ADR-003](ADR-003-host-autoritaet-ein-park-ein-spielstand.md) | Host-Autorität: ein Park, ein Spielstand | Akzeptiert | 2026-11-14 |
| [ADR-004](ADR-004-erfassung-ueber-den-commit-des-editors-drei-sync.md) | Erfassung über den Commit des Editors, drei Sync-Wege | Akzeptiert | 2026-11-14 (erweitert 2026-11-18) |
| [ADR-005](ADR-005-replay-nur-ueber-whitelist-nichts-aus-dem-netz-w.md) | Replay nur über Whitelist, nichts aus dem Netz wird Code | Akzeptiert | 2026-11-15 |
| [ADR-006](ADR-006-bahnen-als-bauplan-dateien.md) | Bahnen als Bauplan-Dateien | Akzeptiert | 2026-11-18 |
| [ADR-007](ADR-007-reiter-multiplayer-neben-nicht-in-der-tabbar.md) | Reiter „Multiplayer“ neben, nicht in der TabBar | Abgelöst (ADR-021) | 2026-11-18 |
| [ADR-008](ADR-008-qa-befehle-nur-mit-dev-flag-und-nur-im-eigenen-t.md) | QA-Befehle nur mit Dev-Flag und nur im eigenen Testpark | Akzeptiert | 2026-11-14 |
| [ADR-009](ADR-009-keine-acse-dateien-in-paketen.md) | Keine ACSE-Dateien in Paketen | Akzeptiert | 2026-11-19 |
| [ADR-010](ADR-010-nexus-paket-ohne-skripte-dll-mit-versionsangaben.md) | Nexus-Paket ohne Skripte, DLL mit Versionsangaben | Teilweise ersetzt (ADR-023) | 2026-11-19 |
| [ADR-011](ADR-011-gast-figur-aus-der-gast-vorlage-des-spiels-compi.md) | Gast-Figur aus der Gast-Vorlage des Spiels (CompilePrefab) | Akzeptiert | 2026-11-19 |
| [ADR-012](ADR-012-kein-avatar-prefab-des-startbildschirms-im-park.md) | Kein Avatar-Prefab des Startbildschirms im Park | Akzeptiert | 2026-11-18 |
| [ADR-013](ADR-013-aussehen-aus-gruppe-und-farben-des-frontier-avat.md) | Aussehen aus Gruppe und Farben des Frontier-Avatars | Akzeptiert | 2026-11-19 |
| [ADR-014](ADR-014-eigener-multiplayer-besuchermodus-spielfunktione.md) | Eigener Multiplayer-Besuchermodus, Spielfunktionen nur technisch nutzen | Akzeptiert | 2026-11-19 |
| [ADR-015](ADR-015-kaufen-host-prueft-und-bucht-mit-addcashdelta.md) | Kaufen: Host prüft und bucht mit AddCashDelta | Akzeptiert | 2026-11-19 |
| [ADR-016](ADR-016-essen-und-trinken-beim-gehen.md) | Essen und Trinken beim Gehen | Akzeptiert | 2026-11-19 |
| [ADR-017](ADR-017-zeilenenden-jeder-datei-bleiben-wie-sie-sind.md) | Zeilenenden jeder Datei bleiben, wie sie sind | Akzeptiert | 2026-11-19 |
| [ADR-018](ADR-018-deutsche-texte-string-literal-fuer-spiel-kompone.md) | Deutsche Texte, STRING_LITERAL für Spiel-Komponenten | Akzeptiert (Übersetzung: ADR-022) | 2026-11-14 |
| [ADR-019](ADR-019-dokumentation-im-repository-mit-feature-registry.md) | Dokumentation im Repository mit Feature-Registry und Prüfung | Akzeptiert | 2026-11-20 |
| [ADR-020](ADR-020-native-oberflaeche-spiel-bausteine-variablen-rem.md) | Native Oberfläche: Bausteine, Variablen und Einheiten des Spiels | Vorgeschlagen | 2026-11-20 |
| [ADR-021](ADR-021-einstieg-ueber-runden-knopf-links-oben.md) | Einstieg über einen runden Knopf links oben | Akzeptiert | 2026-11-21 |
| [ADR-022](ADR-022-englisch-nach-spielsprache.md) | Englisch nach der Sprache des Spiels | Akzeptiert | 2026-11-21 |
| [ADR-023](ADR-023-eine-zip-mit-setup-fuer-alle-plattformen.md) | Eine ZIP mit Setup.exe für GitHub, Nexus und Vortex | Teilweise ersetzt (ADR-024) | 2026-11-22 |
| [ADR-024](ADR-024-setup-als-eigener-download.md) | Setup als eigener Download, die ZIP ohne Programme | Akzeptiert | 2026-11-22 |

## Vorlage

```markdown
# ADR-nnn: <Titel>

- **Status:** Vorgeschlagen
- **Datum:** JJJJ-MM-TT
- **Betrifft:** FEAT-…

## Kontext
## Entscheidung
## Alternativen
## Begründung
## Konsequenzen
```
