# ADR-023: Eine ZIP mit Setup.exe für GitHub, Nexus und Vortex

- **Status:** Teilweise ersetzt durch ADR-024 (Setup ist ein eigener Download, Nexus nimmt keine .exe)
- **Datum:** 2026-11-22
- **Betrifft:** FEAT-011, FEAT-012, FEAT-001, FEAT-004, FEAT-005, FEAT-006, ADR-009, ADR-010

## Kontext

Bis 2.0.0 gab es zwei Pakete: für GitHub mit INSTALL.cmd und UPDATE.cmd (PowerShell), für Nexus
eins ohne Skripte zum Hineinkopieren, weil Nexus das Skript-Paket unter Quarantäne stellte
(ADR-010). Ein Tester scheiterte am Kopieren von Hand. Vortex hatte beim Eigner PC2Coop
heruntergeladen, aber nie in den Spielordner gelegt. Der Eigner will eine Datei, die jeder ohne
Vorwissen installieren kann, auf beiden Plattformen gleich.

## Entscheidung

- Ein Paket `PC2Coop-<Version>.zip`: PC2Coop-Setup.exe, eine kurze zweisprachige Anleitung,
  Lizenz, `payload-manifest.json` und die Mod unter `Mod/PC2CoopProbe`. Keine Skripte, kein
  ACSE, kein Quellcode (der liegt auf GitHub).
- Setup ist ein kleines C#-Programm für das .NET Framework, das bei Windows dabei ist, gebaut
  mit dem csc.exe von Windows (`tools/build_setup.py`). Fenster auf Deutsch oder Englisch nach
  der Windows-Sprache, Befehlszeile für Tests.
- Updates: Setup fragt GitHub nach dem neuesten Release, lädt ZIP und `.sha256`, prüft beide
  und kopiert nur die Mod-Dateien heraus. Ein heruntergeladenes Programm startet es nie.
- Vortex: Die Mod liegt in `Mod/`, damit der „ACSE Mod“-Installer der Planet-Coaster-2-
  Erweiterung genau `PC2CoopProbe` nach `Win64\ovldata` legt. Setup erkennt eine
  Vortex-Installation und fasst sie nicht an.
- ACSE bleibt draußen (ADR-009). ACSE steht unter GPL-3 und dürfte unverändert mit Lizenz und
  Quellenhinweis mitgeliefert werden; der Eigner fragt das ACSE-Team vorher. Bis dahin bietet
  Setup bei fehlendem ACSE die Seite bei Nexus an.

## Alternativen

- Zwei Pakete wie bisher: zwei Wege, zwei Anleitungen, und das Kopieren von Hand geht schief.
- Wieder PowerShell-Skripte: Nexus und Virenscanner stufen sie als verdächtig ein.
- Mod-Dateien in die EXE einbetten: Setup liefe auch ohne Entpacken, aber eine EXE, die eine DLL
  auspackt, sieht für Virenscanner wie ein Dropper aus, und Vortex bräuchte den Ordner trotzdem.
- FOMOD für Vortex: nicht nötig, die Erweiterung sortiert den Ordner mit `Main.ovl` richtig ein.
- Installer-Baukästen (Inno Setup, MSI): neue Software, größere Dateien, mehr Fehlalarme.

## Begründung

Eine Datei, ein Doppelklick, eine Anleitung von zehn Zeilen. Setup prüft, was beim Kopieren von
Hand schiefgeht (falscher Ordner, fehlendes ACSE, laufendes Spiel, beschädigte oder nicht
entpackte Dateien), und sagt es in einem Satz.

## Konsequenzen

- Setup ist nicht signiert: Windows SmartScreen fragt beim ersten Start. Eine Code-Signatur kann
  später dazukommen (ROADMAP).
- Ein altes UPDATE.cmd (bis 2.0.0) kann 2.1.0 nicht installieren; einmal von Hand Setup
  starten, danach aktualisiert Setup selbst.
- `tools/package_release.py` baut nur noch ein Paket; es gibt keinen Schalter `--nexus` mehr.
- Ob Nexus die EXE ohne Quarantäne annimmt, zeigt erst der Upload.
