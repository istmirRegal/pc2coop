# Installation, Updates und Pakete

Alles, was die Mod auf den PC eines Spielers bringt, aktualisiert oder entfernt.
Vorlage je Funktion: Funktion · Technik · UI · Besonderheiten.

### FEAT-001 – Installer (INSTALL.cmd)
- **Status:** Replaced (durch FEAT-011) · **Seit:** 1.4.1 · **Bis:** 2.0.0
- **Funktion:** Kopierte die Mod nach `<Spiel>\Win64\ovldata\PC2CoopProbe` (Konsolenfenster).
- **Technik:** INSTALL.cmd → install.ps1 (beide entfernt): Prüfung gegen `payload-manifest.json`,
  Protokoll `.pc2coop-alpha-install.json`, Sicherungen, Rollback.
- **Warum ersetzt:** PowerShell-Skripte stuften Nexus und Virenscanner als verdächtig ein
  (ADR-010), also gab es ein zweites Paket zum Kopieren von Hand, an dem Spieler scheiterten.
  Setup übernimmt Protokoll und Sicherungen unverändert (ADR-023).

### FEAT-002 – ACSE-Prüfung beim Installieren
- **Status:** Implemented · **Seit:** 1.12.2 (Nexus), für alle Pakete seit 1.12.3
- **Funktion:** Ohne Mod-Loader ACSE installiert Setup nichts, sagt es und bietet die
  Download-Seite bei Nexus an. Ein vorhandenes ACSE (auch `ACSEDebug`) wird benutzt und nie
  verändert.
- **Technik:** `setup/PC2CoopSetup.cs`, Funktion Install: `ACSE\Main.ovl` oder `ACSEDebug`
  müssen da sein (Code 3 in der Befehlszeile).
- **UI:** Zeile „ACSE fehlt – PC2Coop braucht diesen Mod-Loader“ mit Knopf „Herunterladen“.
- **Besonderheiten:** ACSE-Einträge, die ein altes Paket ins Protokoll schrieb, bleiben dort
  und werden nie entfernt. Test: `tests/test_setup_exe.py`.

### FEAT-003 – Deinstallation (UNINSTALL.cmd)
- **Status:** Replaced (durch FEAT-011, Knopf „Entfernen“) · **Seit:** 1.4.1 · **Bis:** 2.0.0
- **Funktion:** Entfernte die Dateien laut Protokoll (install.ps1, entfernt).

### FEAT-004 – Updater (UPDATE.cmd)
- **Status:** Replaced (durch FEAT-011, Knopf „Nach Update suchen“) · **Seit:** 1.4.1 · **Bis:** 2.0.0
- **Funktion:** Holte die neueste Version von GitHub, prüfte die Prüfsumme und startete den
  Installer der neuen Version (update.ps1, entfernt).
- **Besonderheiten:** Ein altes UPDATE.cmd findet 2.1.0, bricht aber ab, weil install.ps1 im
  Paket fehlt; die bisherige Version bleibt installiert. Einmal von Hand Setup starten.

### FEAT-005 – GitHub-Release-Paket
- **Status:** Replaced (durch FEAT-012) · **Seit:** 1.4.1 · **Bis:** 2.0.0
- **Funktion:** ZIP mit Installer-Skripten, Mod und Quellcode für GitHub.

### FEAT-006 – Nexus-Paket ohne Skripte
- **Status:** Replaced (durch FEAT-012) · **Seit:** 1.12.3 · **Bis:** 2.0.0
- **Funktion:** ZIP mit `Win64\ovldata\PC2CoopProbe` zum Kopieren in den Spielordner.
- **Warum ersetzt:** Kopieren von Hand ging schief; Vortex sortierte es beim Eigner nie ein.

### FEAT-007 – Keine ACSE-Dateien in Paketen
- **Status:** Implemented · **Seit:** 1.12.3
- **Funktion:** Pakete enthalten weder ACSE noch dessen Quellcode; Spieler laden ACSE selbst.
- **Technik:** `package_release.py` kennt keine ACSE-Quellen mehr; `check()` verbietet
  `/ACSE/` im ZIP. Setup verlangt ACSE (FEAT-002).
- **Besonderheiten:** Wunsch des Projekteigners (Lizenzen/Rechte, ADR-009). Die alten
  Release-Dateien v1.4.1–v1.12.2 mit ACSE wurden von GitHub gelöscht.

### FEAT-008 – Versionsangaben in der DLL
- **Status:** Implemented · **Seit:** 1.12.3
- **Funktion:** Windows zeigt bei `PC2CoopDiagnostic.dll` Produkt, Beschreibung, Version, Lizenz.
- **Technik:** `native/version.rc` + `tools/build_native.py` (erzeugt `pc2coop_version.h` aus
  `Session.VERSION`, baut `version.res` mit `rc.exe`).
- **Besonderheiten:** Soll Virenscanner-Fehlalarme verringern. DLL bei jedem Release neu bauen.

### FEAT-009 – Spielbuild-Erkennung
- **Status:** Implemented · **Seit:** 1.4.2
- **Funktion:** Die Mod sucht die benötigte Spielroutine selbst; fehlt sie, bleibt der
  Multiplayer aus und das Log enthält „game build not supported“.
- **Technik:** DLL sucht die String-Routine des Spiels per Byte-Muster (`native/string_probe.cpp`, genau ein Treffer nötig);
  `tools/scan_exe.py` prüft eine EXE mit denselben Regeln. Getestet: Steam-Build 26255360 und
  26494896 (Update vom 2026-11-17; RVA `0x1e29f50` bzw. `0x1e2d910`).
- **Besonderheiten:** Spieler mit unterschiedlicher Spielversion werden abgewiesen (FEAT-029).

### FEAT-010 – Startskript der Python-Alpha (`START.cmd`)
- **Status:** Legacy · **Seit:** vor 1.4.1
- **Funktion:** Startete den Python-Controller (`pc2coop.coop`) der frühen LAN-Alpha.
- **Technik:** `alpha-dist/START.cmd`, `alpha-dist/start.ps1`; braucht `runtime\python.exe`.
- **Besonderheiten:** Wird nicht mehr ausgeliefert (nicht in `INSTALLER_FILES`). Nicht ändern,
  sondern bei Gelegenheit samt FEAT-218 entfernen (dann Status `Removed`).

### FEAT-011 – PC2Coop-Setup.exe
- **Status:** Implemented · **Seit:** 2.1.0 · **Hängt ab von:** FEAT-012, FEAT-002
- **Funktion:** Doppelklick: ein kleines Fenster zeigt Spielordner, ACSE und installierte
  Version. „Installieren“/„Aktualisieren auf x“, „Nach Update suchen“, „Entfernen“,
  „Spiel starten“. Deutsch, wenn Windows deutsch ist, sonst Englisch.
- **Technik:** `setup/PC2CoopSetup.cs` (C# 5, .NET Framework 4.x, das bei Windows dabei ist),
  gebaut mit `tools/build_setup.py` (csc.exe von Windows, Manifest `setup/app.manifest`:
  asInvoker, DPI). Spielordner: gemerkt in `%LOCALAPPDATA%\PC2Coop\setup.json`, sonst Steam
  (Registry, `libraryfolders.vdf`, `appmanifest_2688950.acf`), sonst Ordnerauswahl.
  Installieren: jede Datei gegen `payload-manifest.json` (SHA-256) prüfen, ersetzte Dateien nach
  `.pc2coop-alpha-backups\<Zeit>` sichern (die neuesten drei bleiben), bei Fehler zurückrollen,
  Protokoll `.pc2coop-alpha-install.json` mit Version schreiben (Format wie install.ps1, alte
  Protokolle werden übernommen). Eine Datei, die die alte Version besaß und die neue nicht hat,
  wird entfernt. Update: `releases/latest` des Repositorys aus `release.json`, nur Download-Links
  dieses Repositorys, ZIP und `.sha256` prüfen, nur `PC2Coop/payload-manifest.json` und
  `PC2Coop/Mod/PC2CoopProbe/<Datei>` entpacken (jeder andere Eintrag mit `..`, `:` oder außerhalb
  von `PC2Coop/` bricht ab), dann wie Installieren. Ein heruntergeladenes Programm wird nie
  gestartet. Entfernen: die drei Mod-Dateien und Protokoll-Einträge; Logs, Park-Notizen und ACSE
  bleiben.
- **UI:** Fenster mit den Zeilen Spiel/ACSE/PC2Coop, Knöpfen und einer Statuszeile. Befehlszeile
  für Tests: `--install`, `--uninstall`, `--status`, `--check-update`, `--update` mit `--game`,
  `--source`, `--api`, `--lang`, `--log`; Ausgabe `result=…`, Codes 0 ok, 1 Fehler,
  2 Spiel läuft, 3 ACSE fehlt, 4 Vortex verwaltet die Mod, 5 kein Spiel, 6 keine Schreibrechte,
  7 nicht entpackt/Paket beschädigt, 10 schon aktuell.
- **Besonderheiten:** Fasst eine Vortex-Installation nicht an (Hardlinks oder
  `vortex.deployment*.json` mit PC2CoopProbe) und sagt, dass Vortex sie verwaltet. Nicht
  entpackt gestartet (Windows führt die EXE aus der ZIP-Ansicht allein aus): Hinweis „zuerst
  entpacken“. Nicht signiert: SmartScreen fragt beim ersten Start. Läuft ohne
  Administratorrechte; fehlen Schreibrechte, rät die Meldung zu „Als Administrator ausführen“.
  Tests: `tests/test_setup_exe.py` (nur nachgebaute Spielordner, eigenes LOCALAPPDATA/TEMP,
  GitHub nachgestellt), `tests/test_package_release.py`.

### FEAT-012 – Eine ZIP für GitHub, Nexus und Vortex
- **Status:** Implemented · **Seit:** 2.1.0 · **Entscheidung:** ADR-023
- **Funktion:** Dieselbe `PC2Coop-<Version>.zip` (+ `.sha256` auf GitHub) für alle Wege:
  Setup, Vortex oder von Hand kopieren.
- **Technik:** `tools/package_release.py`: `PC2Coop/PC2Coop-Setup.exe`,
  `PC2Coop/LIES MICH - READ ME.txt` (aus `alpha-dist/LIESMICH.txt`, `{version}` ersetzt, UTF-8
  mit BOM, CRLF), `PC2Coop/LICENSE.txt`, `PC2Coop/payload-manifest.json` (Version, getesteter
  Steam-Build und EXE-Hash, SHA-256 jeder Mod-Datei), `PC2Coop/Mod/PC2CoopProbe/*`. `check()`:
  alles unter `PC2Coop/`, kein ACSE, keine Skripte (`.cmd`, `.ps1`, `.bat`, `.vbs`, `.js`, `.py` …),
  als Programme genau Setup und die DLL. Prüft vorher die Build-Berichte von OVL, DLL und Setup.
- **Besonderheiten:** Der Ordner `Mod/` ist Absicht: Die Planet-Coaster-2-Erweiterung von Vortex
  nimmt mit ihrem „ACSE Mod“-Installer den Ordner mit `Main.ovl` und nur dessen Geschwister und
  legt sie nach `Win64\ovldata`. Mit `Win64/` im ZIP hätte ihr „Root“-Installer Setup und Anleitung
  in den Spielordner gelegt. Nachgebildet und geprüft in `tests/test_package_release.py`.

