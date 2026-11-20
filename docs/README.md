# Dokumentation PC2Coop

Wissensbasis des Projekts. Einstieg für KI: `CLAUDE.md` im Repository-Wurzelordner.
Regeln für die Pflege: `docs/development/AI_WORKFLOW.md`. Prüfung: `tools/check_docs.py`.

## Projekt

| Datei | Inhalt |
|---|---|
| [project/PROJECT_OVERVIEW.md](project/PROJECT_OVERVIEW.md) | Was PC2Coop ist, für wen, Stand, Grenzen |
| [project/FEATURES.md](project/FEATURES.md) | **Feature-Registry**: alle Funktionen mit ID, Status, Version |
| [project/ROADMAP.md](project/ROADMAP.md) | Offene Punkte, Pläne, Ungetestetes |
| [project/GLOSSARY.md](project/GLOSSARY.md) | Begriffe |

## Funktionen (je Bereich, jede Funktion als `### FEAT-nnn`)

| Datei | IDs |
|---|---|
| [features/installation-and-updates.md](features/installation-and-updates.md) | FEAT-001–010 |
| [features/session-and-lobby.md](features/session-and-lobby.md) | FEAT-020–048 |
| [features/build-sync.md](features/build-sync.md) | FEAT-060–081 |
| [features/presence.md](features/presence.md) | FEAT-090–099 |
| [features/ui-integration.md](features/ui-integration.md) | FEAT-110–118 |
| [features/team.md](features/team.md) | FEAT-130–147 |
| [features/visitor-mode.md](features/visitor-mode.md) | FEAT-160–174 |
| [features/native-dll.md](features/native-dll.md) | FEAT-190–199 |
| [features/dev-and-qa.md](features/dev-and-qa.md) | FEAT-210–221 |

## Architektur

| Datei | Inhalt |
|---|---|
| [architecture/SYSTEM_ARCHITECTURE.md](architecture/SYSTEM_ARCHITECTURE.md) | Schichten, Lebenszyklus, Rollen, „darf nie brechen“ |
| [architecture/CODE_STRUCTURE.md](architecture/CODE_STRUCTURE.md) | Dateien, Module, Funktionen, Werkzeuge, Tests |
| [architecture/NETWORKING.md](architecture/NETWORKING.md) | Alle Nachrichten, ops-Zeilen, DLL-Befehle/-Ereignisse, sync-Zeilen |
| [architecture/DATA_FLOW.md](architecture/DATA_FLOW.md) | Wege einer Änderung, Beitritt, Kauf, gespeicherte Dateien |
| [architecture/DEPENDENCIES.md](architecture/DEPENDENCIES.md) | Externe und interne Abhängigkeiten, kritische Ketten |

## UI/UX

| Datei | Inhalt |
|---|---|
| [ui-ux/UI_INVENTORY.md](ui-ux/UI_INVENTORY.md) | Jedes Bedienelement, jede UI-Aktion |
| [ui-ux/NAVIGATION.md](ui-ux/NAVIGATION.md) | Wege zwischen den Ansichten |
| [ui-ux/COMPONENTS.md](ui-ux/COMPONENTS.md) | Komponenten, Zustandsfelder, Eingriffe in Spiel-UI |
| [ui-ux/DESIGN_SYSTEM.md](ui-ux/DESIGN_SYSTEM.md) | Farben, Schrift, Maße, Sprache |
| [ui-ux/UX_AUDIT.md](ui-ux/UX_AUDIT.md) | Befunde für das UX-Overhaul |

## Entscheidungen

[decisions/README.md](decisions/README.md) – ADR-001 bis ADR-019 mit Vorlage.

## Entwicklung

| Datei | Inhalt |
|---|---|
| [development/AI_WORKFLOW.md](development/AI_WORKFLOW.md) | Pflicht-Ablauf für jede Änderung |
| [development/CODING_STANDARDS.md](development/CODING_STANDARDS.md) | Code-Regeln Lua/JS/C++/Python |
| [development/TESTING.md](development/TESTING.md) | Unit-Tests, Testkopie, Spiel-Update |
| [development/RELEASE.md](development/RELEASE.md) | Version, Bauen, Pakete, Veröffentlichen |

## Änderungen

| Datei | Für |
|---|---|
| [changelog/CHANGELOG.md](changelog/CHANGELOG.md) | Spieler |
| [changelog/DEVLOG.md](changelog/DEVLOG.md) | Entwickler (inkl. bekannte Probleme) |

## Hintergrund (ältere Dokumente)

| Datei | Inhalt | Stand |
|---|---|---|
| [KONZEPT.md](KONZEPT.md) | Konzept des Mehrspieler-Erlebnisses, Reihenfolge | 2026-11-18, Richtung gültig |
| [COOP_DESIGN.md](COOP_DESIGN.md) | Ursprüngliche Anforderungen (u. a. drei Spieler) | 2026-11-01 |
| [BRIDGE.md](BRIDGE.md) | Wie die DLL geladen wird | früh, Grundlage gültig |
| [RESEARCH.md](RESEARCH.md) | Recherche zu anderen Projekten | 2026-11-01 |
| [VALIDATION.md](VALIDATION.md) | Früher Prüfstand | 2026-11-01, historisch |
| [NEXT.md](NEXT.md) | Früher Meilensteinplan | historisch, ersetzt durch ROADMAP.md |
| [sources.lock.json](sources.lock.json) | Quellen der Recherche | – |
