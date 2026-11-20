# Release

Öffentlich auf GitHub (`release.json`: Repository); Spieler aktualisieren mit `UPDATE.cmd`,
das `releases/latest` liest und zwei Dateien braucht: `PC2Coop-<x.y.z>.zip` und
`PC2Coop-<x.y.z>.zip.sha256`. Der Eigner lädt das Nexus-Zip selbst bei Nexus hoch.

**Jeder Schritt, der etwas veröffentlicht (push, tag, Release, Upload), nur nach Rückfrage.**

## 1. Version erhöhen (alle Stellen)

| Datei | Stelle |
|---|---|
| `probe/PC2CoopProbe/Main/database/pc2coopprobeluadatabase.lua` | `probeVersion` |
| `probe/PC2CoopProbe/Main/pc2coop/session.lua` | `Session.VERSION` (Host lehnt andere Versionen ab) |
| `tools/cobra_worker.py` | `probe_version` |
| `tests/test_probe_lua.py` | erwartete Init-Zeile |
| `alpha-dist/LIESMICH.txt` | Kopfzeile + „Neu in x.y.z“ |
| `docs/changelog/CHANGELOG.md` | „Unveröffentlicht“ → Version mit Datum |

## 2. Bauen

```powershell
python tools/build_native.py --msvc "<VS>\VC\Tools\MSVC\14.44.35207" --sdk "C:\Program Files (x86)\Windows Kits\10" --sdk-version 10.0.22621.0
python tools/build_ui.py
python tools/build_probe.py --cobra-tools <cobra-tools> --python <python311>
```

Die DLL jedes Mal neu bauen: ihre Versionsangaben (`native/version.rc`) kommen aus `Session.VERSION`.

## 3. Pakete

```powershell
python tools/package_release.py            # GitHub: Installer, Updater, Quellen
python tools/package_release.py --nexus    # Nexus: nur Win64\ovldata\PC2CoopProbe + LIESMICH + Lizenz
```

`payload()` kopiert nur `Main.ovl`, `Manifest.xml` und die DLL aus `build/` (Dev-Flag und Logs
können so nicht hinein). `check()` lehnt Pakete mit ACSE ab (ADR-009) und im Nexus-Zip alle
`.cmd`/`.bat`/`.ps1`/`.exe`/`.vbs`/`.js` (ADR-010). `NEXUS_README` ersetzt Sätze der
LIESMICH für Nexus – wer die LIESMICH ändert, prüft, dass jeder ersetzte Satz noch genau
einmal vorkommt (sonst bricht `--nexus` ab).

## 4. Prüfen

- Alle Tests + `tools/check_docs.py` grün.
- Test in der Testkopie (mindestens Start, Hosten, betroffene Funktionen).
- **Datenschutz:** im Diff und in den Paketen keine Tokens/Cookies, keine echten Namen oder
  E-Mails, keine lokalen Pfade mit Benutzernamen, keine Logs, keine Spieldateien.
- `git diff --stat` mit und ohne `--ignore-cr-at-eol`.

## 5. Veröffentlichen (nach Rückfrage)

1. Commit, `git tag vX.Y.Z`, push.
2. `gh release create vX.Y.Z` mit Zip und `.sha256` (gh liegt im Arbeitsordner unter
   `work/toolchain/gh-2.104.0/bin/gh.exe`). Ältere Release-Dateien behalten keine Assets
   (Wunsch des Eigners); nur das neueste Release hat Dateien.
3. Nexus-Zip an den Eigner geben.
