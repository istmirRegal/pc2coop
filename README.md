# PC2Coop – Planet Coaster 2 live zusammen bauen

Inoffizielle Multiplayer-Mod für Planet Coaster 2: mehrere Spieler bauen gleichzeitig im
selben Park, über Steam-Einladungen, ohne Portfreigabe oder Zusatzprogramm.

## Für Spieler

0. Den Mod-Loader ACSE für Planet Coaster 2 installieren (Nexus Mods), falls noch nicht
   vorhanden. Er ist nicht im PC2Coop-Paket.
1. Neueste ZIP unter [Releases](../../releases/latest) herunterladen und entpacken.
2. Planet Coaster 2 beenden, `INSTALL.cmd` doppelklicken.
3. Spiel starten: Hauptmenü → **Multiplayer** → **Lobby erstellen**, Steam-Freunde einladen.
   In der Lobby wählt der Host, wo ihr spielt (gespeicherter Park, neuer Sandbox-Park,
   Franchise) – alle sehen die Auswahl; nach „Park öffnen“ lädt er bei allen automatisch. Im Park geht es auch direkt:
   Pausemenü → **Multiplayer** (F7) → **Diesen Park hosten**.
4. Neue Version: Spiel beenden, `UPDATE.cmd` doppelklicken.

Alle Mitspieler brauchen dieselbe Mod-Version und dieselbe Spielversion
(getestet mit Steam-Build 26494896). Details, Stand der Synchronisation und bekannte Lücken:
[alpha-dist/LIESMICH.txt](alpha-dist/LIESMICH.txt).

## Wie es funktioniert

- Läuft komplett im Spiel: Lua-Mod (über [ACSE](https://github.com/OpenNaja/ACSE)) plus
  eine kleine DLL für Steam-Lobby, Einladungen und Nachrichten (Steam Networking Messages).
- Der Host ist maßgeblich: er ordnet alle Änderungen, prüft gleichzeitige Bearbeitung
  desselben Objekts und überträgt beim Beitritt seinen Park.
- Bauänderungen werden aus den Editor-Aufrufen des Spiels mitgeschnitten und bei den
  anderen genauso wieder abgespielt (Szenerie, Gelände, Wege, Fahrgeschäfte, ...).
- Die Oberfläche (Spielerleiste, Lobby, Menüeinträge) ist in die Gameface-UI des Spiels
  eingebaut.

## Sicherheit

- Sitzungen sind nur für Steam-Freunde des Hosts sichtbar; die Mod tritt nur Sitzungen von
  Steam-Freunden bei und fragt nach, wenn eine Sitzung per Startparameter statt per
  angeklickter Einladung kommt.
- Der Host lässt Freunde zu, die er nicht selbst eingeladen hat, bevor sie den Park bekommen.
- In der Lobby sehen Mitspieler DLC-Liste, Mod-Ordnernamen und Steam-Profilbild der anderen.
- Aus dem Netz werden genau zwei Dateien geschrieben (der Park des Hosts), nur vom Host,
  mit festen Namen und Größenprüfung; sie werden nach dem Laden gelöscht.
- Nachrichten anderer Spieler werden nie als Code ausgeführt: Bauaktionen laufen über eine
  feste Liste erlaubter Spielfunktionen mit geprüften Argumenten.
- Der Befehlskanal für automatische Tests ist nur aktiv, wenn `pc2coop-dev.flag` im
  Mod-Ordner liegt; ausgelieferte Pakete enthalten die Datei nicht.
- `UPDATE.cmd` lädt nur aus diesem Repository und prüft die SHA-256-Prüfsumme. Wer das
  Repository veröffentlicht, sollte sein GitHub-Konto mit 2FA schützen.

Sicherheitslücke gefunden? Bitte als Issue melden (ohne Log-Dateien mit fremden Steam-IDs).

## Entwickeln

- **Dokumentation:** `docs/README.md` (Funktionen, Architektur, Entscheidungen, UI);
  Regeln für KI und Entwickler: `CLAUDE.md`.
- `probe/PC2CoopProbe/` – Mod-Quellcode (Lua) und UI (`ui/UIGameface/js/pc2coop`).
- `native/` – DLL (C++), gebaut mit `tools/build_native.py` (MSVC Build Tools).
- `tools/build_ui.py`, `tools/build_probe.py` (Cobra Tools) – Mod-Paket bauen.
- `tools/package_release.py` – Spieler-ZIP plus `.sha256` für ein GitHub-Release.
- `tests/` – Tests gegen nachgebildete Spiel-APIs (`python -m pytest tests`; die Lua-Tests
  brauchen `lupa`).
- `tools/game_bot.py` – steuert eine Testkopie des Spiels über feste QA-Befehle.

Release: siehe `docs/development/RELEASE.md` (alle Versionsstellen, Bauen, beide Pakete).

## Lizenz

Eigener Code: MIT ([LICENSE](LICENSE)). ACSE ist nicht enthalten (eigener Download, eigene Lizenz).
Keine Spieldateien enthalten. Planet Coaster 2 ist eine Marke von Frontier Developments;
dieses Projekt ist nicht mit Frontier verbunden.
