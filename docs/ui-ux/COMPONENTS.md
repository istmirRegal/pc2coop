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
`friends[]`, `chat[]`, `log[]`, `toasts[]` (id, text, color, loc, kind), `chatKey`, `labels`, `desync`, `dlc`, `guard`, `requests[]`,
`team` (tab, board, events, since, checkpoints, rules, vote, competition, context,
invitation), `visitor` (active, riding, guest, hint, shop, list, rides[], emotes, wheel).
Wer ein Feld hinzufügt, trägt es hier ein.

## Komponenten

| Komponente | Zeigt | Liest | FEAT |
|---|---|---|---|
| `CoopLayer` | Wurzel, stapelt alles | – | FEAT-110 |
| `PlayerBar` | Sitzungs-Cluster oben rechts: Spieler mit Zustands-Icon (`stateIcon`), Tätigkeit im Tooltip, Wettbewerbs-Uhr | players, following, visitor, team.competition | FEAT-090, FEAT-145 |
| `HoverTip` | Kasten mit Spiel-Tooltip beim Darüberfahren (`TooltipContainer`, wie `Button` mit `tooltipOnHover`) | tip, anchor, onClick, style | FEAT-090, FEAT-144 |
| `EndConfirm` | Dialog „Für alle beenden?“ (Spiel-`Dialog`), vor `leave` des Hosts mit Mitspielern | `askEnd`, `endOrAsk` | FEAT-042 |
| `raiseTooltips` (in `poll`) | hebt die Tooltip-Ebene des Spiels (`Layer_root` mit `.TooltipContainer`) auf z-index 10001 über unsere Ebene (10000) | – | – |
| `VisitorBar` | Besucher-Leiste, Kaufliste, Fahrgeschäfte-Liste, Bewertung | visitor, role | FEAT-160–169 |
| `EmoteWheel` | Emote-Rad | visitor.wheel | FEAT-168 |
| `RequestCard` (`pendingRequests`) | Anfrage-Karte: Beitritt, Abstimmung, Testfahrt, Bewerten | requests, team.vote, team.invitation, team.competition | FEAT-027, FEAT-141, FEAT-138, FEAT-147 |
| `ConnectionPill` | Verbindung zum Host, Sync, Host im Hauptmenü | join, desync, role | FEAT-031, FEAT-033 |
| `ContextMenu` | Markieren-Radialmenü (`MARK_ITEMS`) | team.context | FEAT-136 |
| `MarkHint` | Tastenhinweise „Enter Chat“, „Mittelklick Markieren“ (`keyCap`) | role, context, visitor, team.context | FEAT-095, FEAT-116 |
| `ChatArea` | Chat, Ereignisse und Meldungen unten links, Chat-Eingabe per Enter | toasts (kind), chatKey, role, context, open | FEAT-116 |
| `Lobby` | Multiplayer-Fenster. Park: `renderParkPanel` (links, Klassen des Spiel-Panels) mit `renderPanelPlayers`, `renderPanelFriends`, `renderPlan`, `renderHistory`, `renderSession`, `renderContentSetting`, `renderCompetition`. Hauptmenü (nur Rückfall ohne Seite): `renderBody` mit `renderPlayers`, `renderPlace`, `renderChat`, `renderContent`, `renderFriends` | fast alles | FEAT-110 |
| `MiniLobby` | Sitzungsleiste im Hauptmenü oben rechts (TP-04) | role, players, open | FEAT-034 |
| `MultiplayerPage` | Seite „Multiplayer“ im Hauptmenü (TP-03): `places` (acht Plätze), `friendRows`, `chatBody`, `parkTiles` (Spiel-`FrontEndTileButton`); `pagePanel` baut die Spalten aus den `Panel_*`-Klassen | fast alles im Hauptmenü | FEAT-119 |
| `pageReady`, `openPage`, `pageShown`, `openGamePage`, `sortedFriends` | Seite in `FrontEndNavData.screens` eintragen und öffnen, Spielseiten öffnen, Freunde sortieren | nav, currentState | FEAT-119 |
| `JoinProgress` | Beitrittsfortschritt | join | FEAT-031 |
| `Rejoin` | Wiederbeitritts-Dialog | join | FEAT-039 |
| `JoinConfirm` | Beitritts-Nachfrage | join | FEAT-028 |
| `JoinFailed` | Beitrittsfehler | join | FEAT-031 |
| `Avatar`, `AvatarCanvas` | Steam-Profilbild (PNG aus Base64 auf Canvas) oder Farbkreis | avatars | FEAT-036 |

## Hilfsfunktionen

| Funktion | Zweck |
|---|---|
| `C(name)` | Farbe aus den CSS-Variablen des Spiels (`--name`), gelesen in `refreshPalette()` alle 3 Abfragen (etwa 1 s); ändert sich eine, zeichnet die Ebene neu. Rückfall `PALETTE_DEFAULT` (ADR-020) |
| `noticeColor(hex)` | Streifen einer Meldungskarte: Lua-Farben mit Bedeutung (Warnung, Warten, Hinweis) werden zu Spielfarben (`warning`, `highlight`, `accentLight`) |
| `rem(px)` | Größe in rem (`px / 20`, Entwurf bei 1080p) |
| `glyph(src, size, white, extra)` | Spiel-Icon aus `/img/icons/` mit fester Größe; das `Icon` des Spiels ignoriert `style` (Größe 0) |
| `remPx()` | aktuelle Pixel pro rem (für Mauskoordinaten) |
| `HUD_BG(alpha)` | HUD-Grund wie `rgba(var(--accentPanelBackground-triplet), …)` im Spiel; folgt der Akzentfarbe |
| `ACCENT_A(alpha)` | Akzentfarbe mit Transparenz (Linien, Rahmen), wie `rgba(var(--accent-triplet), …)` |
| `hudPill(extra, alpha)` | Baustein Pille: HUD-Grund, runde Ecken, weiße Schrift (Wettbewerbs-Uhr) |
| `hudCard(extra, alpha)` | Baustein HUD-Karte: Meldungen, Chat, Mini-Sitzungskarte, Beitrittskarte |
| `keyCap(label)`, `keyHint(key, word, last)`, `hintBar(extra, children)` | Baustein Tastenhinweis wie `InputHintsItem` (`MarkHint`, Chat-Eingabe) |
| `literal(text)` | Text für Spiel-Komponenten |
| `shown(text)` | Lokalisierungs-Schlüssel übersetzen, sonst Text |
| `section(title, extra)` | Abschnittstitel |
| `row(children, key)` | Zeile mit Trennlinie |
| `buttons(items, wide)` | Knopfreihe (`{label, onSelect, disabled, inputName}`); `wide`: über die ganze Zeile (schmales Fenster) |
| `iconButton(icon, tip, onSelect, toggled)` | runder Icon-Knopf mit Tooltip wie in den Info-Fenstern des Spiels |
| `muted(text, extra)` | Nebentext (0.9 rem, `accentButtonDesaturatedDark`) |
| `box(height, children)` | feste Höhe mit Scrollen |
| `statusOf`, `playerActivity`, `activityText`, `contentLine`, `joinText` | Texte aus dem Zustand |
| `openScreen(mode)` | Spielbildschirm im Hauptmenü öffnen (Park laden, Franchise, Sandbox) |

## Eingriffe in Spiel-Komponenten

| Funktion | Spielmodul | Was | ADR |
|---|---|---|---|
| `patchBuildBar` | `/js/project/modules/browser/components/Browser.js`, `BrowserTab.js` | Reiter „Multiplayer“ neben der Bauleiste | ADR-007 |
| `patchPauseMenu` / `patchMenuClass` | `/js/project/modules/gameMenu/components/GameMenuModule.js` | Eintrag im Pausemenü | – |
| `patchStartTabClass` | `/js/project/modules/frontEnd/views/mainMenu/menuTabs/FrontEndStartMenuTab.js`, `FrontEndTileButton.js` | Kachel im Hauptmenü | – |
| `DebugToolImports.js` | ersetzt `/js/common/debug/DebugToolImports.js` | startet die Ebene, Stil der Namensschilder (`•`-Präfix, `•#rrggbb` färbt den Namen) | ADR-001 |

Jeder Eingriff ist in `try/catch`, markiert die Klasse mit `__pc2coop` und schreibt bei
Fehlern ins Log (`PC2Coop_Log`). Nach Spiel-Updates zuerst diese Stellen prüfen.
