# Testen

## 1. Unit-Tests (immer)

Im Ordner `outputs/pc2-coop`:

```powershell
..\..\work\toolchain\python311\python.exe -c "import sys; sys.path.insert(0,'.'); import unittest; unittest.main(module=None, argv=['t','discover','-s','tests'])"
```

Das eingebettete Python hat kein pytest und ignoriert `PYTHONPATH` (deshalb `sys.path.insert`).
Einzelne Datei: `argv=['t','discover','-s','tests','-p','test_visitor_lua.py']`.
Doku-Prüfung allein: `python tools/check_docs.py`.

Lua-Tests bauen die Spiel-APIs nach (`tests/test_*_lua.py`). Was dort nicht nachgebaut ist,
ist **nicht** getestet – Status `Implemented-Untested`, bis es im Spiel lief.

## 2. Testkopie des Spiels

Eine vollständige Kopie des Spiels außerhalb des Repositorys (im Arbeitsordner
`work/coop-anything/local/test-install`, ~37 GB) mit `pc2coop-dev.flag` im Mod-Ordner.

**Vorher (Pflicht):**
1. Läuft das Spiel des Eigners? → **nicht testen** (gleiches Steam-Konto).
2. Freier Platz auf C: (`(Get-PSDrive C).Free`) – voll = Spiel endet mit 0xFDEAD.
3. Keine Maus-/Tastatur-Eingaben auf dem Desktop des Eigners, solange er am PC ist
   (`tools/game_input.ps1` nur, wenn er ausdrücklich weg ist). Nie im Hauptmenü klicken:
   „Fortsetzen“ lädt echte Spielstände.
4. Nie die Installation oder Spielstände des Eigners anfassen (ADR-008).

**Ablauf:**
```powershell
python tools/game_bot.py --game-dir <Testkopie> "new-test-park:[PC2CoopSync] sync:ready"
```
- Sobald der Prozess existiert, den Watchdog starten (Hintergrund):
  `tools/game_watchdog.ps1 -ProcessId <pid> -Log <scratch>/watchdog-<pid>.log`
  (stoppt nur das Spiel bei > 24 GB oder 45 s Hänger; Log zwischen Schritten lesen).
- Weitere Schritte: `game_bot.py --attach <pid> "<befehl>:<erwartete Logzeile>"`,
  Lua-Skripte: `python tools/qa_lua.py --mod-dir <Testkopie>/Win64/ovldata/PC2CoopProbe --pid <pid> skript.lua`.
- Bilder: `tools/screenshot_game.ps1` (PrintWindow, keine Eingabe).
- Log: `Win64\ovldata\PC2CoopProbe\pc2coop-diagnostic-<pid>.log` der Testkopie (enthält
  Steam-Namen und -IDs: nie committen).
- In kleinen Schritten testen. Nach einem Absturz des PCs zuerst Kernel-Power 41 lesen.

**Mitspieler nachstellen** (Lua-Skript in der Testkopie):
```lua
session._onNet("msg|777|hello|Vici|-1|live|" .. session.VERSION .. "|")
session.Answer("777", true)
-- danach pres/look/buy/... Zeilen wie in NETWORKING.md als msg|777|<zeile>
```

**Einstellungen und Spielstände der Testkopie sind die des Eigners** (gleiches Windows-Profil,
gleiches Steam-Konto; geprüft 2026-11-20):
- Grafik: `%LOCALAPPDATA%\Frontier Developments\Planet Coaster 2\Config_Local`.
- Spiel, Steuerung, Ton: `Saved Games\Frontier Developments\Planet Coaster 2\<Steam-ID>\Config`,
  über Steam Cloud abgeglichen.
- Die Testkopie schreibt dorthin auch `Saves\player` und Autosaves des Testparks (`*.prkauto2`).
- In der Testkopie deshalb **keine Einstellungen ändern**. Für Bilder in anderer Akzentfarbe,
  Farbenblind-Modus oder UI-Skalierung: `require("pc2coop.ui")._QaLook("akzent|thema|skalierung|reiter")`
  in einem QA-Skript. Akzent 0–8 und Thema 0–3 (0 Standard, 1 Protanopie, 2 Deuteranopie,
  3 Tritanopie) wie `ThemeConfig.js`, Skalierung 0.7–1.0 wie im Optionsmenü, Reiter 0 blendet
  unseren Bauleisten-Reiter aus, -1 lässt einen Wert. Das ändert nur die laufende HUD-Ansicht
  und speichert nichts.
- 1440p und 4K gehen hier nicht (Bildschirm 1080p, randlos). Die Mod-Oberfläche ist ganz in
  `rem` gebaut (außer Mauskoordinaten) und skaliert wie das Spiel mit `min(B/1920, H/1080)`.

## 3. Was nicht automatisch geprüft werden kann

Zwei echte PCs, echte Steam-Verbindung zwischen zwei Konten, echte Maus/Tasten, Controller.
Diese Tests macht der Eigner; Ergebnisse in `docs/changelog/DEVLOG.md` und den Status in der
Registry eintragen.

## 4. Nach einem Spiel-Update

1. Unit-Tests; dann Testkopie aktualisieren und `new-test-park` starten.
2. Log auf `hook-unavailable`, `tick-error`, `patch` Fehler prüfen.
3. Spiel-Module aus `docs/architecture/DEPENDENCIES.md` und die UI-Eingriffe aus
   `docs/ui-ux/COMPONENTS.md` prüfen (`bar-check`, `menu-test`, `ui-test`). Dazu die
   Spiel-Komponenten und CSS-Variablen aus `docs/ui-ux/NATIVE_UI.md`, die die Mod benutzt.
4. Spielbuild in `profiles/` ergänzen (FEAT-009).
