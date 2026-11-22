# ADR-010: Nexus-Paket ohne Skripte, DLL mit Versionsangaben

- **Status:** Teilweise ersetzt durch ADR-023 (ein Paket mit Setup.exe statt zwei Paketen; die DLL-Versionsangaben gelten weiter)
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-006, FEAT-008

## Kontext

Nexus stellte das Paket als „suspicious“ in Quarantäne. Heuristiken reagieren auf `.cmd`/`.ps1`
und auf eine DLL ohne Versionsangaben, die Tasten abfragt (`GetAsyncKeyState`).

## Entscheidung

Das Nexus-Zip enthält nur `Win64\ovldata\PC2CoopProbe`, Readme und Lizenz (zum Kopieren in
den Spielordner). Die DLL bekommt eine VERSIONINFO-Ressource (`native/version.rc`) aus
`Session.VERSION`. Das GitHub-Paket behält Installer und Updater.

## Alternativen

- Ein Paket für beide Orte.
- DLL signieren (kostet Zertifikat).

## Begründung

Weniger Fehlalarme ohne Funktionsverlust für Nexus-Nutzer (Updates kommen dort von Nexus).

## Konsequenzen

- Zwei Pakete pro Release (`package_release.py`, `--nexus`).
- Quarantäne muss trotzdem vom Eigner bei Nexus geklärt werden.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
