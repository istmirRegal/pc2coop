# UI-Inventar

Jeder Ort, an dem der Spieler etwas von PC2Coop sieht oder bedient. Stand 1.13.0.
Darstellung: `probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js` (Komponenten siehe
`docs/ui-ux/COMPONENTS.md`). Ein Klick schickt `request(<aktion>, <arg>)` →
`Engine.sendEvent('PC2Coop_Request', 'n|aktion|arg')` → Aktionstabelle in
`probe/PC2CoopProbe/Main/pc2coop/ui.lua` (`Ui._Request`).

**Regel:** Wer ein Bedienelement hinzufügt, ändert oder entfernt, trägt es hier ein
(und die Aktion in die Tabelle am Ende). `tools/check_docs.py` prüft, dass jede Aktion aus
`ui.lua` hier steht.

## 1. Einstiege in das Multiplayer-Fenster

| Ort | Element | Wann sichtbar | Aktion | FEAT |
|---|---|---|---|---|
| Hauptmenü, Reiter „Spielen“ | Kachel „Multiplayer“ neben Karriere (`patchStartTabClass`); Beschreibung mit Zustand („Sitzung offen · 2/8“, „<Freund> hat eine Sitzung – beitreten“); öffnet die Multiplayer-Seite | immer | `open` | FEAT-113, FEAT-119 |
| Hauptmenü, jede Seite | Sitzungsleiste (`MiniLobby`) oben rechts unter dem Newsletter-Kasten: Avatare, Zustand, „Öffnen“, „Beenden“/„Verlassen“ | in einer Sitzung, Seite nicht offen | `open`, `leave` | FEAT-034 |
| Park, Bauleiste unten | Reiter „Multiplayer“ rechts neben der Leiste, **nicht** in der TabBar (`patchBuildBar`, ADR-007) | im Park | `open` | FEAT-111 |
| Park, Pausemenü (Esc) | Eintrag „Multiplayer“ (`patchMenuClass`); in einer Sitzung dazu „Sitzung verlassen“/„Sitzung beenden“ | im Park | `open`, `leave` | FEAT-112, FEAT-042 |
| Tastatur | **F7** öffnet/schließt das Fenster (`key:menu` → `Ui.Toggle`) | überall | – | FEAT-114 |
| Tastatur | **Enter** öffnet die Chat-Eingabe unten links (`key:chat` → `Ui.ChatKey`) | im Park, Fenster zu, kein Textfeld des Spiels aktiv | `chatinput` | FEAT-116 |
| Tastatur | **F8** Entwickler-Dialog (Spiel-Dialog, `menu.lua`) | nur mit Dev-Flag (`pc2coop-dev.flag`), im Park | – | FEAT-115 |

## 2. Multiplayer-Fenster (`Lobby`)

**Im Park** (UX-Overhaul P2, TP-11): Fenster im Look der Spiel-Fenster am **linken Rand**
(`renderParkPanel`: Klassen `Panel_*`, `TabBar_*`, Spiel-`Tab` und `CloseButton`), 23.5 rem breit,
ab 7.6 rem von oben, Inhalt 26 rem hoch mit Scrollen. **Nicht modal:** kein abgedunkelter Hintergrund,
Bauen geht weiter; der Chat-Bereich rückt rechts daneben.
- Kopf: Symbol, Titel („Multiplayer“ / „Deine Sitzung“ / „Sitzung von <Host>“), Schließen-X (`close`, Esc).
- Reiter (`paneltab`, Symbol mit Tooltip): **Spieler · Planen · Verlauf · Einstellungen**; ohne Sitzung
  nur „Spieler“ mit „Sitzung starten“ (`host`).
- Fuß: Status-Punkt + Statustext, darunter:

| Knopf | Wann | Aktion |
|---|---|---|
| „Besuchen“ | im Park, nicht im Besuch | `visitor` 1 |
| „Neu synchronisieren“ | Gast mit Desync | `resync` |
| „Beenden“ (Host) / „Verlassen“ (Gast) | in Sitzung | `leave` |

**Im Hauptmenü** (UX-Overhaul P3): die Multiplayer-Seite (2.6). Der zentrierte Kasten (66 × 39 rem)
mit drei Spalten (2.1a) ist nur noch Rückfall, wenn die Seite nicht angelegt werden kann. Fuß:
„Sitzung starten“ (`host`), „Steam-Overlay“ (`invite_overlay`), „Beenden“/„Verlassen“ (`leave`),
„Schließen“ (`close`, auch Esc).

### 2.1 Spieler (Park)

| Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Möchte beitreten“ | Name + „Zulassen“/„Ablehnen“ (nur Host, nur bei Anfragen) | `approve`, `deny` | FEAT-027 |
| „Spieler n / 8“ | Zeile: Profilbild, Name, Krone (Host), Tätigkeit, Hinweis bei fehlenden Inhalten; runde Icon-Knöpfe „Hinbringen“ (`takemeto`) und „Folgen“ (`eye`, an = du folgst) | `jump`, `follow` | FEAT-043, FEAT-096, FEAT-097 |
| „+ Einladen“ | klappt „Freunde einladen“ auf: Freunde mit Status, „Einladen“/„Eingeladen“; „Steam-Overlay“ | `invite`, `invite_overlay` | FEAT-023 |

### 2.1a Hauptmenü (drei Spalten)

| Spalte | Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|---|
| links | „Möchte beitreten“ | Name + „Zulassen“/„Ablehnen“ (nur Host, nur bei Anfragen) | `approve`, `deny` | FEAT-027 |
| links | „Spieler“ | Profilbild, Name, Krone (Host), Aktivität, Farbe; „Hinbringen“, „Folgen“/„Nicht folgen“; freie Plätze bis 8 | `jump`, `follow` | FEAT-043, FEAT-096, FEAT-097 |
| Mitte | „Wo spielen wir?“ (Menü, Host) | „Öffne einen Park – alle kommen mit.“; Knöpfe „Sandbox“, „Franchise“ (Spielseiten) | `choose` (franchise) | FEAT-119 |
| Mitte | „Inhalte“ | DLC-Vergleich; Host: „Nur gemeinsame Inhalte“/„Alle Inhalte erlauben“ | `guard` | FEAT-037, FEAT-038 |
| rechts | „Chat“ | Nachrichten, Eingabe „Nachricht an alle“ (Enter sendet) | `chat` | FEAT-035 |
| rechts | „Freunde einladen“ / „Steam-Freunde“ | Freunde mit Status; „Einladen“/„Eingeladen“ (in Sitzung) oder „Beitreten“ (Freund hat Lobby) | `invite`, `join_friend` | FEAT-023, FEAT-024 |

### 2.6 Multiplayer-Seite im Hauptmenü (`MultiplayerPage`, P3)

Eigene Seite im Rahmen des Spiels (Kopf „MULTIPLAYER“, Brotkrumen „‹ Hauptmenü · Multiplayer“,
Esc zurück, schließt das Fenster). Titel, ein Satz, zwei bis drei Spalten:

| Spalte | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Spieler n / 8“ | acht Plätze: Spieler (Profilbild, Name, Krone, Tätigkeit oder fehlende Inhalte), Beitrittsanfragen als wartende Karte „<Name> möchte beitreten“ mit Icon-Knöpfen Haken (Zulassen) und X (Ablehnen), eingeladene Freunde blass, freie Plätze „+ Einladen“; Fuß: Zustand, „Sitzung starten“ bzw. „Steam-Overlay“, „Beenden“/„Verlassen“ | `approve`, `deny`, `host`, `invite_overlay`, `leave` | FEAT-119, FEAT-027 |
| rechts | ohne Sitzung „Steam-Freunde“ (Sitzung zuerst, dann PC2, online; „Beitreten“); nach „+ Einladen“ „Freund einladen“ mit „Einladen“/„Eingeladen“, „Steam-Overlay“, „Fertig“; sonst „Chat“ mit Eingabe „Nachricht“ | `join_friend`, `invite`, `invite_overlay`, `chat` | FEAT-024, FEAT-023, FEAT-035 |
| Host in der Lobby | Kacheln des Spiels (`FrontEndTileButton`) „Sandbox“ (öffnet die Sandbox-Seite des Spiels) und „Franchise“ (wie die Kachel des Spiels) | `choose` (franchise) | FEAT-119 |

### 2.2 Besuchen (Reiter entfallen, P2)

Besuchen ist eine Aktion (TP-23): Knopf „Besuchen“ im Fuß des Fensters. Die Fahrgeschäfte-Liste
öffnet im Besuch die Taste F (§4), „Testfahrt mit allen“ im Markieren-Radialmenü, die Ich-Sicht
wechselt man im Besuch mit V. Der Knopf in der Bauleiste neben „Multiplayer“ wurde verworfen: Bei
UI-Skalierung 1.0 verdeckte er die Icon-Knöpfe am Ende der Bauleiste des Spiels.

### 2.3 Planen

| Bereich | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Brett des Parks“ (Info-Icon: auch als Marker im Park) | Einträge als Zeilen mit Typ-Icon (Aufgabe `clipboard`, Baugebiet `flag`, Vorschlag `thoughts`, Kommentar `pinActive`, Treffpunkt `marker`), Titel, Art · von · → Zuständig, Stimmen, Notiz; runde Icon-Knöpfe: Haken (Erledigt/Wieder offen), Daumen hoch/runter, Zuständig wechseln (offene Aufgaben, Baugebiete), „Hinbringen“, Löschen | `board_done`, `board_vote`, `board_assign`, `goto`, `board_del` | FEAT-130–135 |
| „+ Neuer Eintrag“ → „Neuer Eintrag“ | Auswahl (`ListStepperRow`) „Art“, Titel, Notiz, Auswahl „Zuständig“ (alle, Spieler), Auswahl „Größe“ 10/20/40 m, „Hinzufügen“, „Abbrechen“; Ort = letzte Markierung oder Bildmitte; öffnet sich auch nach einer Brett-Aktion im Radialmenü | `board_add` | FEAT-130–134 |

### 2.4 Verlauf

| Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Meldungen des Parks“ | Zeilen mit Icon, Text, Icon-Knöpfen „Hinbringen“ und „Ausblenden“ (nur auf diesem PC) | `goto` | FEAT-140 |
| „Sicherungspunkte“ (Info-Icon: was Zurückholen bedeutet) | Liste oder „Noch keiner.“; Host: „Zurückholen…“, „Sicherungspunkt erstellen“ | `restore`, `checkpoint` | FEAT-141 |
| „Verlauf der Sitzung“ | Feed, auch „Seit deinem letzten Besuch: …“ (kommt beim Beitritt einmal als Meldung) | – | FEAT-044, FEAT-139 |

### 2.5 Einstellungen

| Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Für dich“ (nur auf deinem PC) | Schalter (`ToggleRow`) „Mitspieler in der Welt zeigen“; Tooltip: Name, Blickrichtung, gehaltenes Objekt, Sperr-Färbung | `labels` | FEAT-091 |
| „Inhalte“ | nur mit Mitspielern: DLC-Vergleich; Host: Schalter „Nur gemeinsame Inhalte“ | `guard` | FEAT-037, FEAT-038 |
| „Wettbewerb“ | Host: Thema, Bauduell/Koop gegen die Uhr je 15/30/60 Min.; laufend: Uhr, Bewertung Gestaltung/Technik 1–5, Ergebnis; Host: „Zeit beenden, bewerten“/„Bewertung abschließen“/„Wettbewerb schließen“ | `comp_start`, `comp_rate`, `comp_next`, `goto` | FEAT-145–147 |
| „Regeln dieser Sitzung“, Info-Icon mit der Rolle im Tooltip | Auswahl (`ListStepperRow`) „Schnellwahl“ Locker/Geordnet/Nur bauen (+ „Eigene“), „Spieltempo und Pause“ alle/nur der Host, „Fremde Bauten abreißen“ erlaubt/erst fragen; Schalter „Besucher-Modus“; Erklärung je Zeile im Tooltip; Mitspieler: gesperrt, Tooltip „Nur der Host ändert Regeln.“ | `rule_preset`, `rule` | FEAT-142–144 |
| Fuß | „Beenden“ (Host, Tooltip: endet für alle) mit Nachfrage „Für alle beenden?“, solange noch jemand da ist; „Verlassen“ (Tooltip: Park läuft beim Host weiter) | `leave` | FEAT-042, FEAT-144 |

## 3. Im Park ohne Fenster (HUD-Ebene)

| Element | Ort | Wann | Bedienung | FEAT |
|---|---|---|---|---|
| Sitzungs-Cluster (`PlayerBar`): Avatar, Name, Krone, Zustands-Icon; Tätigkeit und „Klicken zum Folgen“ im Tooltip; einmal 5 s „Alle sind da“, wenn niemand mehr lädt; darunter die Wettbewerbs-Uhr | oben rechts, ab 4.2 rem | in Sitzung im Park; beim Mitfahren nur Avatare | Klick auf Mitspieler = folgen | FEAT-090, FEAT-096 |
| Verbindungs-Pille (`ConnectionPill`): keine Verbindung zum Host / nicht synchron (+ „Neu synchronisieren“) / Host im Hauptmenü | oben Mitte, 5 rem | nur bei Problemen, Fenster zu | `resync` | FEAT-033, FEAT-031 |
| Namensschilder: nur der Name in der Spielerfarbe | über dem Blickpunkt der Mitspieler (Coaster-Labels des Spiels, Stil in `DebugToolImports.js`) | Mitspieler im Park, „Für dich“ an (Reiter Einstellungen) | – | FEAT-091 |
| Bodenmarke, Sichtkegel, Geist, Sperr-Färbung, Figuren | in der Welt (`viz.lua`) | Mitspieler im Park | – | FEAT-092–094, FEAT-171 |
| Ablehnung am Objekt: Schild „<Name> baut hier gerade“ / „war schneller“ / „hat das gerade geändert“, Objekt blinkt in der Farbe des Mitspielers | 4 m über dem Objekt (Coaster-Labels), Blinken über Sperr-Färbung | 5 s nach einer zurückgenommenen eigenen Änderung (Blinken 2 s); ohne Objekt als Karte im Chat-Bereich | – | FEAT-082 |
| Markieren-Radialmenü (`ContextMenu`): Titel (Fahrgeschäft oder „Markierung“), Kreise mit Spiel-Icons „Testfahrt mit allen“, „Mitfahren“, „Übernahme von …“, „Kommentar“, „Vorschlag“, „Baugebiet“, „Treffpunkt“; Mitte = Schließen | um die Maus | nach eigener Markierung (kurzer Mittelklick), nicht im Besuch | `ctx` (invite, ride, take, comment, proposal, area, meet, close) | FEAT-136, FEAT-137 |
| Tastenhinweise „[Enter] Chat“ und „[Mittelklick] Markieren“ (`MarkHint`) | unten rechts über der Bauleiste | in Sitzung im Park, Fenster zu, kein Besuch, kein Radialmenü offen | – | FEAT-095 |
| Anfrage-Karte (`RequestCard`), eine zur Zeit mit Zähler „1 von n“: Beitrittsanfrage (Host) „Zulassen“/„Ablehnen“ → `approve`/`deny`; Abstimmung „Ja“/„Nein“ → `vote`; Testfahrt „Mitfahren“/„Später“ → `invitation`; nach einem Bauduell „Bewerten“ → `paneltab` + `open` | oben Mitte, 7.5 rem | etwas wartet auf eine Antwort, Fenster zu | siehe Spalte links | FEAT-027, FEAT-141, FEAT-138, FEAT-147 |
| Chat-Bereich (`ChatArea`): Chat-Zeilen (Name in Spielerfarbe), Spieler-Ereignisse (hell), darüber Meldungs-Karten | unten links, ab 6 rem; bei offenem Fenster im Park rechts daneben | Zeilen 10 s (max. 6), Karten 6 s (max. 3) | – | FEAT-044, FEAT-116 |
| Chat-Eingabe (`ChatArea`): letzte 12 Zeilen, Feld „Nachricht an alle“, Hinweise „[Enter] Senden“, „[Esc] Schließen“ | unten links | nach Enter im Park, Fenster zu | `chat`, `chatinput` | FEAT-035, FEAT-116 |
| Park-Meldungen | Meldungen des Spiels beim Host (Pannen, Wartung, Proteste; `World.HookNotifications`) gehen als `note` an alle → Verlauf | in Sitzung | – | FEAT-140 |
| Undo/Redo | Spielknopf und Strg+Z (`World.HookHUD`) | immer; gesperrt für fremde Schritte | – | FEAT-074 |
| Spieltempo/Pause | Spielknöpfe (`World.HookHUD`) | Regel „nur Host“ sperrt Gäste | – | FEAT-078 |
| Mittelklick kurz | Welt | im Park | Ping (DLL `key:mup`) | FEAT-095 |

## 4. Besucher-Modus (`VisitorHud`, `VisitorRides`, `EmoteWheel`)

Wie der Laufmodus des Spiels (UX-Overhaul P4, TP-24): keine Leiste oben. Die Bauleiste
(`BrowserModule_root`) und die Bau-Tastenhinweise des Spiels (`HUD_promptsList`) sind im Besuch
ausgeblendet (`syncVisitHud`), beim Mitfahren nicht (dort liegen die Knöpfe der Fahrkamera).

| Element | Ort | Wann | Bedienung | FEAT |
|---|---|---|---|---|
| Tastenhinweise | unten rechts über der Statusleiste | im Besuch, Fenster zu | von hinten: WASD Laufen, Umschalt Rennen, E Benutzen, F Fahrgeschäfte, T Emotes, V Ich-Sicht, Tab Zurück; Ich-Sicht: WASD, Alt Springen, Strg Ducken, L Lampe, E Shop, F, T, V Ansicht, Tab; Laden offen: 1–6 Kaufen, E Schließen | FEAT-160, FEAT-195 |
| „Du fährst <Bahn>“ | oben Mitte | beim Mitfahren | – | FEAT-166 |
| E-Hinweis | unter der Bildmitte | von hinten, vor einem Eingang | [E] + Spieltext, darunter der Sperrgrund (Lokalisierung über `shown()`) | FEAT-165 |
| Kauf-Panel „Kaufen“ | unten rechts über den Tastenhinweisen | Laden-Menü offen | Zeilen mit Taste, Artikel, Preis; 1–6 oder Klick → `buy`; E/Tab schließt | FEAT-169 |
| Fahrgeschäfte-Panel | links wie das Multiplayer-Fenster | F (oder X schließt) | Zeilen: Name, Art, Entfernung, Wartende, Werte, Bewertung als Sterne des Spiels (`Stars`); „Mitfahren“ → `ride`; „Deine Wertung“: fünf Sterne zum Klicken (gewählte gefüllt in Akzentfarbe) → `rate`; Vorschlag (Enter) → `rate`; Maus frei, solange offen | FEAT-166, FEAT-167 |
| Emote-Rad | Bildmitte, Kreise auf einem Ring wie das Markieren-Radialmenü | T gehalten | Gast-Icons des Spiels (`guestThoughts`) mit Taste 1–6 und Wort; Maus/1–6 wählt (größer, Akzentfarbe), T loslassen sendet | FEAT-168 |

Tasten im Besuch (über die DLL, FEAT-195): **WASD** laufen, **Shift** rennen, **Maus** umsehen,
**E** Eingang/Laden, **F** Fahrgeschäfte, **V** Ich-Sicht ↔ von hinten, **T** Emote-Rad, **1–6**
kaufen/Emote, **Tab** zurück (schließt zuerst das Laden-Menü). Entfallen (P4): die Emote-Knöpfe
(das Rad reicht) und die Knöpfe „Ich-Sicht“ und „Zurück zum Bauen“ (V, Tab). In der Ich-Sicht gelten zusätzlich die Tasten
des Spiels (Alt springen, Strg ducken, L Lampe).

## 5. Beitritt (Dialoge des Spiels)

| Element | Wann | Knöpfe | FEAT |
|---|---|---|---|
| `JoinConfirm` „Der Sitzung von … beitreten?“ | Einladung angenommen, Nachfrage an | „Beitreten“ `confirm_join`, „Abbrechen“ `cancel_join` | FEAT-028 |
| `JoinProgress` Karte | während des Beitritts | Text je Phase (joining, silent, asking, awaiting %, loading, lobby) | FEAT-031 |
| `JoinFailed` | Beitritt gescheitert | „Erneut versuchen“ `retry_join`, „Abbrechen“/„Schließen“ `cancel_join` | FEAT-031 |
| `Rejoin` „Du warst eben noch in der Sitzung von …“ | nach Absturz | „Wieder beitreten“ `rejoin`, „Nein“ `forget_rejoin` | FEAT-039 |

## 6. F8-Dialog (`menu.lua`, Dialog des Spiels)

Nur für Entwickler: Die DLL meldet F8 nur mit `pc2coop-dev.flag` (TP-31). Spieler sehen ihn nicht.

Hauptseite: Status-Text (Rolle, Spieler, Zähler, letzte Ereignisse) und „Raum hosten“,
„Freunde einladen“, „Sitzung beenden“/„Sitzung verlassen“, „Zu <Name>“, „Entwickler“, „Schliessen“.
Entwickler-Seite: technische Werte und „API-Rekorder an/aus“, „Namensschilder an/aus“,
„Sync pausieren/fortsetzen“, „Zurueck“. (FEAT-115, FEAT-214)

## 7. Alle UI-Aktionen (`ui.lua`)

| Aktion | Argument | Wirkung | Knopf in JS? |
|---|---|---|---|
| `hello` | hud/frontend | Oberfläche neu gestartet, Zustand neu senden | automatisch |
| `open` / `close` | – | Fenster öffnen/schließen | ja |
| `host` | – | `Session.Host` | ja |
| `invite_overlay` | – | Steam-Overlay | ja |
| `invite` | sid | Freund einladen | ja |
| `join_friend` | sid | Lobby eines Freundes beitreten | ja |
| `leave` | – | Sitzung verlassen/beenden | ja |
| `resync`, `retry_join` | – | `Session.Resync` | ja |
| `cancel_join`, `confirm_join` | – | Beitritt abbrechen/bestätigen | ja |
| `approve`, `deny` | sid | Beitrittsanfrage | ja |
| `rejoin`, `forget_rejoin` | – | Wiederbeitritt | ja |
| `chat` | Text | Chat senden | ja |
| `chatinput` | 1/0 | Chat-Eingabe offen/zu (`Session.SetTyping`) | ja (automatisch beim Öffnen/Schließen) |
| `labels` | 1/0 | Mitspieler in der Welt zeigen an/aus (`Menu.labelsEnabled`) | ja |
| `jump` | sid | Kamera zum Spieler | ja |
| `follow` | sid | folgen an/aus | ja |
| `ping` | – | Ping unter dem Mauszeiger (`Session.Ping`) | **nein** (Ping kommt über Mittelklick) |
| `visitor` | 1/0 | Besuch starten/beenden | ja |
| `guest` | – | Laufmodus des Spiels (`Visitor.WatchGuest`) | nein (seit P2; im Besuch V) |
| `view` | – | Ich-Sicht ↔ von hinten | ja |
| `ride` | Bahn-Key | mitfahren | ja |
| `emote` | Art | Emote | ja |
| `buy` | 1–6 | kaufen | ja |
| `shopclose` | – | Laden-Menü schließen | **nein** (E/Tab) |
| `visitorlist` | 1/0 | Fahrgeschäfte-Panel (`Visitor.SetList`) | ja (X am Panel; öffnen mit F) |
| `rate` | key\|sterne\|text | bewerten | ja |
| `invite_ride` | key\|name | Testfahrt-Einladung | nein (seit P2; Radialmenü „Testfahrt mit allen“ über `ctx`) |
| `invitation` | 1/0 | Einladung annehmen/später | ja |
| `paneltab` | team/plan/history/session (visit veraltet, zeigt „Spieler“) | Reiter | ja |
| `board_add` | art\|titel\|text\|zuständig\|radius | Brett-Eintrag | ja |
| `board_vote` | id\|1/0 | Vorschlag abstimmen | ja |
| `board_done` | id\|1/0 | Aufgabe erledigt | ja |
| `board_assign` | id\|name | Zuständigen setzen | ja (Reiter Planen, Icon-Knopf) |
| `board_del` | id | Eintrag löschen | ja |
| `ctx` | Punkt | Kontextmenü-Auswahl | ja |
| `goto` | x\|z | Kamera hin | ja |
| `rule`, `rule_preset` | name\|wert / preset | Regeln | ja |
| `checkpoint`, `restore`, `vote` | – / n / 1/0 | Sicherungspunkte | ja |
| `comp_start`, `comp_next`, `comp_rate` | … | Wettbewerb | ja |
| `guard` | 1/0 | Content Guard | ja |
| `dlc` | Liste | eigene DLCs melden | automatisch (`reportDlc`) |
| `parks` | – | Parkliste neu laden | nein (seit P3, Park über die Spielseiten) |
| `choose` | save\|id / new\|biom\|kreativ / franchise | Park wählen | nur franchise (Kachel) |
| `start` | – | gewählten Park öffnen | nein (seit P3) |
| `opening` | – | Host öffnet einen Park auf den Spielseiten: Wahl „einen Park“, startet (alle sehen „<Host> öffnet einen Park“) | automatisch (Ladeseiten des Spiels) |
