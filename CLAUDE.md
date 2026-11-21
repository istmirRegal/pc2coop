# CLAUDE.md – Einstieg für KI und Entwickler

**PC2Coop** ist eine Mod für Planet Coaster 2: mehrere Steam-Freunde bauen live im selben
Park und besuchen ihn gemeinsam. Sie läuft komplett im Spiel (Lua über ACSE, Gameface-UI,
kleine DLL für Steam). Version: `Session.VERSION` in
`probe/PC2CoopProbe/Main/pc2coop/session.lua`. Öffentlich auf GitHub, Spieler-Texte auf Deutsch.

## Zuerst lesen

1. `docs/README.md` – Index der ganzen Dokumentation.
2. `docs/project/PROJECT_OVERVIEW.md` – was, für wen, Stand.
3. `docs/project/FEATURES.md` – **jede** Funktion mit ID, Status, Datei.
4. `docs/architecture/SYSTEM_ARCHITECTURE.md` – Aufbau und „darf nie brechen“.
5. `docs/development/AI_WORKFLOW.md` – **Pflicht-Ablauf für jede Änderung.**
6. `docs/changelog/DEVLOG.md` (oben) und `docs/project/ROADMAP.md` – letzte Änderungen, offene Punkte.

## Pflicht-Ablauf (Kurzform)

1. **Kontext verstehen:** Registry, Bereichsdatei, ADRs, DEVLOG lesen – dann Code.
2. **Auswirkungen prüfen:** `docs/architecture/DEPENDENCIES.md`, Netzformat, UI, Sicherheit.
3. **Umsetzen:** `docs/development/CODING_STANDARDS.md`, mit Unit-Test.
4. **Doku aktualisieren (Pflicht):** Registry + Feature-Abschnitt, NETWORKING, UI_INVENTORY,
   ADR bei Entscheidungen, CHANGELOG/DEVLOG. Entfernte Funktionen bleiben dokumentiert
   (Status `Removed`/`Replaced`).
5. **Validieren:** alle Tests inkl. `tests/test_docs.py` (`tools/check_docs.py`), Testkopie
   wenn möglich, Zeilenenden-Diff, Datenschutz-Blick.

Eine Aufgabe ist erst fertig, wenn Code **und** Doku stimmen. Bei Widerspruch gilt der Code
(Git ist die technische Wahrheit) – dann die Doku korrigieren.

## Regeln, die immer gelten

- **Fragen vor:** Software installieren, große Downloads, Schreiben außerhalb des
  Arbeitsordners, Konten des Eigners benutzen (Steam, GitHub, Nexus, Discord), jemanden
  kontaktieren, **irgendetwas veröffentlichen** (push, tag, Release, Upload). Commits lokal sind ok.
- **Nie** die Spielinstallation oder Spielstände des Eigners anfassen. Getestet wird nur in der
  Testkopie, nur wenn das Spiel des Eigners nicht läuft, mit Watchdog, ohne Maus/Tastatur auf
  seinem Desktop (`docs/development/TESTING.md`).
- **Nichts Privates ins Repository:** keine Spieldateien/Assets, keine Tokens/Cookies, keine
  echten Namen oder E-Mails, keine lokalen Pfade mit Benutzernamen, keine Logs (enthalten Steam-IDs).
- **Nichts aus dem Netz wird ausgeführt** (ADR-005); jede Netz-Eingabe wird geprüft.
- **Jeder Spiel-API-Aufruf in `pcall`** – die Mod darf das Spiel nie abstürzen lassen.
- **Host-Autorität** (ADR-003): Reihenfolge, Konflikte, Geld nur beim Host.
- **Keine ACSE-Dateien in Paketen** (ADR-009); Nexus-Paket ohne Skripte (ADR-010).
- **Einzelspieler-Funktionen nicht erweitern**; Spielfunktionen nur technisch für Multiplayer
  nutzen (ADR-014). Neue Funktionen müssen für Mitspieler etwas bringen.
- **Zeilenenden erhalten** (ADR-017): `git diff --stat` mit/ohne `--ignore-cr-at-eol` vergleichen.
- Spieler-Texte Deutsch, „du“, kurz; Spiel-Komponenten bekommen `literal()` (ADR-018).

## Wo was liegt

| Was | Wo |
|---|---|
| Lua-Module | `probe/PC2CoopProbe/Main/pc2coop/` (Übersicht: `docs/architecture/CODE_STRUCTURE.md`) |
| Einstieg im Spiel | `probe/PC2CoopProbe/Main/database/pc2coopprobeluadatabase.lua`, `probe/PC2CoopProbe/Main/managers/pc2coopqa.lua` |
| Oberfläche | `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js` |
| DLL | `native/` |
| Nachrichten | `docs/architecture/NETWORKING.md` |
| Bedienelemente | `docs/ui-ux/UI_INVENTORY.md` |
| Entscheidungen | `docs/decisions/` |
| Pakete, Installer | `alpha-dist/`, `tools/package_release.py` |
| Tests | `tests/` |

## Befehle

Im Ordner `outputs/pc2-coop` (Werkzeuge liegen im Arbeitsordner unter `work/toolchain/`):

```powershell
..\..\work\toolchain\python311\python.exe -c "import sys; sys.path.insert(0,'.'); import unittest; unittest.main(module=None, argv=['t','discover','-s','tests'])"
..\..\work\toolchain\python311\python.exe tools\check_docs.py
```

Git braucht hier `git -c safe.directory=<pfad>` (Ordner gehört einem anderen Windows-Konto).
Bauen und Release: `docs/development/RELEASE.md`. Testkopie: `docs/development/TESTING.md`.

## Zusammenarbeit mit dem Eigner

- Der Eigner leitet das Projekt und gibt die Richtung vor (`docs/KONZEPT.md`, ROADMAP).
  Er spricht Deutsch.
- Große Aufträge: alles bauen und mit Unit-Tests absichern, den Spieltest am Ende machen,
  dann beheben, was er zeigt.
- Ehrlich berichten: was im Spiel geprüft ist und was nur in Unit-Tests.
- UX-Overhaul: `docs/ui-ux/UX_OVERHAUL.md` (gebaut bis P6-Funde, Abnahme auf zwei PCs offen),
  Maßstab ist das Spiel selbst (`docs/ui-ux/NATIVE_UI.md`, ADR-020). Neue Oberfläche benutzt Variablen,
  `rem` und Bausteine des Spiels.
