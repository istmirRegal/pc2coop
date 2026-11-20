# Komponenten

Alle in `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js`.

## Zustand

- Lua (`ui.lua`, `Ui.Tick`) schreibt JSON in den DataStore-Kontext `pc2coop`, Felder `state`
  und `avatars` (Profilbilder, selten geändert).
- `poll()` alle 300 ms: Listener anmelden (`DS.getPropertyListener`), Wert lesen, alle 10
  Durchläufe die eigenen DLCs melden (`reportDlc` → `dlc`).
- `StateComponent`: Basisklasse; jede Komponente bekommt `state.coop` = ganzer Zustand.
- Zurück: `request(cmd, arg)` (FEAT-118).

Wichtige Zustandsfelder (aus `ui.lua`): `available`, `role`, `context` (menu/park), `open`,
`canHost`, `players[]` (sid, name, host, me, color, act, …), `following`, `join` (phase,
host, progress, reason, retry), `stage`, `parkTitle`, `choice`, `canChoose`, `parks[]`,
`friends[]`, `chat[]`, `log[]`, `toasts[]`, `desync`, `dlc`, `guard`, `requests[]`,
`team` (tab, board, events, since, checkpoints, rules, vote, competition, context,
invitation), `visitor` (active, riding, guest, hint, shop, list, rides[], emotes, wheel).
Wer ein Feld hinzufügt, trägt es hier ein.

## Komponenten

| Komponente | Zeigt | Liest | FEAT |
|---|---|---|---|
| `CoopLayer` | Wurzel, stapelt alles | – | FEAT-110 |
| `PlayerBar` | Spielerleiste oben rechts | players, following, visitor, join | FEAT-090 |
| `VisitorBar` | Besucher-Leiste, Kaufliste, Fahrgeschäfte-Liste, Bewertung | visitor, role | FEAT-160–169 |
| `EmoteWheel` | Emote-Rad | visitor.wheel | FEAT-168 |
| `VoteBanner` | Abstimmung | team.vote | FEAT-141 |
| `ContextMenu` | Mittelklick-Menü | team.context | FEAT-136 |
| `CompBanner` | Wettbewerbs-Uhr | team.competition | FEAT-145 |
| `InviteBanner` | Testfahrt-Einladung | team.invitation | FEAT-138 |
| `Toasts` | Meldungen unten links (max. 5, 6 s) | toasts | FEAT-116 |
| `Lobby` | Multiplayer-Fenster mit Reitern (`renderBody`, `renderVisit`, `renderPlan`, `renderHistory`, `renderSession`, `renderPlayers`, `renderChooser`, `renderPlace`, `renderChat`, `renderContent`, `renderFriends`) | fast alles | FEAT-110 |
| `MiniLobby` | Lobby-Karte im Hauptmenü | role, players, open | FEAT-034 |
| `JoinProgress` | Beitrittsfortschritt | join | FEAT-031 |
| `Rejoin` | Wiederbeitritts-Dialog | join | FEAT-039 |
| `JoinConfirm` | Beitritts-Nachfrage | join | FEAT-028 |
| `JoinFailed` | Beitrittsfehler | join | FEAT-031 |
| `Avatar`, `AvatarCanvas` | Steam-Profilbild (PNG aus Base64 auf Canvas) oder Farbkreis | avatars | FEAT-036 |

## Hilfsfunktionen

| Funktion | Zweck |
|---|---|
| `literal(text)` | Text für Spiel-Komponenten |
| `shown(text)` | Lokalisierungs-Schlüssel übersetzen, sonst Text |
| `section(title, extra)` | Abschnittstitel |
| `row(children, key)` | Zeile mit Trennlinie |
| `buttons(items)` | Knopfreihe (`{label, onSelect, disabled, inputName}`) |
| `box(height, children)` | feste Höhe mit Scrollen |
| `statusOf`, `playerActivity`, `activityText`, `contentLine`, `joinText` | Texte aus dem Zustand |
| `openScreen(mode)` | Spielbildschirm im Hauptmenü öffnen (Park laden, Franchise, Sandbox) |

## Eingriffe in Spiel-Komponenten

| Funktion | Spielmodul | Was | ADR |
|---|---|---|---|
| `patchBuildBar` | `/js/project/modules/browser/components/Browser.js`, `BrowserTab.js` | Reiter „Multiplayer“ neben der Bauleiste | ADR-007 |
| `patchPauseMenu` / `patchMenuClass` | `/js/project/modules/gameMenu/components/GameMenuModule.js` | Eintrag im Pausemenü | – |
| `patchStartTabClass` | `/js/project/modules/frontEnd/views/mainMenu/menuTabs/FrontEndStartMenuTab.js`, `FrontEndTileButton.js` | Kachel im Hauptmenü | – |
| `DebugToolImports.js` | ersetzt `/js/common/debug/DebugToolImports.js` | startet die Ebene, Stil der Namensschilder (`•`-Präfix) | ADR-001 |

Jeder Eingriff ist in `try/catch`, markiert die Klasse mit `__pc2coop` und schreibt bei
Fehlern ins Log (`PC2Coop_Log`). Nach Spiel-Updates zuerst diese Stellen prüfen.
