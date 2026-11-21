# Installation, Updates und Pakete

Alles, was die Mod auf den PC eines Spielers bringt, aktualisiert oder entfernt.
Vorlage je Funktion: Funktion · Technik · UI · Besonderheiten.

### FEAT-001 – Installer (`INSTALL.cmd`)
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-005, FEAT-002
- **Funktion:** Kopiert die Mod (`Main.ovl`, `Manifest.xml`, `PC2CoopDiagnostic.dll`) nach
  `<Spiel>\Win64\ovldata\PC2CoopProbe`. Findet den Steam-Spielordner selbst; sonst
  `INSTALL.cmd -GameDir "<Pfad>"`.
- **Technik:** `alpha-dist/INSTALL.cmd` ruft `alpha-dist/install.ps1 -Action Install`.
  `Install-IntoGame` prüft jede Datei gegen `payload-manifest.json` (SHA-256), schreibt ein
  Protokoll `.pc2coop-alpha-install.json` in `ovldata`, sichert überschriebene Dateien unter
  `.pc2coop-alpha-backups\<Zeit>` und rollt bei einem Fehler alles zurück. `Safe-ModPath`
  erlaubt nur `ACSE/` und `PC2CoopProbe/`. Läuft Planet Coaster 2, bricht er ab.
- **UI:** Konsolenfenster mit Meldungen auf Deutsch.
- **Besonderheiten:** Keine Administratorrechte, schreibt nur in `Win64\ovldata`. Eine
  fremde, veränderte Datei wird nie überschrieben („Andere Modversion vorhanden“). Prüft die
  EXE nicht mehr hart: unbekannter Build → nur Hinweis (FEAT-009).

### FEAT-002 – ACSE-Prüfung beim Installieren
- **Status:** Implemented · **Seit:** 1.12.2 (Nexus), für alle Pakete seit 1.12.3
- **Funktion:** Ohne Mod-Loader ACSE installiert der Installer nichts und sagt, wo es ACSE gibt.
  Ein vorhandenes ACSE (auch `ACSEDebug`) wird benutzt und nie verändert.
- **Technik:** `install.ps1`: `$bringsAcse` (Paket enthält `ACSE/*`) und `$hasAcse`
  (`ACSE\Main.ovl` oder `ACSEDebug`); `$acseOther` überspringt ACSE-Dateien.
- **UI:** Fehlermeldung „ACSE fehlt …“ im Installer-Fenster.
- **Besonderheiten:** Ein ACSE, das ein älteres PC2Coop-Paket installiert hat, bleibt beim
  Update erhalten (es steht danach nicht mehr im Protokoll und wird beim Deinstallieren
  nicht entfernt). Getestet mit nachgebautem Spielordner.

### FEAT-003 – Deinstallation (`UNINSTALL.cmd`)
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Entfernt genau die Dateien, die laut Protokoll von PC2Coop stammen.
- **Technik:** `install.ps1 -Action Uninstall` → `Uninstall-FromGame`: bricht ab, wenn eine
  Datei seit der Installation verändert wurde; löscht leere Ordner `PC2CoopProbe`/`ACSE`.
- **UI:** Konsolenfenster.
- **Besonderheiten:** Logs und Sicherungen bleiben liegen.

### FEAT-004 – Updater (`UPDATE.cmd`)
- **Status:** Implemented · **Seit:** 1.4.1 · **Hängt ab von:** FEAT-005
- **Funktion:** Holt die neueste Version von GitHub, prüft die Prüfsumme und installiert sie.
- **Technik:** `alpha-dist/update.ps1`: liest das Repository aus `update.json`
  (`release.json` beim Bauen), fragt `releases/latest` ab, lädt ZIP und `.sha256`, prüft
  SHA-256, entpackt nach `%LOCALAPPDATA%\PC2Coop\<Version>\PC2Coop` und startet dort den
  Installer. `-CheckOnly` zeigt nur die verfügbare Version und die Release-Notizen.
- **UI:** Konsolenfenster; zeigt „Installierte Paketversion“ und „Neue Version verfuegbar“.
- **Besonderheiten:** Spricht nur mit dem eigenen GitHub-Repository. Ohne `.sha256`-Asset
  verweigert er den Download. Nicht im Nexus-Paket (FEAT-006).

### FEAT-005 – GitHub-Release-Paket
- **Status:** Implemented · **Seit:** 1.4.1
- **Funktion:** Baut `PC2Coop-<Version>.zip` und `.sha256` für ein GitHub-Release.
- **Technik:** `tools/package_release.py`: prüft Build-Reports (OVL- und DLL-Hash, DLL-Quellen
  unverändert), legt Installer-Dateien, `update.json`, `payload/PC2CoopProbe`, Lizenz und den
  eigenen Quellcode (`source/`) ins ZIP, schreibt `payload-manifest.json` und prüft das ZIP.
- **UI:** –
- **Besonderheiten:** Der Ablauf eines Releases steht in `docs/development/RELEASE.md`.

### FEAT-006 – Nexus-Paket ohne Skripte
- **Status:** Implemented · **Seit:** 1.12.3 (ohne Skripte seit 1.12.3-Neuauflage)
- **Funktion:** `PC2Coop-<Version>-nexus.zip` zum Hineinkopieren in den Spielordner.
- **Technik:** `package_release.py --nexus` → Funktion `nexus()`: nur
  `Win64/ovldata/PC2CoopProbe/*`, `PC2Coop-LIESMICH.txt` (umgeschrieben über `NEXUS_README`),
  `PC2Coop-LICENSE.txt`. `check()` bricht ab, wenn `.cmd/.ps1/.exe/...` oder ACSE im ZIP wären.
- **UI:** –
- **Besonderheiten:** Grund: Nexus stellte ein Paket mit PowerShell-Skripten unter Quarantäne
  (ADR-010). Kein Updater: Updates kommen über Nexus.

### FEAT-007 – Keine ACSE-Dateien in Paketen
- **Status:** Implemented · **Seit:** 1.12.3
- **Funktion:** Pakete enthalten weder ACSE noch dessen Quellcode; Spieler laden ACSE selbst.
- **Technik:** `package_release.py` kennt keine ACSE-Quellen mehr; `check()` verbietet
  `/ACSE/` im ZIP. `install.ps1` verlangt ACSE (FEAT-002).
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
