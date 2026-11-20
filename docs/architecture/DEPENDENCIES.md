# Abhängigkeiten

## Externe Abhängigkeiten

| Was | Wofür | Ausgeliefert? |
|---|---|---|
| Planet Coaster 2 (Steam, Build siehe `profiles/`) | alles; Spiel-APIs `api.*`, Gameface | nein |
| ACSE (Mod-Loader) | lädt die Lua-Datenbank und Hooks | **nein**, der Spieler installiert es selbst (ADR-009, FEAT-002) |
| `steam_api64.dll` des Spiels | Lobby, Freunde, Networking Messages | nein, bereits geladen (`GetProcAddress`) |
| Preact (im Spiel vorhanden) | Oberfläche `CoopLayer.js` | nein |
| MSVC 2022, Windows SDK 10.0.22621 | DLL bauen | nein (nur Entwicklung) |
| Cobra Tools (`work/toolchain/cobra-tools`) | OVL bauen | nein (nur Entwicklung) |
| Python 3.11 + `lupa` | Tests, Build-Skripte | nein (nur Entwicklung) |
| `gh` CLI | Releases | nein (nur Entwicklung) |

Spiel-Module, auf die der Code angewiesen ist (Namen können sich mit Spiel-Updates ändern):
`Editors.Scenery.SubModeBase`, `Editors.Scenery.SubModeSelect`, `Managers.ParkLoadSaveManager`,
`Windows.MainHUDGameface`, `Managers.NotificationManager`, `StartScreen.Shared.SandboxMenuHUD`,
`Editors.Shared.BaseUIMode`, `Editors.Shared.BaseEditMode`, `Editors.Gameface.GamefaceBaseUIMode`,
`Editors.Scenery.Utils.SceneryUtils`, `Helpers.VisitorCameraTargetUtils`, `Helpers.RideDatabaseUtils`,
`UI.GamefaceUIWrapper`, `Database.GameDatabase`, `Quaternion`, `TransformQ`, `Vector3`.
Gameface: `/js/common/core/Engine.js`, `/js/common/core/Localisation.js`.
Nach einem Spiel-Update zuerst diese prüfen (`docs/development/TESTING.md`, Abschnitt Spiel-Update).

## Modul-Abhängigkeiten (Lua)

`A → B` heißt: A lädt B (`require`). Gestrichelt (`⇢`) = nur bei Bedarf oder in `pcall`.

```
pc2coopqa (Park-Manager) → qa, diagnostic, live, sync, session, labels, viz, recorder, menu, ui
frontend  → diagnostic, session, ui
session   → world, shared, board, rides, shop, sync, visitor ⇢ figure
sync      → replay, rides, recorder, shared, visitor, world
capture   → sync
ui        → parks, shop, sync, visitor, world ⇢ board
visitor   → figure, shop, world
viz       → shared ⇢ figure
world     → shared
menu      → recorder
qa        → (fast alles, nur Dev-Flag)
board, figure, shop, parks, labels, diagnostic, replay, rides, recorder, introspect, live, shared → nichts aus pc2coop
```

Regeln:
- Basis-Module (`board`, `figure`, `shop`, `replay`, `rides`, `parks`) bleiben ohne Abhängigkeit zu
  `session`; sie sind einzeln testbar.
- `session` darf `visitor` nur über `require` im Funktionsrumpf benutzen (Kreis
  `visitor → … → session` vermeiden); `visitor` kennt `session` nicht, sondern bekommt
  Rückrufe über `Visitor.Init`.
- Die Oberfläche (`CoopLayer.js`) hängt nur am DataStore-Zustand von `ui.lua` und an
  `Engine.sendEvent('PC2Coop_Request', …)`; sie kennt keine anderen Lua-Module.

## Funktions-Abhängigkeiten (Auszug)

Die Spalte „Hängt ab von“ jeder Funktion steht in ihrer Bereichsdatei unter `docs/features/`.
Kritische Ketten, die beim Ändern beachtet werden müssen:

| Wenn du änderst … | … prüfe auch |
|---|---|
| Nachrichtenformat in `session.lua` | `docs/architecture/NETWORKING.md`, `tests/test_session_lua.py`, Versionsprüfung FEAT-029 (alte Gäste) |
| `Sync.Receive` / `Handlers.*` | FEAT-060–081, `tests/test_sync_lua.py`, `tests/test_editor_sync_lua.py` |
| Whitelist in `replay.lua` | ADR-005, FEAT-065–071 |
| `ui.lua`-Zustand | `CoopLayer.js` (liest die Felder), `docs/ui-ux/UI_INVENTORY.md` |
| Tasten in `native/steam_net.cpp` | FEAT-195, `Visitor.OnKey`, `Session`-Ereignis `key:v` |
| Paketinhalt | `tools/package_release.py` `check()`, ADR-009, ADR-010 |
| Version | alle Stellen in `docs/development/RELEASE.md` |
