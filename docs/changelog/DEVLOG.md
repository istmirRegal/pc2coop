# Development Log

Für Entwickler: interne Änderungen, Funde, Refactors, bekannte Probleme. Neueste zuerst.
Spieler-Änderungen: `docs/changelog/CHANGELOG.md`.

## 2026-11-20 – Dokumentationssystem

- `docs/` neu gegliedert: `project/` (Registry, Überblick, Roadmap, Glossar), `features/`
  (eine Datei pro Bereich, jede Funktion mit `### FEAT-nnn`), `architecture/`, `ui-ux/`,
  `decisions/` (ADR-001–019, nachträglich aus Code und Commits), `development/`, `changelog/`.
- `CLAUDE.md` als Einstieg; Pflicht-Ablauf in `docs/development/AI_WORKFLOW.md`.
- `tools/check_docs.py` + `tests/test_docs.py` (FEAT-221).
- Ältere Dateien `docs/KONZEPT.md`, `NEXT.md`, `COOP_DESIGN.md`, `BRIDGE.md`, `RESEARCH.md`,
  `VALIDATION.md` bleiben als Hintergrund (im Index verlinkt).
- LIESMICH: „Dinge kaufen“ aus „Noch nicht“ entfernt (gibt es seit 1.13.0).

## Bekannte Probleme und Aufräum-Kandidaten

| Was | Wo | Notiz |
|---|---|---|
| Zweig `key:ping` wird nie ausgelöst | `session.lua` | DLL sendet es seit 1.9.0 nicht mehr (Ping per Mittelklick); entfernen |
| Kopfkommentar nennt `['pc2coop'].request` | `CoopLayer.js` Zeile 7–8 | Anfragen gehen über `Engine.sendEvent('PC2Coop_Request')`; Kommentar korrigieren |
| UI-Aktionen ohne Knopf | `ui.lua` `ping`, `board_assign`, `shopclose` | bewusst (Mittelklick, E/Tab) bzw. UX-C3 |
| Legacy-Python und `START.cmd` | `pc2coop/`, `alpha-dist/START.cmd`, `alpha-dist/start.ps1` | FEAT-010, FEAT-218; Entfernen braucht Entscheidung |
| Lua-Texte ohne Umlaute | `session.lua`, `menu.lua` | UX-B1 |
| Besuchen-Reiter „Steuerung“ veraltet | `CoopLayer.js` `renderVisit` | UX-A1 |
| Nicht mit zwei PCs geprüft | alles nach 1.5.0 | siehe ROADMAP |

## 2026-11-19 – 1.13.0

- `figure.lua`: Gast-Figur per `CompilePrefab` (ADR-011); Statue als Rückfall.
- `shop.lua`, Kaufen über den Host (ADR-015); Essen beim Gehen (ADR-016).
- G (Gast-Kamera) gebaut und wieder entfernt (ADR-014).
- Fund: Nach `VisitorCamera` setzt das Spiel die Kamera zurück → Kamera erst später anfordern (`toFigure`).
- Fund: Look darf erst nach Beitritts-Zustimmung gesendet werden (Join-Security-Test).
- Fund: Look-Nachrichten außerhalb der Park-Stage ignorierte der Host → Behandlung auf msg-Ebene.
- Fund: Lokalisierungs-Schlüssel in `span` werden nicht übersetzt → `shown()`.
- 333 Tests.

## 2026-11-19 – 1.12.3 und Pakete

- `replay.lua` `chunkAt` geht zu dem Elternteil mit eigener Volume-ID (Treffer ist ein Chunk-Kind).
- Pakete ohne ACSE (ADR-009), Nexus ohne Skripte, DLL-VERSIONINFO (ADR-010).
- Alle älteren Release-Dateien gelöscht (Wunsch des Eigners).

## 2026-11-18 – 1.10.0 bis 1.12.2

- Bahnen als Baupläne (ADR-006); Lua-Skript-Kanal für QA; `game_watchdog.ps1` nach einem
  Einfrieren des PCs beim Test.
- 1.12.1/1.12.2: Reiter in der TabBar sperrte die HUD → neben die TabBar (ADR-007).
- Avatar-Prefab des Startbildschirms stürzt im Park ab (ADR-012).

## 2026-11-14 bis 2026-11-17 – 1.4.1 bis 1.9.1

- 1.4.2: String-Routine per Byte-Muster statt fester Adresse (FEAT-009, `tools/scan_exe.py`).
- 1.4.3: geordneter Ausgang pro Spieler in der DLL (Steam-Code 25 bei vollem Puffer),
  `tests/native/test_outbox.cpp`.
- 1.5.0: aus dem ersten echten Zwei-Spieler-Test – doppelte Lobby-Meldung von Steam, Park
  doppelt übertragen; Bündeln von Bauplan-Änderungen.
- 1.6.1: Sicherheits-Durchgang (Dateien nur vom Host, Freundes-Prüfung, Dev-Flag für QA).
- 1.9.0: Manifest beim Speichern der Park-Kopie (Aliase), Setter gehen an den Autor zurück.
