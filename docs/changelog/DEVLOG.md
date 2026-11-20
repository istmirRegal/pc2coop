# Development Log

Für Entwickler: interne Änderungen, Funde, Refactors, bekannte Probleme. Neueste zuerst.
Spieler-Änderungen: `docs/changelog/CHANGELOG.md`.

## 2026-11-20 – UX-Overhaul P0, Schritt 2: Schrift und Texte

- Die Schriftgrößen folgen der Skala des Spiels: 0.9, 1, 1.1 und 1.2 rem. Vorher waren es
  zehn Größen von 13 bis 28 px.
- JS-Texte folgen §3/§7 aus `UX_OVERHAUL.md`. UX-A3, UX-A4 und UX-B3 sind für die Mod-Oberfläche
  erledigt. Die Lua-Verlaufstexte mit „Lobby“ und der F8-Dialog sind noch offen.
- Umlaute in 26 Lua-Meldungszeilen (UX-B1). Geändert wurden nur Texte in
  `toast`/`addFeed`/`failJoin`/`_RefuseJoin` und in den Beitrittsgründen. Protokoll-Codes wie
  `laedt` sind unverändert. Ein Test ist angepasst (`tests/test_coop_play_lua.py`).
- Testkopie (1080p) mit offenem und mit geschlossenem Fenster fotografiert: nichts läuft über.
- Fallstrick: `sed -i` stellt hier CRLF auf LF um. Nach jeder Textersetzung
  `git diff --stat` mit und ohne `--ignore-cr-at-eol` vergleichen (ADR-017).

## 2026-11-20 – UX-Overhaul P0, Schritt 1: Farben und Einheiten

- `CoopLayer.js` hat keine festen Farben mehr (außer Spielerfarben). Alle Farben kommen über
  `C(name)` aus den CSS-Variablen des Spiels.
- Alle Größen sind `rem` (`px / 20`). Die Mauskoordinaten des Kontextmenüs bleiben in Pixeln,
  der Abstand zum Rand ist über `remPx()` umgerechnet.
- Abschnittstitel sind fett statt in Großbuchstaben.
- Fund: Gameface ignoriert `var(--…)` im Inline-`background`. Die Mod liest die Werte deshalb
  wie die Bible des Spiels per `getComputedStyle` aus.
- Testkopie (1080p): Fenster, Toasts und Spielerleiste fotografiert, alles lesbar.
- Hinweis zum Bild: Bei offenem Fenster liegt die Spielerleiste unter dem abgedunkelten
  Hintergrund. Das war vorher genauso.
- Noch nicht geprüft: andere Auflösungen, UI-Skalierung, Akzentfarbe, Farbenblind-Modus.

## 2026-11-20 – UX-Overhaul: Analyse und Konzept

- UI-Code des Spiels (entpackt, nur lokal) ausgewertet: `docs/ui-ux/NATIVE_UI.md`. Kernfunde:
  - Das Spiel skaliert über `rem` (1 rem = 20 px bei 1080p × Auto- × Nutzer-Skalierung).
  - Alle Farben sind CSS-Variablen mit 9 Akzentfarben und 3 Farbenblind-Modi.
  - Fertige Bausteine: `Panel`, `DataRow`, Einstellungszeilen, Tooltips, Tastenhinweise,
    Radialmenü, 1234 Icons.
- Befund zur Mod: feste `px` (zehn Schriftgrößen, 13–28 px), 25 Hex-Farben, 4 von vielen
  Spiel-Komponenten genutzt.
- Konzept `docs/ui-ux/UX_OVERHAUL.md`:
  - 32 Berührungspunkte bewertet
  - Zustandsmatrix
  - Ortsregeln
  - Textregeln
  - Machbarkeit
  - Phasen P0–P6
- Dazu ADR-020 (vorgeschlagen) und Ziel-Teil in `DESIGN_SYSTEM.md`. Code unverändert.
- Gefunden: Endet der Host die Sitzung, bekommt der Mitspieler nur eine Verlaufszeile und
  bleibt ohne Hinweis im Park (TP-09/TP-30).

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
