# Release

Öffentlich auf GitHub (`release.json`: Repository); Spieler aktualisieren mit PC2Coop-Setup.exe
(„Nach Update suchen“), das `releases/latest` liest und zwei Dateien braucht: `PC2Coop-<x.y.z>.zip`
und `PC2Coop-<x.y.z>.zip.sha256`. Der Eigner lädt dieselbe ZIP selbst bei Nexus hoch.

**Jeder Schritt, der etwas veröffentlicht (push, tag, Release, Upload), nur nach Rückfrage.**

## 1. Version erhöhen (alle Stellen)

| Datei | Stelle |
|---|---|
| `probe/PC2CoopProbe/Main/database/pc2coopprobeluadatabase.lua` | `probeVersion` |
| `probe/PC2CoopProbe/Main/pc2coop/session.lua` | `Session.VERSION` (Host lehnt andere Versionen ab) |
| `tools/cobra_worker.py` | `probe_version` |
| `tests/test_probe_lua.py` | erwartete Init-Zeile |
| `docs/changelog/CHANGELOG.md` | „Unveröffentlicht“ → Version mit Datum |

## 2. Bauen

```powershell
python tools/build_native.py --msvc "<VS>\VC\Tools\MSVC\14.44.35207" --sdk "C:\Program Files (x86)\Windows Kits\10" --sdk-version 10.0.22621.0
python tools/verify_native.py build/native/PC2CoopDiagnostic.dll
python tools/build_ui.py
python tools/build_probe.py --cobra-tools <cobra-tools> --python <python311>
python tools/build_setup.py
```

Die DLL jedes Mal neu bauen: ihre Versionsangaben (`native/version.rc`) kommen aus `Session.VERSION`.
Setup ebenso (Version und Repository aus `Session.VERSION` und `release.json`).

## 3. Paket

```powershell
python tools/package_release.py
```

Ein Paket für alle (ADR-023): `PC2Coop-<x.y.z>.zip` und `PC2Coop-<x.y.z>.zip.sha256`. Es prüft die
Build-Berichte von OVL, DLL und Setup und bricht ab, wenn eine Quelle seit dem Bauen geändert
wurde. `check()` lässt kein ACSE (ADR-009), keine Skripte und als Programme nur Setup und die DLL
zu. Die Anleitung im ZIP kommt aus `alpha-dist/LIESMICH.txt` (`{version}` wird ersetzt).
Getesteter Spiel-Build: `TESTED_BUILD` und `EXE_HASH` in `tools/package_release.py` nach jedem
Spiel-Update anpassen.

## 4. Prüfen

- Alle Tests + `tools/check_docs.py` grün (darunter `tests/test_setup_exe.py`,
  `tests/test_package_release.py`).
- Test in der Testkopie (mindestens Start, Hosten, betroffene Funktionen). Setup nur über die
  Befehlszeile und nur gegen die Testkopie: `PC2Coop-Setup.exe --install --game <Testkopie>`.
- **Datenschutz:** im Diff und im Paket keine Tokens/Cookies, keine echten Namen oder
  E-Mails, keine lokalen Pfade mit Benutzernamen, keine Logs, keine Spieldateien.
- `git diff --stat` mit und ohne `--ignore-cr-at-eol`.

## 5. Veröffentlichen (nach Rückfrage)

1. Commit, `git tag vX.Y.Z`, push.
2. `gh release create vX.Y.Z` mit ZIP, `.sha256`, `PC2Coop-Setup.exe` und `PC2Coop-Linux-install.sh` (ADR-024, FEAT-013; gh liegt im Arbeitsordner unter
   `work/toolchain/gh-2.104.0/bin/gh.exe`). Ältere Release-Dateien behalten keine Assets
   (Wunsch des Eigners); nur das neueste Release hat Dateien. Setup findet Updates über
   `releases/latest` und braucht beide Dateien.
3. Dieselbe ZIP (ohne Setup) an den Eigner geben; er lädt sie bei Nexus hoch. Nexus nimmt keine .exe.
