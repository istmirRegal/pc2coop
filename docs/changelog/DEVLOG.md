# Development Log

Für Entwickler: interne Änderungen, Funde, Refactors, bekannte Probleme. Neueste zuerst.
Spieler-Änderungen: `docs/changelog/CHANGELOG.md`.

## 2026-11-21 – Sicherheit und Stabilität geprüft (coop-anything-Methoden)

- Auftrag des Eigners: Zusammenspiel übers Netz, Abstürze, Out of Sync, Edge Cases und
  IT-Sicherheit (DLL, Dateien, Chat/JavaScript) prüfen, mit dem Repo coop-anything als Hilfe.
  Dessen Werkzeuge (fuzz, chaos, flight) sind für C++-Mods mit eigener UDP-Verbindung gebaut;
  PC2Coop läuft über Steam und Lua. Übernommen wurden Methode und Profile:
  `tests/test_fuzz_session_lua.py` (Sitzungen aus Seeds über ein gestörtes Netz, Orakel,
  Neustart der Lua-Module bei jedem Parkladen) und über 5000 bösartige Nachrichten.
- Funde des Fuzzers, behoben: zweimal kurz nacheinander geladen → kein Brett, keine Regeln
  (`Session._SendTeam` nach jedem Laden); Park-Übertragung unterwegs verloren → Spieler wartete
  ewig (`Session._CheckParkArrives`: nach 20 s ohne Fortschritt neu anfragen, 3×, dann
  „Erneut versuchen“; der Host startet eine hängende Übertragung nach 30 s neu).
- Sicherheitsfunde, behoben: keine Mengenlimits (Chat, Brett, Einladungen, Bewertungen – auch
  Brett- und Bewertungsdatei liefen voll) → `Session.RATE_LIMITS`; `pres` nahm ∞ an →
  `Session._Finite`; Replay-Vektoren nahmen ∞ an → Grenze wie bei Zahlen; Baupläne: ein
  Mitspieler konnte Dateien anderer überschreiben und unbegrenzt viele schicken → DLL nimmt nur
  `pc2coop-ride-<Absender>-…`, ≤ 400 je Spieler und Spielstart (DLL neu gebaut).
- Ohne Befund: Verbindungen nur von Lobby-Mitgliedern, Dateinamen nur `pc2coop-…`, kein
  `innerHTML`/`eval` in der Oberfläche (Chat ist Text), kein `load` auf Netzdaten,
  Replay nur über die Liste der Bau-Methoden, Entwicklerkanal nur mit Flag-Datei.
- Übersicht: `docs/architecture/SECURITY.md`.

## 2026-11-21 – Markierung ohne Verdecken, Restpunkte aus dem UX-Konzept

- Wunsch des Eigners: die Markierung darf keine Spielelemente verdecken, nur unterstützen
  (halb durchsichtig, Umrisse o. Ä.). Umsetzung mit dem, was das Spiel schon kann: der
  Highlight-Kanal 3 (wie gesperrte Objekte) blinkt auf dem markierten Objekt; gefunden wird es
  am Maus-Strahl (`Sync.PartOnRay`, der Boden-Strahl ging durch Objekte hindurch), die Id geht
  mit `ping`/`pg`. Ohne Objekt: zehn kleine Punkte im Kreis am Boden. Baugebiete waren eine
  Scheibe mit dem Durchmesser des Gebiets über allem darin – jetzt ein Punktring. Keine
  schwebenden Scheiben mehr. `spawn` ohne Entität bricht die Schleife ab (sonst hinge sie).
- Schilder in der Welt (Ping „hier!“, Brett, Park-Meldungen) über `Lang.World` auf Englisch.
- TP-32: Schalter „Chat unten links einblenden“ (FEAT-122). Das alte mittige Fenster des
  Hauptmenüs (Rückfall mit dem Look vor dem Overhaul) und `renderBody`/`renderPlayers`/
  `renderPlace`/`renderChat`/`renderFriends` sind entfernt; `pendingPage` öffnet die Seite nach.
- `tests/test_alpha.py`: `wait_for` 15 s statt 4 s (scheiterte unter Last), Inbox-Lesen über
  `wait_for`.
- Fehlende englische Muster: „… kauft … (…)“, „Gekauft: …“.

## 2026-11-21 – Englisch nach der Sprache des Spiels (FEAT-121, ADR-022)

- Wunsch eines englischsprachigen Testers, vom Eigner freigegeben. Die Texte bleiben im Code
  Deutsch; `Texts.js` übersetzt beim Anzeigen (`EXACT` ~330 Einträge, ~110 `PATTERNS` für Texte
  mit Namen/Zahlen aus JS und Lua, „ · “-Teile einzeln). `tr()` hängt in `h()` und `literal()`,
  also an jedem Text der Ebene; Texte von Spielern gehen durch `keep()` („Super“ im Chat bliebe
  sonst nicht „Super“).
- Sprache: `System.getLanguage()` des Spiels (`Language.German` = 2), sonst Englisch;
  `import('./Texts.js')` nur dann (fehlt die Datei, bleibt alles Deutsch). Lua bekommt die
  Sprache über die UI-Aktion `lang` (für die Schilder an Objekten, `lang.lua`), der Zustand
  spiegelt sie zurück, damit die Ebene sie erneut schickt, falls Lua am Anfang nicht zuhörte.
- Die Hinweiszeile (`setPrompts`) wurde einmal beim Laden gebaut; jetzt `buildPrompts()`.
- Tests: `tests/test_texts_js.py` (Node, Beispiele aus Oberfläche und Lua; keine Umlaute in der
  englischen Spalte), `tests/test_lang_lua.py`, `lang` in `tests/test_ui_lua.py`.
- Nebenbei: weitere Textregeln in Lua (kein „bitte“, kein „oben rechts anklicken“, „Sie können“
  → kurzer Satz, „abreissen“ → „abreißen“).
- Testkopie auf Build 26494896 gebracht (robocopy aus der Installation des Eigners, nur lesen;
  Mod-Ordner, ACSE und Testdateien ausgenommen; 124 Dateien, 2,2 GB). Dort geprüft (QA-Feld 6):
  Hauptmenü-Seite und Fenster im Park auf Englisch, „Enter Chat“/„Mark“ in der Hinweiszeile,
  Meldungen aus Lua („Undone: …“, „Vici placed 3 objects“), „Super“ im Chat bleibt. Log ohne
  NUL-Byte, Stringroutine bei RVA `0x1e2d910` wie beim Tester. Fund dabei: Zurück auf Deutsch
  blieb „Mark“ stehen – `promptsShown` wird beim Sprachwechsel `null`, damit die Zeile neu gesetzt
  oder geleert wird. Komponenten des Spiels (Schalter „Ein“, Brotkrumen) folgen dessen Sprache.

## 2026-11-21 – UX-Overhaul gegen das Konzept geprüft

- Auftrag des Eigners: prüfen, ob das UX-Overhaul wirklich richtig umgesetzt ist. Code gegen
  `UX_OVERHAUL.md` (TP-Ziele, §5 Zustände, §6 Orte, §7 Textregeln, P0-Kriterien) gelesen.
  P0-Kriterien halten (keine festen Farben außer Spielerfarben und neutralem Weiß, kein `px` außer
  gemessenen Positionen). Funde und Behebung stehen in `UX_OVERHAUL.md` §9 „Prüfung 2026-11-21“:
  13 Lua-Texte ohne Umlaute, Bedienwege („Multiplayer > Sitzung“, „unten im Baumenue oder F7“),
  „Ping“, Übernahme-Frage als Toast statt Anfrage-Karte (jetzt `Session.TakeAsk`, `take_ok`).
- Werte auf dem Netz bleiben ASCII-Codes (`laedt`, `geloescht`, `empfaengt`); nur Anzeigetexte
  haben Umlaute. `cut()` kürzt UTF-8-sicher.
- Der Hauptblock von `session.lua` ist am Limit von 200 Locals; neue Werte als Modulfelder
  (`Session._takeAsk`, `Session.TAKE_ASK_FRAMES`, `Session._AskedToTake`).

## 2026-11-21 – „unknown park“ bei Testern (1.13.0)

- Ein Tester konnte in 1.13.0 keinen gespeicherten Park über „Park öffnen“ laden, neue schon
  (Meldung „Der Park konnte nicht geöffnet werden (unknown park)“). Ohne Log gefunden: das
  `require` des Hauptmenüs cached keine Module (wie in `shared.lua` beschrieben). `refreshParks`
  und `start` holten sich je eine eigene `parks.lua`; die Speicher-Token aus `Parks.List` waren
  beim `Parks.Load` weg. Trifft jeden gespeicherten Park, immer. Die Unit-Tests hatten ein
  Park-Modul ohne Zustand und sahen es nicht; der neue Test lädt das echte `parks.lua` mit einem
  `require` wie im Menü und zeigt vor dem Fix genau `ui:start|save|false|unknown park`.
- „Liste kommt nicht sofort“: `refreshParks` lief nur beim Öffnen des Fensters, wenn die Lobby
  schon stand; sonst erst nach „aktualisieren“.
- 1.14.0 hat keinen Knopf mehr dafür (Park über die Seiten des Spiels), `ui.lua` hält trotzdem
  jetzt eine Instanz. Ausweg für 1.13.0: Lobby öffnen, Park über das Lade-Menü des Spiels öffnen.

## 2026-11-21 – Log-Datei ohne NUL-Byte

- Fremde Tester sollen ihr Log schicken; der Eigner sah beim Öffnen nur chinesische Zeichen.
  Ursache: die Kanal-Testzeile am Anfang (`pc2coopprobeluadatabase.lua`) schrieb absichtlich ein
  NUL-Byte. Eine Datei ohne BOM mit NUL hält der Windows-Editor für UTF-16. Die Zeile hat jetzt
  kein NUL mehr; NUL durch den Kanal prüft weiter `tools/verify_native.py`.
- Chat-Texte stehen nicht im Log, Bewertungskommentare schon (`session:feed`), dazu Steam-Namen
  und Steam-IDs. Logs bleiben außerhalb des Repositorys.
- Erstes Tester-Log (1.13.0, Solo-Park ohne Sitzung, kein Fehler): drei Viertel der Zeilen waren
  `replay:skip|ridestation.GetRideStationEditToken|… object not shared`. Das Spiel fragt das
  Token immer wieder ab, solange das Menü einer Fahrt offen ist; ohne Sitzung ist nichts geteilt.
  `replay.lua` schreibt jeden Grund jetzt beim 1., 10., 100. und jedem 1000. Mal (`|x<n>`),
  höchstens 200 verschiedene Gründe. Die Datei hat ein Limit von 4 MB.
- Bekannt: Steam hat PC2 am 2026-11-17 auf Build 26494896 aktualisiert; die Testkopie ist noch
  26255360. Die Mod findet im neuen Build alles (Tester-Log: Stringroutine bei RVA `0x1e2d910`,
  Prüfung bestanden, Hooks installiert). Mehrspieler auf dem neuen Build ist noch nicht geprüft.

## 2026-11-21 – P6: Funde aus dem ersten Test des Eigners

- Eigner testete 1.14.0 aus dem Nexus-Paket auf einem PC; 14 Funde (UX_OVERHAUL.md, Tabelle P6).
- Scrollen: Gameface scrollt nicht von selbst; `ScrollBox` hält den Versatz selbst und zeigt die
  Scrollleiste des Spiels (`ScrollPanePres`). Kinder brauchen `flexShrink: 0`, sonst schrumpfen sie
  auf die Höhe des Kastens. QA-Mausrad: Gameface kennt kein `WheelEvent`, `MouseEvent('wheel')`
  mit `deltaY` geht.
- Einstieg: runder Knopf in der `ManagementMenu`-Spalte (ADR-021), Fenster darunter; der Knopf
  erschien erst nach einem Neuzeichnen der Spalte, daher ein Anstoß, solange er fehlt.
- Hinweise: `ButtonPromptUtil.ButtonPromptHelper` des Spiels; Taste als Kind des `ButtonPrompt`
  (das Spiel kennt keinen Eingabenamen für Enter), Maus als `InputIcon_imageIcon` (ein
  `ButtonPrompt_icon` zeigte sie grau). Im Besuch eine Zeile mit den Klassen der Spielzeile; das
  Ausblenden der Spielzeile traf zuerst auch unsere (gleiche Klasse).
- Sitzungsleiste: `Button_root alt` wie der Newsletter-Kasten, Kanten gemessen.
- Marker: Ping-Ring 1–1,5 statt 2–6, drei statt sechs Scheiben, Größe nach Kameraabstand
  (`sizeAt`, Abstand/25 zwischen 0,5 und 3; bei Abstand/60 war er aus 45 m nicht mehr zu sehen),
  Füllung 0,45 statt 0,6. Wirklich durchsichtig wird die Grundform des Spiels nicht.
- Testkopie: runder Knopf, Hinweiszeile (Enter, Maus Mitte weiß), Scrollen per QA-Mausrad im
  Fenster und auf der Seite, Sitzungsleiste, Hinweis auf der Sandbox-Seite, „Freund wählen →“,
  Besuchs-Hinweise in der Spielzeile, Rad ohne Zahlen, Ping aus 35 m und 70 m fotografiert.
- Besuch: Geschwindigkeit und Blickrichtung folgen den Tasten weich (`ACCEL`, `DECEL`, `TURN`),
  Gang nach echter Geschwindigkeit mit Spielraum; Eingänge/Läden über einen Fächer aus Richtungen
  (`lookYaws`); Zahlentasten aus; Zeiger aus (`set_cursor_hidden`, `cursor: none`).

## 2026-11-21 – TP-29: Tooltips an gesperrten Spielknöpfen

- `patchStatusControls` wie beim Pausemenü (`Focusable.decorateEx`, `nodeName` ist die echte
  Klasse); `wrapStatusTooltips` umhüllt die Tooltip-Funktionen der Instanz einmal und ändert nur
  `attributes.label`, die Taste im Tooltip bleibt. Entscheidet beim Darüberfahren (`statusLockText`).
- QA-Look-Feld 14 schreibt die Texte ins Log. „Nur der Host ändert das Spieltempo“ mit Umlaut.

## 2026-11-21 – Spielerleiste weicht Fenstern des Spiels aus

- Fund: Die Spielerleiste lag über dem Szeneriepinsel-Fenster. `trackRightPanels` (in `poll()`)
  misst `Panel_panel` außerhalb unserer Ebene am rechten Rand; `PlayerBar` rückt links daneben.
- Testkopie: Gelände-Werkzeug per QA geöffnet (`BaseEditMode` "Terrain",
  `GamefaceBaseUIMode` "GamefaceTerrain"), Leiste rückt aus, nach "Select" wieder am Rand.

## 2026-11-21 – UX-Overhaul P5, Schritt 3: ohne Steam, leere Listen, Zurückholen

- `Session.NetProblem` (`dll`/`steam`), `net:error` setzt `Session._netError` und macht
  `Session.Available` falsch; UI-Feld `netProblem`. `NET_PROBLEM` für Kachel, Seite, Statuszeile.
- `onlineFriends`, `noFriendsText`, `INVITED_TIP`; `RestoreConfirm` (QA-Look-Feld 13).
- Abstimmungstext „zurücksetzen“ mit Umlaut.

## 2026-11-21 – UX-Overhaul P5, Schritt 2: Beitritt, Start, Einladungen

- `joinSteps` mit Spiel-`ProgressSteps` (`hideLabels`; auf der Seite `scale(0.8)` und absolut
  gesetzt, sonst lief es links aus dem Kasten) und eigenem Balken (die Spiel-`ProgressBar` zeichnete
  nichts); auf der Seite statt der Plätze, sonst `JoinProgress`. „Abbrechen“ → `cancel_join`; `Session.DismissJoin` merkt die
  Lobby (`Session._dropLobby`), ein späteres `lobby:entered` dafür wird verlassen.
- `Session._starting` (Phase `starting`), gelöscht bei `lobby:entered`; `lobby:error|create-failed`
  und 1800 Frames ohne Antwort → `failJoin`. `hostButton`, `spinner` (Spiel-`LoadingSpinner`,
  per `transform: scale` verkleinert).
- Freunde tragen `asked` (Frame der Einladung); JS merkt die Zeit (`invitesSeen`), nach 2 Minuten
  „keine Antwort“. Fehlertexte ohne Doppelpunkt, mit Umlauten.

## 2026-11-21 – UX-Overhaul P5, Schritt 1: Verbindung und Sitzungsende

- `ConnectionPill` mit Zeit (`trackConnection`, Uhr in JS: Lua sagt nur `silent`), „Verlassen“,
  grüner Moment; `ConnectionDialog` nach 30 s und für „Host im Hauptmenü“; `SessionEnded`.
- `session.lua`: Phase `ended` (`Session._ended` als Feld: der Hauptteil hatte die 200 lokalen
  Variablen von Lua erreicht), `Session.DismissEnded`, UI-Aktion `ended_ok`; Toasts „Keine
  Verbindung …“, „… wieder da“, „Host ist zurück im Hauptmenü …“ entfallen; der Desync-Toast
  nur noch beim Host (Mitspieler haben die Pille mit dem Knopf). Logzeilen `host-gone`,
  `host-in-menu`.
- Zurück ins Hauptmenü über `Engine.sendEvent('ExitToMainMenu')` wie im Pausemenü des Spiels.

## 2026-11-20 – UX-Overhaul P4, Schritt 2: Emote-Rad und Sterne

- `EmoteWheel` wie `ContextMenu`: Kreise auf einem Ring (7 rem), Icons
  `guestThoughts/guest_bubble_mood_happy`, `…_mood_excited`, `…_emotionFunny`, `…_like`,
  `…_dislike`, `…_sick` (farbig, ohne Filter), Taste als `keyCap`, Mitte „T loslassen“.
- `VisitorRides`: Durchschnitt als Spiel-`Stars`; eigene Wertung als fünf `star`/`starOutline`
  mit neuem Paletten-Eintrag `accent-filter` (wie `--accent-filter` der Spiel-Sterne).
- Testkopie: T und Maus als Ereignisse eingespielt (`key:v|t|1`, `mouse|40|25`), Rad fotografiert,
  danach „<Name> lacht“ im Verlauf; Panel mit vorgetäuschten Bahnen und einer Wertung.

## 2026-11-20 – UX-Overhaul P4, Schritt 1: Besuch ohne Leiste oben

- `VisitorBar` ersetzt durch `VisitorHud` (Tastenhinweise, E-Hinweis, Kauf-Panel) und
  `VisitorRides` (Panel links). `syncVisitHud` blendet `BrowserModule_root` und `HUD_promptsList`
  des Spiels im Besuch aus und danach wieder ein (Prototyp „Bauleiste im Besuch aus“).
- Fund: Ein `div` ohne Größe als Wurzel – `bottom` und `top: 58%` der Kinder rechneten von einem
  Kasten der Höhe 0 oben am Bild: Hinweise unsichtbar, E-Hinweis oben. Jetzt `100vw × 100vh`.
- F: DLL `poll_visitor` mit 11 Tasten (`'F'` → `f`), `Visitor.OnKey` → `list`,
  `Visitor.SetList`/`ListOpen` (Maus-Look aus, solange offen), `ui.lua` liest die Liste von dort
  (`visitorList` entfällt). Test `test_f_opens_the_rides_and_frees_the_mouse`.
- QA-Sicherheit: Maus-Look im QA-Skript abgeschaltet (TESTING.md), die DLL hätte sonst den
  Zeiger des Eigners in die Mitte der Testkopie gezogen.

## 2026-11-20 – UX-Overhaul P3, Schritt 2: Anfrage im Platz, „öffnet einen Park“, „Alle sind da“

- TP-06: `places` setzt Anfragen als Karte zwischen Spieler und Eingeladene (Icon-Knöpfe `tick`,
  `close`); der gestrichelte Rand allein war in Gameface nicht zu sehen, daher `accentFaint`.
- TP-08: `FrontEndNav.onChange` auf `LoadPark`/`SettingUpSpinner` beim Host in der Lobby →
  UI-Aktion `opening` (`ui.lua`: `SetChoice("game", "einen Park")`, `MarkStarting`); die Wahl
  geht mit der Roster-Zeile an alle. In der Testkopie kamen `close` und `opening` beim Anlegen
  des Testparks aus dem Hauptmenü an.
- „Alle sind da“: Beobachter in der HUD-Ansicht (`allHere`): erst jemand mit Lade-Tätigkeit
  (`-`, `laedt`, `holt…`, `lobby`), dann niemand mehr → 5 s Pille unter den Spielern, einmal je
  Park-Ansicht. Test `test_host_opening_a_park_on_the_game_pages`.

## 2026-11-20 – UX-Overhaul P3, Schritt 1: Multiplayer-Seite im Hauptmenü

- Prototyp: `FrontEndNavData.screens` ist ein offenes Objekt. `pageReady` trägt `MultiplayerPage`
  als Seite 900 ein (Eltern Hauptmenü, `claimDefaultInputs`); `FrontEndModule` zeichnet sie samt
  Kopf, Brotkrumen und Esc. `ScreenID[900] = 'MainMenu'`, damit die Engine bei
  `FrontEndModeChange` einen bekannten Namen hört.
- Fenster-Zustand ↔ Seite: Öffnen (Kachel, F7, Leiste) navigiert zur Seite; Esc, Brotkrumen oder
  eine Spielseite schicken `close` (`FrontEndNav.onChange`); Schließen aus Lua geht ins Hauptmenü.
  Ohne Seite bleibt das alte Fenster (`lobbyFallback`).
- Absturz in der Testkopie beim ersten Öffnen: `openPage` rief alle Zustands-Beobachter direkt auf,
  darunter den, der `openPage` aufruft – Rekursion bis zum Stapelüberlauf, das Spiel beendete sich
  ohne Fehlermeldung. Jetzt `setTimeout`, und der Beobachter merkt sich den Zustand vorher.
- Entfernt: `renderChooser`, `MODES`, `BIOMES`, `openScreen` (Mod-Parkliste, UX-A6). Neu
  `openGamePage` wie die Spiel-Kacheln (Sandbox-Seite; Franchise über `FrontEndFranchiseSelected`,
  wie die Kachel des Spiels, statt direkt zu navigieren).
- Sitzungsleiste: bei 5.2 rem lag sie über dem Newsletter-Kasten, jetzt 10.8 rem. Der Chat-Bereich
  unten links blendet sich auf der Seite aus (sie hat ihren eigenen Chat). Chat-Zeilen in einer
  Reihe (in Gameface stand der Text sonst unter dem Namen).
- Prüfung: Node-Rendertest (ohne Sitzung, Host, Gast, Einladen, Leiste, Rückfall-Fenster);
  Testkopie im Hauptmenü (Bot-Schritt `inspect:qa:frontend=true`, QA-Skripte über
  `pc2coop.frontend`): Seite ohne und mit Sitzung, Schließen, Leiste auf Hauptmenü und
  Sandbox-Seite. Kein Klick im Hauptmenü.

## 2026-11-20 – Brett: eigene Stimme falsch angezeigt

- `ui.lua` `teamState`: `myVote = mine == nil and false or (…)` ergab ohne Stimme "0" (in Lua
  ist `a and false or b` nie `false`), der Daumen „Dagegen“ war bei jedem Vorschlag gewählt.
  Gefunden auf den Bildern von P2. Test `test_board_vote_of_this_player` (scheitert ohne die
  Korrektur). Im Spiel nicht erneut fotografiert.

## 2026-11-20 – Wackliger Test `test_alpha`

- `BridgeTests.test_pid_bound_inbox_explicit_newpark_ack_and_error_stop` scheiterte etwa jeden
  sechsten Lauf mit `PermissionError`: Unter Windows lässt sich die Inbox-Datei nicht öffnen, während
  die Bridge sie schreibt. `wait_for` wertet das jetzt als „noch nicht“. Danach 10 Läufe
  `test_alpha` und 6 volle Läufe grün.

## 2026-11-20 – UX-Overhaul P2, Schritt 4: Planen, Verlauf, Pausemenü

- TP-17: `BOARD_ICON` je Art; `iconButton('footerGuests', …)` → `board_assign` reihum (die
  UI-Aktion gab es schon, nur keinen Knopf: UX-C3). Formular: Art, Zuständig, Größe als
  `ListStepperRow` (`AREA_SIZES`) statt Pillen und „Wechseln“. `infoTip` für Erklärungen.
- TP-18: Meldungen des Parks als Zeilen (Icon `notifications_warning`, „Hinbringen“,
  „Ausblenden“ über `state.dismissed`). `Session._ShowSince`: Meldung (200 Zeichen) und Zeile im
  eigenen Feed, nicht über `addFeed` (der Host hätte seine an alle geschickt). Der Host bekam
  bisher gar keine Meldung. „Fahrgeschaefte“ → „Fahrgeschäfte“.
- TP-30: `patchMenuClass` setzt in einer Sitzung „Sitzung verlassen“/„Sitzung beenden“ vor
  „Beenden“ des Spiels (`endOrAsk`).
- Namensschilder: `DebugToolImports.js` nimmt den Punkt bei allen Mod-Schildern ab. Versuch mit
  `nowrap`: das Schild wurde abgeschnitten. Die Schilder sind Zellen eines Atlas
  (`CoasterLabels_cellItem`), sie können nicht breiter werden, also bleibt der Umbruch.
- Prüfung: neuer Lua-Test (since als Meldung und im Feed); Node-Rendertest Planen mit Formular,
  Verlauf mit ausgeblendeter Meldung, Pausemenü ohne/mit Sitzung; Testkopie: Planen, Verlauf,
  Schilder.

## 2026-11-20 – UX-Overhaul P2, Schritt 3: Einstellungen als Spielzeilen, Nachfrage beim Beenden

- TP-20: `renderSession` mit `ToggleRow` und `ListStepperRow` des Spiels, `focusable: false`
  (kein Fokus beim Darüberfahren). Regeln haben ihren Tooltip in `RULES` (4. Feld); Schnellwahl
  aus `PRESETS` (wie `rule_preset` in `ui.lua`), „Eigene“ nur solange keine passt. Mitspieler:
  `disabled` + Tooltip `LOCKED`. „Locker zusammen bauen“ war in der Auswahl abgeschnitten → „Locker“.
- „Deine Rolle“ und „Abwesenheit“ entfallen als Abschnitte: Rolle als Tooltip am Info-Icon
  (`HoverTip`), Gehen als Tooltip an „Beenden“/„Verlassen“ (`buttons()` kann jetzt `tip`).
- TP-30: `endOrAsk` → `EndConfirm` (Spiel-`Dialog`) beim Host mit Mitspielern, im Park und im
  Hauptmenü. Der Dialog dunkelt das Spiel ab, unser Fenster bleibt hell (es liegt darüber).
- Fund: Alle Spiel-Tooltips (auch Reiter, Icon-Knöpfe) lagen unter unserer Ebene: die
  `LayerCollection` des Spiels hat keinen z-index, unsere Wurzel 10000. `raiseTooltips` (in `poll`
  und beim Darüberfahren) setzt nur die Tooltip-Ebene auf 10001.
- Prüfung: Node-Rendertest (Host/Gast, Regeln passend/„Eigene“); Testkopie: Einstellungen mit
  Tooltip über dem Fenster, „Eigene“ + Besucher-Modus aus, Dialog, Spielerleiste.

## 2026-11-20 – UX-Overhaul P2, Schritt 2: Spielerleiste und Namensschilder

- TP-13: `PlayerBar` zeigt `stateIcon` (Spiel-Icons `building`, `camera`, `move`,
  `downloadArrow`, `clock`, `eye`) statt der abgeschnittenen Tätigkeit. Die Tätigkeit und
  „Klicken zum Folgen“ stehen im Tooltip: neue Klasse `HoverTip` mit dem `TooltipContainer` des
  Spiels, Anker links neben der Pille (`TIP_LEFT`), Modifikator `wide` wie bei den Reitern des
  Spiels. Der Standard-Anker (oben, mittig) lief in der Ecke über den rechten Rand. Die Pillen sind
  gleich breit (`alignItems: stretch`): Gameface zeichnet unsere Ebene über die Tooltip-Ebene, ein
  Tooltip neben einer schmalen Pille lag sonst unter der breiteren darüber. Kein Doppelpunkt im
  Tooltip: `literal()` macht daraus einen Strich.
- TP-14: Spieler-Schilder sind nur der Name in der Spielerfarbe. `labels.lua` schreibt
  „•#rrggbb Name“ (`Labels._Text`), `DebugToolImports.js` nimmt Punkt und Farbe ab, ändert dafür
  nur `nodeValue` des Textknotens (die Ansicht des Spiels besitzt ihn) und merkt sich den Text.
  Ping und Ablehnung am Objekt tragen jetzt auch die Spielerfarbe.
- Abweichung: Tätigkeit beim Darüberfahren am Schild selbst geht nicht, die Coaster-Labels haben
  keine Maus-Eingabe.
- QA: `_QaLook` hat ein 5. Feld (1–8 Spieler im Cluster, 9 erster Reiter): löst `mouseenter`
  aus. Für Spiel-Komponenten (`Tab`) wirkt das nicht, `ButtonBehaviour` prüft die
  Eingabemethode (ohne echte Maus nicht „Maus und Tastatur“).
- Prüfung: `tests/test_labels_lua.py`; Node-Rendertest der Spielerleiste; Testkopie: Schilder
  und Tooltip fotografiert.

## 2026-11-20 – UX-Overhaul P2, Schritt 1: Fenster im Park links

- Prototyp: Die Komponente `Panel` des Spiels ist fokussierbar und legt Eingabe-Kontexte an (Tab,
  Esc, mit `focusable: false` sogar global für die Reiter). Ohne echte Tastatur nicht prüfbar, ob
  sie dem Bauen Tasten wegnimmt. Gebaut deshalb aus den CSS-Klassen (`Panel_*`, `TabBar_*`, per
  `loadCSS`) mit Spiel-`Tab` und `CloseButton` (beide wie `Button`, den wir schon nutzen).
- `renderParkPanel`: links, 23.5 rem, ab 7.6 rem (unter den runden Knöpfen des Spiels), Inhalt
  26 rem. Kein Hintergrund mehr, `pointerEvents` nur auf dem Fenster. Chat rückt bei offenem
  Fenster nach rechts.
- Reiter Spieler (Anfragen, Spielerzeilen mit `iconButton`, „+ Einladen“ klappt Freunde auf),
  Planen (Brett mit Icon-Knöpfen, Formular hinter „+ Neuer Eintrag“), Verlauf, Einstellungen
  (Für dich, Regeln, Inhalte, Wettbewerb). Entfallen: Park des Hosts, Chat im Fenster, Reiter
  Besuchen (Steuerungstext, „Ich-Sicht“, „Alle einladen“).
- „Besuchen“ zuerst als zweiter Reiter in der Bauleiste: bei UI-Skalierung 1.0 verdeckte er die
  Icon-Knöpfe am Ende der Bauleiste. Jetzt im Fuß des Fensters.
- Gameface-Fund: Knopfreihen in schmalen Spalten quetschen ihren Text, statt umzubrechen. Abhilfe:
  `flexShrink: 0` je Knopf, `buttons(items, wide)`, lange Knöpfe untereinander.
- Prüfung: Node-Rendertest mit Platzhaltern für die Spiel-Module (alle Reiter, Host/Gast/ohne
  Sitzung, Hauptmenü); Testkopie: alle Reiter fotografiert, eigene Skalierung und 1.0, Fenster zu.
- Nicht geprüft: Bauen mit echter Maus bei offenem Fenster, Tooltips der Reiter, „+ Einladen“
  aufgeklappt (braucht einen Klick).

## 2026-11-20 – UX-Overhaul P0: Abnahme-Bilder

- Fund: Einstellungen und Spielstände der Testkopie sind die des Eigners (Windows-Profil, Steam
  Cloud). Nicht umgestellt; stattdessen `Ui._QaLook` (ruft `ThemeConfig.setAccentIndex`,
  `setThemeIndex`, `UIScale.setUserScale` des Spiels nur in der HUD-Ansicht). Danach geprüft:
  die Config-Dateien des Eigners sind unverändert (zuletzt 18.11.).
- Fund: Die Testkopie schreibt `Saves\player` und Autosaves (`*.prkauto2`) in den Spielstand-
  Ordner des Eigners (heute 12:34 und 13:55). Nicht angefasst. Der Eigner ist damit
  einverstanden (2026-11-20).
- Bilder: Akzent Standard, Orange, Lila; Protanopie, Tritanopie; UI-Skalierung 0.7 und 1.0,
  je HUD und Fenster. Behoben:
  - `refreshPalette` lief nur alle 10 Abfragen (3 s) und löste kein Neuzeichnen aus. Direkt nach
    dem Klassenwechsel liefert `getComputedStyle` noch die alten Werte. Jetzt alle 3 Abfragen,
    Neuzeichnen bei Änderung.
  - Meldungsstreifen: feste Lua-Farben → `noticeColor`.
  - Krone im Fenster: weißes SVG auf weißer Karte → `filter` mit `--accentText-filter` wie im Spiel.
  - Spieler-Karte: „Hinbringen“/„Folgen“ in eigener Zeile (liefen aus der Spalte).
- 25 `px`-Linien und -Abstände → `rem`. 1440p/4K nicht fotografierbar (Bildschirm 1080p).
- Bauleiste bei UI-Skalierung 1.0: „Ebene Fahrgeschäfte“ bricht um, auch ohne unseren Reiter.
- Tests: `test_ui_lua.py` (1 neu).

## 2026-11-20 – UX-Overhaul P0, Schritt 3: Akzentfarbe, Bausteine, Lobby-Texte, F8

- JS: `HUD_BG` liest `--accentPanelBackground-triplet`, neu `ACCENT_A` für
  `--accent-triplet` (15 Stellen mit festem `rgba(0, 138, 204, …)` und eine mit
  `rgba(0, 160, 216, …)` ersetzt). Ungültige Tripel fallen auf den Standard zurück.
- Bausteine: `hudPill`, `hudCard`, `keyHint`, `hintBar` (benutzt in Uhr, Meldungen, Chat,
  Mini-Sitzungskarte, Beitrittskarte, `MarkHint`, Chat-Hinweisen).
- Lua: vier Meldungen sagen „Sitzung“ statt „Lobby“; Test angepasst.
- DLL: F8 (`key:dev`) nur mit `pc2coop-dev.flag` (`pc2_developer_mode`). DLL neu gebaut.
- „Für dich“ im Reiter Sitzung: „Mitspieler in der Welt zeigen“ (UI-Aktion `labels`). Fund:
  Der alte Schalter „Namensschilder“ blendet auch Bodenmarke, Sichtkegel, Geist und
  Sperr-Färbung aus; der Text sagt das jetzt.
- Testkopie (1080p, Standard-Akzent): HUD, Meldungskarten, Reiter Sitzung, Schalter aus/an
  fotografiert. Nicht geprüft: F8 ohne Dev-Flag (die Testkopie braucht das Flag für die
  QA-Befehle), andere Akzentfarbe, Farbenblind-Modus, andere Auflösungen.
- Tests: `test_ui_lua.py` (1 neu), `test_session_lua.py` (1 angepasst).

## 2026-11-20 – UX-Overhaul P1, Schritt 4: Ablehnung am Objekt (TP-16)

- Netz: `R|gid|grund|wer` und `deny|name|gid`. Der Host nennt, wer im Weg war (`restore`:
  letzter Bearbeiter, `refuseLocked`/`hostHold`: wer hält). Alte Zeilen ohne `wer` gehen
  weiter („Ein Mitspieler“).
- sync.lua: `sync:rejected|gid|grund|wer`, `sync:hold-denied|name|gid`,
  `sync:hold-lost|wer|gid`; `touchesHeld` gibt die gewinnende Zeile zurück.
- session.lua: `markConflict`, `checkMarks`, `Session.Conflicts`. Eine Marke lebt 5 s. Findet
  `Sync.GidToEntity` das Objekt nicht binnen 0,5 s (z. B. gelöscht), wird eine Karte daraus.
- pc2coopqa.lua: Schild über `labels.lua`, Blinken über `locked` und Kanal-3-Farbe.
- Test in der Testkopie (1080p, Vici nachgestellt, Testkopie mit Watchdog):
  - Vici hält einen Stein, der Host ändert ihn: `sync:rejected|P988|gesperrt|Vici`, Schild
    „Vici baut hier gerade“, Blinken in Vicis Blau sichtbar.
  - Vici verschiebt den Stein, der Host schickt eine veraltete Änderung: „Vici war schneller“.
  - Ohne auffindbares Objekt (gid `nil`): Karte statt Schild.
  - Testaufbau-Fund, kein Fehler der Mod: Ein per API nach dem Sync-Start gesetzter Stein
    hat keine gid-Zuordnung; ein `U` für `P<part>` legt dann einen zweiten Stein an. Im Spiel
    deckt der Start-Abgleich den ganzen Park ab (6 km), neue Objekte laufen über die Hooks.
- Nicht geprüft: echtes Aufnehmen mit der Maus (Werkzeug-Reset), Schild-Höhe bei großen
  Objekten, zwei echte PCs.
- Tests: `tests/test_conflict_lua.py` (6), `test_editor_sync_lua.py` (1 neu, 2 angepasst),
  `test_coop_play_lua.py` (3 angepasst).

## 2026-11-20 – UX-Overhaul P1, Schritt 3: Chat unten links mit Enter

- DLL: `poll_key(VK_RETURN, …, "key:chat")` (nur im Spielfenster, wie F7/F8). DLL neu gebaut.
- Lua:
  - `toast(text, color, loc, kind)` markiert `chat`, `event` (Feed, Emotes, Markierungen,
    Bewertungen) und `notice`.
  - `key:chat` → `Session.OnChatKey` → `Ui.ChatKey` (Zähler `chatKey`).
  - `Session.SetTyping`: Während die Eingabe offen ist, werden `key:v`-Drücke verworfen.
- JS: `ChatArea` ersetzt `Toasts`. Die Eingabe ist das `InputField` des Spiels und wird per
  `focus()` gestartet. Schutz gegen doppeltes Enter (0,8 s nach Senden) und gegen Enter in
  einem Textfeld des Spiels (`document.activeElement`). `MarkHint` zeigt auch „Enter Chat“.
- Fund im UI-Code des Spiels: `InputFieldBase` hört selbst auf `keydown` (Enter/Esc), aber nur
  im Bearbeiten-Modus. Ob Tasten ohne Fokus im HUD ankommen, ist nicht belegt, daher die DLL.
- Tests: `tests/test_chat_lua.py` (3), `test_ui_lua.py` (1).

## 2026-11-20 – UX-Overhaul P1, Schritt 2: Markieren-Radialmenü, Tastenhinweis

- `ContextMenu` ist ein Radialmenü:
  - Einträge `MARK_ITEMS` auf einem Kreis (7 rem) um den Mauspunkt
  - Titel in Akzentfarbe, Mitte schließt
  - am Bildrand eingerückt (11 rem)
- Die Bilder des Spiel-Radialmenüs (Segment-Grafiken) sind nicht nachgebaut, nur seine
  Bildsprache übernommen.
- `MarkHint`: Tastenhinweis im Stil von `InputHintsItem` über der Bauleiste rechts (UX-C1).
- Test in der Testkopie (1080p):
  - QA-Skript ruft `_onNet("key:mdown")` + `Session._MiddleUp(100, 0)` mit festem
    `World.CursorPoint` auf (keine echte Maus).
  - Radialmenü und Hinweis fotografiert.
  - Ohne Mausbewegung öffnet das Menü in der Bildmitte.

## 2026-11-20 – UX-Overhaul P1, Schritt 1: Sitzungs-Cluster, Anfrage-Karte, Verbindungs-Pille

- `VoteBanner`, `InviteBanner` und `CompBanner` sind entfernt. An ihre Stelle treten:
  - `RequestCard` (`pendingRequests`, eine Karte mit Zähler)
  - `ConnectionPill` (`silent`, Desync des Mitspielers, `hostlobby`)
  - die Uhr in `PlayerBar`
- `JoinProgress` zeigt `silent` nicht mehr; das übernimmt die Pille. Beim Mitfahren zeigt
  `PlayerBar` nur die Avatare. `buttons()` gibt `modifiers` an den Spiel-`Button` weiter
  (z. B. `positive`).
- Lua-Toast bei Beitrittsanfrage ohne Bedienweg: „X möchte beitreten.“
- Fund: Das `Icon` des Spiels ignoriert `style` und hat ohne CSS-Klasse die Größe 0. Die Krone
  war deshalb nie zu sehen. Neu ist `glyph()`: ein `div` mit Hintergrundbild, fester Größe und
  `filter: brightness(0) invert(1)` für dunkle Gründe. Im Spiel geprüft.
- Testkopie (1080p) fotografiert:
  - Anfrage-Karte mit Beitrittsanfrage („Zulassen“ grün)
  - Uhr im Cluster, Krone, Uhr- und Multiplayer-Icon
- Die Pille ist nicht im Spiel ausgelöst; dafür fehlt ein Desync bzw. Verbindungsabbruch.

## 2026-11-20 – UX-Overhaul P0, Schritt 2: Schrift und Texte

- Die Schriftgrößen folgen der Skala des Spiels: 0.9, 1, 1.1 und 1.2 rem. Vorher waren es
  zehn Größen von 13 bis 28 px.
- JS-Texte folgen §3/§7 aus `UX_OVERHAUL.md`. UX-A3, UX-A4 und UX-B3 sind für die Mod-Oberfläche
  erledigt. Die Lua-Verlaufstexte mit „Lobby“ und der F8-Dialog sind noch offen.
- Umlaute in 26 Lua-Meldungszeilen (UX-B1). Geändert wurden nur Texte in
  `toast`/`addFeed`/`failJoin`/`_RefuseJoin` und in den Beitrittsgründen. Protokoll-Codes wie
  `laedt` sind unverändert. Ein Test ist angepasst (`tests/test_coop_play_lua.py`).
- Testkopie (1080p) mit offenem und mit geschlossenem Fenster fotografiert: nichts läuft über.
- Fallstrick: `sed -i` stellt hier CRLF auf LF um. Nach jeder Textersetzung
  `git diff --stat` mit und ohne `--ignore-cr-at-eol` vergleichen (ADR-017).

## 2026-11-20 – UX-Overhaul P0, Schritt 1: Farben und Einheiten

- `CoopLayer.js` hat keine festen Farben mehr (außer Spielerfarben). Alle Farben kommen über
  `C(name)` aus den CSS-Variablen des Spiels.
- Alle Größen sind `rem` (`px / 20`). Die Mauskoordinaten des Kontextmenüs bleiben in Pixeln,
  der Abstand zum Rand ist über `remPx()` umgerechnet.
- Abschnittstitel sind fett statt in Großbuchstaben.
- Fund: Gameface ignoriert `var(--…)` im Inline-`background`. Die Mod liest die Werte deshalb
  wie die Bible des Spiels per `getComputedStyle` aus.
- Testkopie (1080p): Fenster, Toasts und Spielerleiste fotografiert, alles lesbar.
- Hinweis zum Bild: Bei offenem Fenster liegt die Spielerleiste unter dem abgedunkelten
  Hintergrund. Das war vorher genauso.
- Noch nicht geprüft: andere Auflösungen, UI-Skalierung, Akzentfarbe, Farbenblind-Modus.

## 2026-11-20 – UX-Overhaul: Analyse und Konzept

- UI-Code des Spiels (entpackt, nur lokal) ausgewertet: `docs/ui-ux/NATIVE_UI.md`. Kernfunde:
  - Das Spiel skaliert über `rem` (1 rem = 20 px bei 1080p × Auto- × Nutzer-Skalierung).
  - Alle Farben sind CSS-Variablen mit 9 Akzentfarben und 3 Farbenblind-Modi.
  - Fertige Bausteine: `Panel`, `DataRow`, Einstellungszeilen, Tooltips, Tastenhinweise,
    Radialmenü, 1234 Icons.
- Befund zur Mod: feste `px` (zehn Schriftgrößen, 13–28 px), 25 Hex-Farben, 4 von vielen
  Spiel-Komponenten genutzt.
- Konzept `docs/ui-ux/UX_OVERHAUL.md`:
  - 32 Berührungspunkte bewertet
  - Zustandsmatrix
  - Ortsregeln
  - Textregeln
  - Machbarkeit
  - Phasen P0–P6
- Dazu ADR-020 (vorgeschlagen) und Ziel-Teil in `DESIGN_SYSTEM.md`. Code unverändert.
- Gefunden: Endet der Host die Sitzung, bekommt der Mitspieler nur eine Verlaufszeile und
  bleibt ohne Hinweis im Park (TP-09/TP-30).

## 2026-11-20 – Dokumentationssystem

- `docs/` neu gegliedert: `project/` (Registry, Überblick, Roadmap, Glossar), `features/`
  (eine Datei pro Bereich, jede Funktion mit `### FEAT-nnn`), `architecture/`, `ui-ux/`,
  `decisions/` (ADR-001–019, nachträglich aus Code und Commits), `development/`, `changelog/`.
- `CLAUDE.md` als Einstieg; Pflicht-Ablauf in `docs/development/AI_WORKFLOW.md`.
- `tools/check_docs.py` + `tests/test_docs.py` (FEAT-221).
- Ältere Dateien `docs/KONZEPT.md`, `NEXT.md`, `COOP_DESIGN.md`, `BRIDGE.md`, `RESEARCH.md`,
  `VALIDATION.md` bleiben als Hintergrund (im Index verlinkt).
- LIESMICH: „Dinge kaufen“ aus „Noch nicht“ entfernt (gibt es seit 1.13.0).

## Bekannte Probleme und Aufräum-Kandidaten

| Was | Wo | Notiz |
|---|---|---|
| Zweig `key:ping` wird nie ausgelöst | `session.lua` | DLL sendet es seit 1.9.0 nicht mehr (Ping per Mittelklick); entfernen |
| Kopfkommentar nennt `['pc2coop'].request` | `CoopLayer.js` Zeile 7–8 | Anfragen gehen über `Engine.sendEvent('PC2Coop_Request')`; Kommentar korrigieren |
| UI-Aktionen ohne Knopf | `ui.lua` `ping`, `board_assign`, `shopclose` | bewusst (Mittelklick, E/Tab) bzw. UX-C3 |
| Legacy-Python und `START.cmd` | `pc2coop/`, `alpha-dist/START.cmd`, `alpha-dist/start.ps1` | FEAT-010, FEAT-218; Entfernen braucht Entscheidung |
| Lua-Texte ohne Umlaute | `session.lua`, `menu.lua` | UX-B1 |
| Besuchen-Reiter „Steuerung“ veraltet | `CoopLayer.js` `renderVisit` | UX-A1 |
| Nicht mit zwei PCs geprüft | alles nach 1.5.0 | siehe ROADMAP |

## 2026-11-19 – 1.13.0

- `figure.lua`: Gast-Figur per `CompilePrefab` (ADR-011); Statue als Rückfall.
- `shop.lua`, Kaufen über den Host (ADR-015); Essen beim Gehen (ADR-016).
- G (Gast-Kamera) gebaut und wieder entfernt (ADR-014).
- Fund: Nach `VisitorCamera` setzt das Spiel die Kamera zurück → Kamera erst später anfordern (`toFigure`).
- Fund: Look darf erst nach Beitritts-Zustimmung gesendet werden (Join-Security-Test).
- Fund: Look-Nachrichten außerhalb der Park-Stage ignorierte der Host → Behandlung auf msg-Ebene.
- Fund: Lokalisierungs-Schlüssel in `span` werden nicht übersetzt → `shown()`.
- 333 Tests.

## 2026-11-19 – 1.12.3 und Pakete

- `replay.lua` `chunkAt` geht zu dem Elternteil mit eigener Volume-ID (Treffer ist ein Chunk-Kind).
- Pakete ohne ACSE (ADR-009), Nexus ohne Skripte, DLL-VERSIONINFO (ADR-010).
- Alle älteren Release-Dateien gelöscht (Wunsch des Eigners).

## 2026-11-18 – 1.10.0 bis 1.12.2

- Bahnen als Baupläne (ADR-006); Lua-Skript-Kanal für QA; `game_watchdog.ps1` nach einem
  Einfrieren des PCs beim Test.
- 1.12.1/1.12.2: Reiter in der TabBar sperrte die HUD → neben die TabBar (ADR-007).
- Avatar-Prefab des Startbildschirms stürzt im Park ab (ADR-012).

## 2026-11-14 bis 2026-11-17 – 1.4.1 bis 1.9.1

- 1.4.2: String-Routine per Byte-Muster statt fester Adresse (FEAT-009, `tools/scan_exe.py`).
- 1.4.3: geordneter Ausgang pro Spieler in der DLL (Steam-Code 25 bei vollem Puffer),
  `tests/native/test_outbox.cpp`.
- 1.5.0: aus dem ersten echten Zwei-Spieler-Test – doppelte Lobby-Meldung von Steam, Park
  doppelt übertragen; Bündeln von Bauplan-Änderungen.
- 1.6.1: Sicherheits-Durchgang (Dateien nur vom Host, Freundes-Prüfung, Dev-Flag für QA).
- 1.9.0: Manifest beim Speichern der Park-Kopie (Aliase), Setter gehen an den Autor zurück.
