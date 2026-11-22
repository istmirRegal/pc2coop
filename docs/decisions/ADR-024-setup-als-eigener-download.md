# ADR-024: Setup als eigener Download, die ZIP ohne Programme

- **Status:** Akzeptiert
- **Datum:** 2026-11-22
- **Betrifft:** FEAT-011, FEAT-012, ADR-023, ADR-010

## Kontext

ADR-023 legte PC2Coop-Setup.exe in die eine ZIP für GitHub, Nexus und Vortex. Nexus Mods nimmt
aber keine .exe an (Eigner, Upload 2026-11-22).

## Entscheidung

- Die ZIP (`PC2Coop-<Version>.zip`, gleich auf GitHub und Nexus) enthält nur Anleitung, Lizenz,
  `payload-manifest.json` und `Mod/PC2CoopProbe` – als Programm nur die DLL der Mod.
- PC2Coop-Setup.exe ist ein eigener Release-Download auf GitHub. Liegt kein Paket daneben,
  holt es das neueste Release von GitHub (dieselbe Prüfung wie beim Update) und installiert es.
- Der Aufbau unter `PC2Coop/` bleibt wie in 2.1.0, damit Setup 2.1.0 weiter aktualisieren kann.

## Alternativen

- EXE in die ZIP für GitHub, eine zweite ZIP ohne EXE für Nexus: zwei Pakete (das wollte der
  Eigner nicht).
- Mod-Dateien in die EXE einbetten: sieht für Virenscanner wie ein Dropper aus.

## Konsequenzen

- Nexus-Spieler installieren mit Vortex oder von Hand; Setup steht in der Anleitung und auf
  GitHub.
- Ein Release hat drei Dateien: ZIP, `.sha256`, PC2Coop-Setup.exe.
