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
| Hauptmenü, Reiter „Spielen“ | Kachel „Multiplayer“ neben Karriere (`patchStartTabClass`) | immer | `open` | FEAT-113 |
| Hauptmenü | Mini-Lobby-Karte (`MiniLobby`): „Sitzung öffnen“, „Beenden“/„Verlassen“ | in einer Lobby, Fenster zu | `open`, `leave` | FEAT-034 |
| Park, Bauleiste unten | Reiter „Multiplayer“ rechts neben der Leiste, **nicht** in der TabBar (`patchBuildBar`, ADR-007) | im Park | `open` | FEAT-111 |
| Park, Pausemenü (Esc) | Eintrag „Multiplayer“ (`patchMenuClass`) | im Park | `open` | FEAT-112 |
| Tastatur | **F7** öffnet/schließt das Fenster (`key:menu` → `Ui.Toggle`) | überall | – | FEAT-114 |
| Tastatur | **F8** Entwickler-Dialog (Spiel-Dialog, `menu.lua`) | im Park | – | FEAT-115 |

## 2. Multiplayer-Fenster (`Lobby`, 1320 × 780 px, Mitte)

Kopf: Symbol, Titel („Multiplayer“ / „Deine Sitzung“ / „Sitzung von <Host>“), „n / 8 Spieler · <Park>“.
Fuß: Status-Punkt (Farbe nach Zustand) + Statustext + Knöpfe:

| Knopf | Wann | Aktion |
|---|---|---|
| „Sitzung starten“ | keine Sitzung, Steam da; gesperrt, wenn Hosten nicht geht | `host` |
| „Neu synchronisieren“ | Gast mit Desync | `resync` |
| „Steam-Overlay“ | in Sitzung | `invite_overlay` |
| „Beenden“ (Host) / „Verlassen“ (Gast) | in Sitzung | `leave` |
| „Schließen“ (auch Esc/UI_Cancel) | immer | `close` |

Im Park mit Sitzung hat das Fenster fünf Reiter (`paneltab`): **Team · Besuchen · Planen ·
Verlauf · Sitzung**. Im Hauptmenü und ohne Sitzung gibt es nur die Team-Ansicht.

### 2.1 Team (drei Spalten)

| Spalte | Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|---|
| links | „Möchte beitreten“ | Name + „Zulassen“/„Ablehnen“ (nur Host, nur bei Anfragen) | `approve`, `deny` | FEAT-027 |
| links | „Spieler“ | Profilbild, Name, Krone (Host), Aktivität, Farbe; „Hinbringen“, „Folgen“/„Nicht folgen“; freie Plätze bis 8 | `jump`, `follow` | FEAT-043, FEAT-096, FEAT-097 |
| Mitte | „Wo spielen wir?“ (Menü) | Reiter Gespeichert/Neu/Franchise/Karriere·später; Parkliste („aktualisieren“), Biome + Kreativ/Budget, „Franchise-Menü öffnen“, „Park öffnen“ (Host) | `choose`, `parks`, `start` | FEAT-032, FEAT-046 |
| Mitte | „Park des Hosts“ (Park) | Parkname, Zahlen, Verlauf | – | FEAT-079 |
| Mitte | „Inhalte“ | DLC-Vergleich; Host: „Nur gemeinsame Inhalte“/„Alle Inhalte erlauben“ | `guard` | FEAT-037, FEAT-038 |
| rechts | „Chat“ | Nachrichten, Eingabe „Nachricht an alle“ (Enter sendet) | `chat` | FEAT-035 |
| rechts | „Freunde einladen“ / „Steam-Freunde“ | Freunde mit Status; „Einladen“/„Eingeladen“ (in Sitzung) oder „Beitreten“ (Freund hat Lobby) | `invite`, `join_friend` | FEAT-023, FEAT-024 |

### 2.2 Besuchen

| Bereich | Elemente | Aktionen | FEAT |
|---|---|---|---|
| links „Als Besucher im Park“ | Erklärung oder „Host hat den Besucher-Modus ausgeschaltet“; „Als Besucher losgehen“, „Zurück zum Bauen“, „Ich-Sicht“ | `visitor`, `guest` | FEAT-160, FEAT-164 |
| links „Steuerung“, „Gemeinsam“ | Hilfetexte (siehe UX-Audit A1) | – | – |
| rechts „Fahrgeschäfte“ | Liste nach Entfernung: Name, Art, Werte, Bewertung; „Mitfahren“, „Alle einladen“ | `visitor`+`ride`, `invite_ride` | FEAT-166, FEAT-138 |

### 2.3 Planen

| Bereich | Elemente | Aktionen | FEAT |
|---|---|---|---|
| links „Neu“ | Art (Aufgabe, Baugebiet, Vorschlag, Kommentar, Treffpunkt), Titel, Notiz, „Zuständig: … Wechseln“, Radius 10/20/40 m, „Hinzufügen“; Ort = letzter Ping oder Bildmitte | `board_add` | FEAT-130–134 |
| rechts „Brett des Parks“ | Einträge; „Erledigt“/„Wieder offen“, „Dafür (n)“/„Dagegen (n)“, „Hinbringen“, „Löschen“ | `board_done`, `board_vote`, `goto`, `board_del` | FEAT-130–135 |

### 2.4 Verlauf

| Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Seit deinem letzten Besuch“ | Text | – | FEAT-139 |
| „Meldungen des Parks“ | Pannen/Probleme mit „Hinbringen“ | `goto` | FEAT-140 |
| „Sicherungspunkte“ | Liste; Host: „Zurückholen…“, „Sicherungspunkt erstellen“ | `restore`, `checkpoint` | FEAT-141 |
| „Verlauf der Sitzung“ | Feed | – | FEAT-044 |

### 2.5 Sitzung

| Abschnitt | Elemente | Aktionen | FEAT |
|---|---|---|---|
| „Wettbewerb“ | Host: Thema, Bauduell/Koop gegen die Uhr je 15/30/60 Min.; laufend: Uhr, Bewertung Gestaltung/Technik 1–5, Ergebnis; Host: „Zeit beenden, bewerten“/„Bewertung abschließen“/„Wettbewerb schließen“ | `comp_start`, `comp_rate`, `comp_next`, `goto` | FEAT-145–147 |
| „Regeln dieser Sitzung“ | Host: Schnellwahl „Locker zusammen bauen“/„Geordnet“/„Nur bauen“; Spieltempo, Fremde Bauten, Besucher-Modus | `rule_preset`, `rule` | FEAT-142, FEAT-143 |
| „Deine Rolle“, „Abwesenheit“, „Beitritt“ | Erklärtexte | – | FEAT-144 |

## 3. Im Park ohne Fenster (HUD-Ebene)

| Element | Ort | Wann | Bedienung | FEAT |
|---|---|---|---|---|
| Spielerleiste (`PlayerBar`) | oben rechts, ab 84 px | in Sitzung im Park, nicht beim Mitfahren | Klick auf Mitspieler = folgen | FEAT-090, FEAT-096 |
| Hinweis „Der Host ist im Hauptmenü …“ | unter der Spielerleiste | Host im Hauptmenü | – | FEAT-033 |
| Namensschilder | über dem Blickpunkt der Mitspieler (Coaster-Labels des Spiels, Stil in `DebugToolImports.js`) | Mitspieler im Park, F8 „Namensschilder“ an | – | FEAT-091 |
| Bodenmarke, Sichtkegel, Geist, Sperr-Färbung, Figuren | in der Welt (`viz.lua`) | Mitspieler im Park | – | FEAT-092–094, FEAT-171 |
| Kontextmenü (`ContextMenu`) | an der Maus | nach eigenem Ping (kurzer Mittelklick), nicht im Besuch | `ctx` (invite, ride, take, comment, proposal, area, meet, close) | FEAT-136, FEAT-137 |
| Abstimmungs-Banner (`VoteBanner`) | oben Mitte, 140 px | offene Abstimmung | „Ja“/„Nein“ → `vote` | FEAT-141 |
| Einladungs-Banner (`InviteBanner`) | oben Mitte, 140 px | Testfahrt-Einladung, Fenster zu | „Mitfahren“/„Später“ → `invitation` | FEAT-138 |
| Wettbewerbs-Uhr (`CompBanner`) | oben Mitte, 18 px | Wettbewerb läuft, Fenster zu | – | FEAT-145 |
| Toasts (`Toasts`) | unten links, ab 120 px | Ereignisse; max. 5, je 6 s | – | FEAT-044, FEAT-116 |
| Park-Meldungen | Meldungen des Spiels beim Host (Pannen, Wartung, Proteste; `World.HookNotifications`) gehen als `note` an alle → Verlauf | in Sitzung | – | FEAT-140 |
| Undo/Redo | Spielknopf und Strg+Z (`World.HookHUD`) | immer; gesperrt für fremde Schritte | – | FEAT-074 |
| Spieltempo/Pause | Spielknöpfe (`World.HookHUD`) | Regel „nur Host“ sperrt Gäste | – | FEAT-078 |
| Mittelklick kurz | Welt | im Park | Ping (DLL `key:mup`) | FEAT-095 |

## 4. Besucher-Modus (`VisitorBar`, `EmoteWheel`)

| Element | Ort | Wann | Bedienung | FEAT |
|---|---|---|---|---|
| Hilfezeile | Leiste oben Mitte, 52 px | im Besuch, Fenster zu | Text je Zustand (von hinten / Ich-Sicht / Mitfahren) | FEAT-160 |
| E-Hinweis | in der Leiste | von hinten, vor einem Eingang | „E: <Spieltext>“ + Sperrgrund (Lokalisierung über `shown()`) | FEAT-165 |
| Kaufliste | in der Leiste | Laden-Menü offen | 1–6 oder Klick → `buy`; E/Tab schließt | FEAT-169 |
| Emote-Knöpfe | in der Leiste | im Besuch mit Sitzung | Winken, Jubeln, Lachen, Super, Naja, Übel → `emote` | FEAT-168 |
| „Fahrgeschäfte“ / „Liste schließen“ | in der Leiste | im Besuch | `visitorlist` | FEAT-166 |
| „Ich-Sicht“ / „Ansicht von hinten“ | in der Leiste | im Besuch, nicht beim Mitfahren | `view` | FEAT-164 |
| „Zurück zum Bauen“ | in der Leiste | im Besuch | `visitor` 0 | FEAT-160 |
| Fahrgeschäfte-Liste | unter der Leiste, 1000 px | Liste offen | „Mitfahren“ → `ride`; Sterne 1–5 → `rate`; Vorschlag (Enter) → `rate` | FEAT-166, FEAT-167 |
| Emote-Rad | Bildmitte | T gehalten | Maus/1–6 wählt, T loslassen sendet | FEAT-168 |

Tasten im Besuch (über die DLL, FEAT-195): **WASD** laufen, **Shift** rennen, **Maus** umsehen,
**E** Eingang/Laden, **V** Ich-Sicht ↔ von hinten, **T** Emote-Rad, **1–6** kaufen/Emote,
**Tab** zurück (schließt zuerst das Laden-Menü). In der Ich-Sicht gelten zusätzlich die Tasten
des Spiels (Alt springen, Strg ducken, L Lampe).

## 5. Beitritt (Dialoge des Spiels)

| Element | Wann | Knöpfe | FEAT |
|---|---|---|---|
| `JoinConfirm` „Der Sitzung von … beitreten?“ | Einladung angenommen, Nachfrage an | „Beitreten“ `confirm_join`, „Abbrechen“ `cancel_join` | FEAT-028 |
| `JoinProgress` Karte | während des Beitritts | Text je Phase (joining, silent, asking, awaiting %, loading, lobby) | FEAT-031 |
| `JoinFailed` | Beitritt gescheitert | „Erneut versuchen“ `retry_join`, „Abbrechen“/„Schließen“ `cancel_join` | FEAT-031 |
| `Rejoin` „Du warst eben noch in der Sitzung von …“ | nach Absturz | „Wieder beitreten“ `rejoin`, „Nein“ `forget_rejoin` | FEAT-039 |

## 6. F8-Dialog (`menu.lua`, Dialog des Spiels)

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
| `jump` | sid | Kamera zum Spieler | ja |
| `follow` | sid | folgen an/aus | ja |
| `ping` | – | Ping unter dem Mauszeiger (`Session.Ping`) | **nein** (Ping kommt über Mittelklick) |
| `visitor` | 1/0 | Besuch starten/beenden | ja |
| `guest` | – | Laufmodus des Spiels (`Visitor.WatchGuest`) | ja („Ich-Sicht“) |
| `view` | – | Ich-Sicht ↔ von hinten | ja |
| `ride` | Bahn-Key | mitfahren | ja |
| `emote` | Art | Emote | ja |
| `buy` | 1–6 | kaufen | ja |
| `shopclose` | – | Laden-Menü schließen | **nein** (E/Tab) |
| `visitorlist` | 1/0 | Fahrgeschäfte-Liste | ja |
| `rate` | key\|sterne\|text | bewerten | ja |
| `invite_ride` | key\|name | Testfahrt-Einladung | ja |
| `invitation` | 1/0 | Einladung annehmen/später | ja |
| `paneltab` | team/visit/plan/history/session | Reiter | ja |
| `board_add` | art\|titel\|text\|zuständig\|radius | Brett-Eintrag | ja |
| `board_vote` | id\|1/0 | Vorschlag abstimmen | ja |
| `board_done` | id\|1/0 | Aufgabe erledigt | ja |
| `board_assign` | id\|name | Zuständigen setzen | **nein** (nur beim Anlegen) |
| `board_del` | id | Eintrag löschen | ja |
| `ctx` | Punkt | Kontextmenü-Auswahl | ja |
| `goto` | x\|z | Kamera hin | ja |
| `rule`, `rule_preset` | name\|wert / preset | Regeln | ja |
| `checkpoint`, `restore`, `vote` | – / n / 1/0 | Sicherungspunkte | ja |
| `comp_start`, `comp_next`, `comp_rate` | … | Wettbewerb | ja |
| `guard` | 1/0 | Content Guard | ja |
| `dlc` | Liste | eigene DLCs melden | automatisch (`reportDlc`) |
| `parks` | – | Parkliste neu laden | ja |
| `choose` | save\|id / new\|biom\|kreativ / franchise | Park wählen | ja |
| `start` | – | gewählten Park öffnen | ja |
