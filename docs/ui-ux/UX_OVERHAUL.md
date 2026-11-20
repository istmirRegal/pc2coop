# UX-Overhaul: Inventar, Audit, Zielbild

Status: **Konzept, wartet auf Freigabe des Eigners** (2026-11-20). Noch nichts davon ist im Code.
Entscheidung dazu: ADR-020. Analyse des Spiels: `docs/ui-ux/NATIVE_UI.md`.
Ersetzt als Arbeitsgrundlage `docs/ui-ux/UX_AUDIT.md` (dessen IDs sind unten zugeordnet).

## Kurzfassung

1. **Die Mod baut das Spiel nicht nach, sie benutzt es.** Farben über die Variablen des Spiels
   (`var(--accent)` …), Größen in `rem`, Fenster, Zeilen, Tooltips, Tastenhinweise und Icons
   aus dem Spiel. Damit folgt die Mod Auflösung, UI-Skalierung, Akzentfarbe und Farbenblind-Modus.
2. **Jede Art von Information hat einen festen Ort** – in Park, Besuch und Hauptmenü derselbe.
3. **Weniger eigene Oberfläche:** Park-Auswahl über die Menüs des Spiels, Tasten in der
   Hinweisleiste statt in Sätzen, Erklärungen als Tooltip, Besuchen als Aktion statt Reiter.
4. **Jeder Zustand ist sichtbar** – Verbinden, Warten, Fehler, Host weg – mit einer Aktion dazu.
5. **Ein Begriff pro Sache** und Texte, die nach Spiel klingen.

## 1. Maßstab

Qualitätsziele (vom Eigner): native Integration, intuitive Bedienung, Konsistenz, Reduktion,
Qualität im Detail, Funktion vor Dekoration.

Es gibt nicht *die eine* Quelle, die alle Designer benutzen. Für diese Mod gilt diese Rangfolge:

| Rang | Quelle | Wofür |
|---|---|---|
| 1 | **Planet Coaster 2 selbst** (Bible, Komponenten, Variablen; `NATIVE_UI.md`) | Aussehen, Bausteine, Orte, Tonfall. Bei Widerspruch gewinnt das Spiel. |
| 2 | Nielsens 10 Usability-Heuristiken | Prüfliste für jeden Berührungspunkt |
| 3 | Don Norman, *The Design of Everyday Things* | Affordances, Signifier, Mapping, Feedback, Constraints, mentales Modell |
| 4 | Apple Human Interface Guidelines | allgemeine Regeln: Konsistenz, stabile Positionen, Hierarchie, Feedback |
| 5 | Game Accessibility Guidelines, Xbox Accessibility Guidelines, Celia Hodent (*The Gamer's Brain*) | Spiele-Eigenheiten: Lesbarkeit, Farbe nie allein, Eingaben, Lernkurve |

## 2. Vorgehen

Für jeden Berührungspunkt (TP) wird getrennt, was **implementiert** ist, was der Spieler
**sieht**, was er **tun kann** und was er **tun will**. Bewertet wird in sieben Kriterien
(G = gut, M = mittel, S = schlecht), dann folgt eine Entscheidung:
**Keep** · **Refine** · **Redesign** · **Relocate** · **Remove** · **Add**.

Grundfrage pro Funktion: *Wie erwartet ein Spieler, das zu tun?* – nicht *wo ist noch Platz für
einen Knopf?* Reihenfolge der Lösungen: (C) im Spiel schon vorhanden → (B) direkt im Kontext →
(A) eigener Knopf, eigenes Fenster.

## 3. Begriffe

Das mentale Modell des Spielers: *Ich spiele meinen Park mit Freunden. Einer ist Gastgeber,
die anderen kommen dazu.*

| Begriff | Bedeutung | ersetzt |
|---|---|---|
| **Sitzung** | die Gruppe, von Start bis Ende, in Hauptmenü und Park | „Lobby“, „Raum“ (UX-B3) |
| **Host** | wer die Sitzung gestartet hat (Krone) | „Gastgeber“ gemischt |
| **Mitspieler** | alle anderen | „Gast“ (verwechselbar mit Parkgästen) |
| **Sitzung starten / beitreten / verlassen / beenden** | die vier Verben | „Lobby erstellen“, „Diesen Park hosten“, „Raum hosten“ |
| **Besuchen** | als Figur durch den Park laufen | „Besucher-Modus“, „Ich-Sicht (Spiel)“ (UX-A3) |
| **Markieren** | Mittelklick-Ping | „Ping“ |
| **Hinbringen** | Kamera zu Ort/Spieler (Spielbegriff, Icon `takemeto.svg`) | „Hinspringen“ |

Offen für den Eigner: „Lobby“ als Name nur für die Wartephase im Hauptmenü behalten? (Vorschlag: nein.)

## 4. Inventar und Audit

Kriterien: **Sinn** (funktionale Sinnhaftigkeit), **IA** (Informationsarchitektur),
**Hier.** (visuelle Hierarchie), **Kons.** (Konsistenz), **Inter.** (Interaktion),
**Feedb.** (Feedback), **Spiel** (Integration ins Spiel). Ist-Zustand: `docs/ui-ux/UI_INVENTORY.md`.

| TP | Bereich | Berührungspunkt | Sinn | IA | Hier. | Kons. | Inter. | Feedb. | Spiel | Entscheidung |
|---|---|---|---|---|---|---|---|---|---|---|
| TP-01 | Einstieg | Multiplayer entdecken | G | M | M | M | M | S | M | Refine |
| TP-02 | Hauptmenü | Kachel „Multiplayer“ | G | G | M | G | G | M | G | Refine |
| TP-03 | Hauptmenü | Multiplayer-Fenster (Lobby) | M | S | S | S | M | M | S | Redesign |
| TP-04 | Hauptmenü | Mini-Lobby-Karte | G | M | M | M | M | M | S | Redesign |
| TP-05 | Einladungen | Freunde einladen, Steam-Overlay | G | M | M | M | M | M | M | Redesign |
| TP-06 | Spielerverwaltung | Beitrittsanfragen | G | S | M | M | M | S | M | Relocate |
| TP-07 | Verbindung | Beitritts-Dialoge | G | G | M | G | G | M | G | Refine |
| TP-08 | Übergänge | Lobby → Park | G | M | M | M | G | M | M | Refine |
| TP-09 | Verbindung | Verbindungs- und Sync-Zustand | G | S | S | M | M | S | S | Redesign |
| TP-10 | Einstieg | Wege ins Fenster im Park | G | G | M | M | G | M | G | Refine |
| TP-11 | Gameplay | Multiplayer-Fenster im Park | M | M | M | S | M | M | S | Redesign |
| TP-12 | Spielerverwaltung | Reiter „Team“ | M | S | M | M | M | M | S | Redesign |
| TP-13 | Gameplay | Spielerleiste | G | G | M | M | S | M | M | Refine |
| TP-14 | Interaktionen | Mitspieler in der Welt | G | G | M | M | G | G | M | Refine |
| TP-15 | Interaktionen | Markieren + Kontextmenü | G | M | M | S | S | M | S | Redesign |
| TP-16 | Interaktionen | Konflikte, abgelehnte Änderungen | G | M | S | M | M | S | M | Refine |
| TP-17 | Interaktionen | Reiter „Planen“ (Brett) | G | M | M | M | M | M | S | Refine |
| TP-18 | Gameplay | Reiter „Verlauf“ | M | M | M | M | M | M | S | Refine |
| TP-19 | Interaktionen | Abstimmungs-Banner | G | M | M | S | M | M | S | Redesign |
| TP-20 | Einstellungen | Regeln der Sitzung | G | G | M | S | M | M | S | Refine |
| TP-21 | Gameplay | Wettbewerb | G | M | M | M | M | M | M | Refine |
| TP-22 | Benachrichtigungen | Toasts | G | S | M | S | M | M | S | Redesign |
| TP-23 | Gameplay | Reiter „Besuchen“ | M | S | M | S | M | M | S | Relocate |
| TP-24 | Gameplay | Besucher-Leiste | G | M | S | S | S | M | S | Redesign |
| TP-25 | Interaktionen | E-Hinweis, Kaufliste | G | G | M | M | M | M | M | Refine |
| TP-26 | Interaktionen | Emote-Rad | G | G | G | M | G | M | M | Refine |
| TP-27 | Gameplay | Fahrgeschäfte-Liste, Bewertung | G | M | M | M | M | S | M | Redesign |
| TP-28 | Benachrichtigungen | Testfahrt-Einladung | G | M | M | M | G | M | M | Relocate |
| TP-29 | Gameplay | gesperrte Spielknöpfe (Tempo, Rückgängig) | G | G | G | G | M | S | G | Refine |
| TP-30 | Fehlerzustände | Verlassen, Beenden, Host beendet | G | M | M | M | M | S | M | Refine + Add |
| TP-31 | Einstellungen | F8-Dialog | S | S | M | S | M | M | M | Remove (für Spieler) |
| TP-32 | Einstellungen | persönliche Einstellungen | – | S | – | – | – | – | – | Add |

### Befunde und Ziel je Berührungspunkt

**TP-01 Entdecken.** Heute erfährt man vom Multiplayer nur über die Kachel. Ziel: Die Kachel
zeigt, ob Freunde gerade eine Sitzung haben („Vici spielt – beitreten“). Das ist ein soziales
Signal, ganz ohne Hilfetext.

**TP-02 Kachel.** Bleibt. Unterzeile mit Zustand („Sitzung offen · 2/8“), F7 nicht nötig.

**TP-03 Hauptmenü-Fenster.** Heute ist es ein schwebender Kasten über dem Hauptmenü. Er hat
einen anderen Stil, „Freier Platz“ steht siebenmal untereinander und Knöpfe brechen um. Er
enthält außerdem eine eigene Park-Auswahl, die die Seiten des Spiels nachbaut (UX-A6:
„Karriere · später“). Ziel: eine **Hauptmenü-Seite „Multiplayer“** im Rahmen des Spiels
(Brotkrumen, Fußleiste mit Esc).
- *Ohne Sitzung:* Titel, ein Satz, Kachel „Sitzung starten“, Freundesliste (wer eine Sitzung
  hat, steht oben, mit „Beitreten“).
- *In der Sitzung:* 8 Spielerplätze als Karten, Chat, Hinweis „Öffne einen Park – alle kommen
  mit.“ Knöpfe springen in die Spielseiten („Fortsetzen“, „Meine Parks“, „Neuer Park“,
  „Franchise“). **Remove:** eigene Parkliste, Biom-Wahl, „Karriere · später“. Der Host wählt den
  Park so, wie er es gewohnt ist.

**TP-04 Mini-Lobby.** Ziel: eine **Sitzungsleiste** an fester Stelle auf allen Hauptmenü-Seiten
(oben rechts unter den Einstellungs-Icons). Sie zeigt Avatare, Krone, ungelesene Chats,
„Öffnen“ und bleibt sichtbar, während der Host durch die Spielseiten geht.

**TP-05 Einladen.** Heute: Liste aller Steam-Freunde im Fenster plus Knopf „Steam-Overlay“.
Ziel (Variante B): **Klick auf einen freien Platz** öffnet die Freundesauswahl im Stil von
`FrontEndFriendsListPopUp` (online zuerst, wer PC2 spielt zuerst). Eingeladene Freunde stehen
als blasse Karte im Platz, bis sie antworten (Mapping: Platz = Person). Das Steam-Overlay ist nur
noch eine Nebenaktion im Popup.

**TP-06 Beitrittsanfragen.** Heute stehen sie nur im Fenster, links oben, und nur, wenn der Host
es offen hat. Ziel: Sie erscheinen in der **Anfrage-Karte** (siehe TP-19) und zusätzlich als
wartende Karte im Platz.

**TP-07 Beitritts-Dialoge.** Die Spiel-Dialoge passen (Keep). Refine:
- Fortschritt als Schritte mit `ProgressBar`: Verbinden → Zustimmung → Park empfangen n % → Laden.
- „Abbrechen“ ist in jedem Schritt da.
- Ein Fehler zeigt immer Grund und „Erneut versuchen“. Das ist heute schon großteils so.

**TP-08 Lobby → Park.** Der Lade-Bildschirm gehört dem Spiel. Ziel:
- Vorher sehen alle in der Sitzungsleiste: „Vici öffnet ‚Seepark‘“.
- Nachher zeigt der Sitzungs-Cluster, wer noch lädt.
- Ist niemand mehr am Laden, erscheint einmal „Alle sind da“.

**TP-09 Verbindung.** Heute ist die Statuszeile unten im Fenster der einzige Ort (UX-E3). Ist das
Fenster zu, gibt es nur Toasts. Endet der Host die Sitzung, sieht der Mitspieler nur eine Zeile
im Verlauf und bleibt still im Park. Ziel:
- Der eigene Zustand zum Host erscheint als **Pille oben Mitte** im Stil von `OnlineNotification`
  („Keine Verbindung zum Host · 12 s“, „Nicht synchron [Neu synchronisieren]“).
- Der Zustand jedes Mitspielers ist ein Icon in der Spielerleiste.
- Host weg oder Sitzung beendet: ein **Dialog** mit „Allein weiterspielen“ / „Ins Hauptmenü“.
  Was mit dem Park des Mitspielers passiert, ist vorher im Spiel zu prüfen.

**TP-10 Wege ins Fenster.** Bauleiste, Pausemenü, F7 und Kachel bleiben. Refine: Der Reiter in
der Bauleiste zeigt das Spiel-Icon `collaborate.svg` und die Taste F7 als Tastensymbol (UX-C5).

**TP-11 Fenster im Park.** Heute ist es ein zentrierter Kasten von 1320 × 780 px. Er verdeckt den
Park und hat eigene Farben. Ziel: das Spiel-**`Panel`** (Titelleiste in Akzentfarbe, Icon,
Schließen, Symbol-Reiter mit Tooltip). Die Breite ist ein Vielfaches von 23.5 rem.
- **Ort: links**, damit es nicht mit den Info-Fenstern des Spiels kollidiert. Die stapeln sich
  rechts und werden beim Bauen gebraucht.
- Es ist nicht modal: Man baut weiter, während es offen ist.
- Reiter: **Spieler · Planen · Verlauf · Einstellungen**.

**TP-12 Reiter „Team“.** Heute stehen fünf Abschnitte in drei Spalten.
- **Remove:** „Park des Hosts“ (doppelt zur Statusleiste des Spiels).
- **Relocate:**
  - Chat → Chat-Bereich (TP-22)
  - Freunde → Platz-Klick (TP-05)
  - Inhalte → Icon am Spieler, nur bei Unterschied; Schalter unter Einstellungen
- **Bleibt als Reiter „Spieler“:** Spielerzeilen (`DataRow`) mit Icon-Knöpfen „Hinbringen“
  (`takemeto.svg`) und „Folgen“ (`eye.svg`), dazu Krone und Zustand. Freie Plätze stehen am Ende
  als ein „+ Einladen“, nicht als siebenmal „Freier Platz“.

**TP-13 Spielerleiste.** Ort oben rechts bleibt.
- Refine: Spiel-Look (Pille wie die Statusleiste), Avatar, Name, Krone, Zustands-Icon.
- Die Tätigkeit steht im Tooltip statt abgeschnitten im Text.
- Folgen zeigt `eye.svg` und im Tooltip „Klicken: folgen“ (UX-C2).
- Die Leiste bleibt im Besuch und beim Mitfahren sichtbar (UX-D4), notfalls kompakt.

**TP-14 Mitspieler in der Welt.** Namensschilder zeigen heute bis zu vier Zeilen
(„• Vici – geht als Besucher durch den Park“) und überdecken sich. Ziel: nur der Name in der
Spielerfarbe. Die Tätigkeit erscheint erst beim Darüberfahren. Bodenmarke, Sichtkegel, Geist und
Figur bleiben (Keep).

**TP-15 Markieren und Kontextmenü.** Das Menü erscheint nur nach einem kurzen Mittelklick und
ist nirgends erklärt (UX-C1). Es ist eine dunkle Liste, die es im Spiel so nicht gibt. Ziel:
- Mittelklick bleibt „Markieren“ und öffnet ein **Radialmenü im Stil des Spiels** (Alt-Radialmenü)
  um den Punkt, mit höchstens 6 Einträgen mit Icon.
- Im Sitzungsbetrieb steht „Mittelklick Markieren“ in der Tastenhinweisleiste.
- Aktionen an einem Objekt („Übernahme anfragen“, „Testfahrt mit allen“) kommen zusätzlich ins
  **Info-Fenster des Objekts** (Variante C; Prototyp nötig).

**TP-16 Konflikte.** Heute springt ein abgelehntes Objekt zurück, und nur ein Toast erklärt es
(UX-E2). Ziel: Das Objekt pulsiert kurz (`highlightPulse`-Stil). Eine kurze Meldung nennt Grund
und Spieler: „Vici baut hier gerade“.

**TP-17 Planen.**
- Einträge als `DataRow` mit Typ-Icon, Hinbringen, Daumen (`thumbsUp.svg`) und Erledigt-Haken.
- Das Formular „Neu“ ist eingeklappt und öffnet sich über „+“.
- Zuständig kann man nachträglich ändern (UX-C3); der Radius ist ein `ListStepper`.

**TP-18 Verlauf.**
- Park-Meldungen erscheinen wie die Meldungszeilen des Spiels (`Notification`: Hinbringen, Verwerfen).
- „Seit deinem letzten Besuch“ kommt einmal als Meldung beim Beitritt statt als Abschnitt.
- Sicherungspunkte bleiben hier; nur der Host sieht die Knöpfe.

**TP-19 Abstimmungs-Banner.** Abstimmung und Testfahrt-Einladung liegen heute beide bei 140 px
oben Mitte und überdecken sich (UX-D2). Ziel: **eine Anfrage-Karte** für alles, was eine Antwort
braucht:
- Inhalte: Beitritt, Abstimmung, Testfahrt, Übernahme, Wettbewerb bewerten.
- Ein Platz, eine Warteschlange („1 von 3“), Ablaufbalken, zwei Knöpfe.

**TP-20 Regeln.**
- Schnellwahl als `ListStepperRow`, Einzelregeln als `ToggleRow`/`ListStepperRow` wie im
  Optionsmenü.
- Mitspieler sehen die Werte gesperrt, im Tooltip steht „Nur der Host ändert Regeln“.
- **Remove:** Erklärtexte „Deine Rolle“, „Abwesenheit“, „Beitritt“; der Inhalt wandert in Tooltips.

**TP-21 Wettbewerb.**
- Einrichten unter Einstellungen.
- Die Uhr hängt am Sitzungs-Cluster oben rechts.
- Läuft die Zeit ab, kommt eine Anfrage-Karte „Zeit ist um – bewerten“. Das ersetzt
  „Bewerten: Multiplayer > Sitzung“ (UX-A5).

**TP-22 Toasts.** Heute laufen Chat, Spieler-Ereignisse, Warnungen und Ablehnungen alle durch
dieselben Toasts unten links: höchstens 5, je 6 s, abgeschnitten (UX-D5). Ziel ist **ein Ort je
Art**:

| Art | Ort |
|---|---|
| Chat und Spieler-Ereignisse („Vici ist beigetreten“) | Chat-Bereich unten links, blendet aus; eine Taste öffnet die Eingabe |
| Verbindung, Sync, Host | Pille oben Mitte (TP-09) |
| Antwort nötig | Anfrage-Karte (TP-19) |
| Ablehnungen | Meldung am Objekt (TP-16) |
| alles | Verlauf (TP-18) |

**TP-23 Reiter „Besuchen“.** Besuchen ist eine Aktion, keine Seite. Ziel:
- „Besuchen“ wird ein Knopf in der Bauleiste neben „Multiplayer“, mit eigenem Icon.
- Ansicht von hinten/Ich-Sicht wechselt man im Besuch mit V. Der doppelte Knopf
  „Ich-Sicht (Spiel)“ entfällt (UX-A3).
- Die Fahrgeschäfte-Liste gehört in den Besuch (TP-27).
- Der Hilfetext „Steuerung“ entfällt (UX-A1).

**TP-24 Besucher-Leiste.** Heute steht oben ein Satz mit 7–8 Tasten (UX-A2), darunter neun
Textknöpfe direkt unter „Heatmaps“. Die Bauleiste bleibt sichtbar und zeigt Bau-Tasten. Das
Spiel macht es im eigenen Laufmodus anders: Es blendet die Bauleiste aus und zeigt nur
Tastenhinweise unten rechts. Ziel: genauso.
- **Tastenhinweise im Spiel-Stil** unten rechts: WASD Laufen, Umschalt Rennen, E (je nach Ort),
  V Ansicht, T Emotes, F Fahrgeschäfte (Taste prüfen), Tab Zurück.
- Die Bauleiste ist im Besuch aus (Prototyp).
- **Remove:** die sechs Emote-Knöpfe (das Rad reicht) und die Leiste oben.

**TP-25 E-Hinweis und Kaufen.**
- E-Hinweis als Prompt unter der Bildmitte („[E] Anstellen · Wildwasserbahn“), mit Sperrgrund.
- Die Kaufliste wird ein kleines Panel mit Zeilen (Artikel, Preis) und Tastensymbolen 1–6.

**TP-26 Emote-Rad.** Funktioniert (Keep), aber im Look des Spiel-Radialmenüs mit Icons.

**TP-27 Fahrgeschäfte-Liste.**
- Panel mit `DataRow`s: Name, Entfernung, Wartezeit, `Stars`, „Mitfahren“.
- Die Bewertung läuft über die Spiel-Sterne mit sichtbarer eigener Wahl statt Knöpfen „1“…„5“
  (UX-C4).

**TP-28 Testfahrt-Einladung.** Kommt in die Anfrage-Karte (TP-19).

**TP-29 Gesperrte Spielknöpfe.** Tempo und Rückgängig sind für Mitspieler gesperrt. Ziel: Ein
Tooltip sagt warum („Nur der Host ändert das Tempo“, UX-E1).

**TP-30 Verlassen und Beenden.**
- „Sitzung beenden“ (Host) fragt nach: „Für alle beenden?“
- „Verlassen“ steht im Fuß des Fensters und im Pausemenü.
- **Add:** der Dialog für Mitspieler, wenn der Host beendet (TP-09).

**TP-31 F8-Dialog.** Er doppelt Hosten, Einladen und Verlassen in einem anderen Stil (UX-B2).
Ziel: nur mit Dev-Flag (wie die QA-Befehle). Spieler sehen ihn nicht.

**TP-32 Persönliche Einstellungen.** Heute gibt es keine: Namensschilder stehen nur im F8-Dialog.
**Add:** im Reiter Einstellungen den Abschnitt „Für dich“ (Namensschilder, Chat-Meldungen,
Chat-Taste).

### Zuordnung der alten Audit-IDs

| UX-Audit | TP | | UX-Audit | TP |
|---|---|---|---|---|
| UX-A1 | TP-23 | | UX-C3 | TP-17 |
| UX-A2 | TP-24 | | UX-C4 | TP-27 |
| UX-A3 | TP-23 | | UX-C5 | TP-10 |
| UX-A4 | Textregeln (§7) | | UX-D1 | Fundament (§9, P0) |
| UX-A5 | TP-21 | | UX-D2 | TP-19 |
| UX-A6 | TP-03 | | UX-D3 | Orte (§6) |
| UX-B1 | Textregeln (§7) | | UX-D4 | TP-13 |
| UX-B2 | TP-31 | | UX-D5 | TP-22 |
| UX-B3 | Begriffe (§3) | | UX-E1 | TP-29, §5 |
| UX-C1 | TP-15 | | UX-E2 | TP-16 |
| UX-C2 | TP-13 | | UX-E3 | TP-09 |

## 5. Zustände

Was der Spieler in jedem Zustand sieht. „Heute“ aus dem Code (`statusOf`, `joinText`, Toasts in
`session.lua`).

| Situation | Zustand | Heute | Ziel |
|---|---|---|---|
| Steam fehlt | Disabled | Satz in der Statuszeile im Fenster | Kachel gesperrt, Tooltip mit Grund; Seite: Grund + „Erneut prüfen“ |
| Keine Sitzung | Initial | Satz „Erstelle eine Lobby …“ | Kachel „Sitzung starten“ + Freundesliste |
| Keine Freunde online | Empty | leere Liste | „Gerade ist keiner deiner Steam-Freunde online.“ |
| Sitzung startet | Loading | – | Knopf zeigt Spinner, gesperrt bis zur Antwort |
| Einladung raus | Waiting | Knopf „Eingeladen“ | blasse Karte im Platz, nach 2 Min. „keine Antwort“ |
| Beitreten | Connecting | Karte „Trete der Lobby bei …“ | Schritt 1/4 mit Balken, „Abbrechen“ |
| Warten auf Host | Waiting | „Warte auf die Zustimmung von …“ | Schritt 2/4, beim Host Anfrage-Karte |
| Park kommt | Loading | „Empfange den Park … n %“ | Schritt 3/4 mit `ProgressBar` |
| Beitritt klappt nicht | Error | `JoinFailed` mit Grund + „Erneut“ | bleibt, Texte prüfen |
| Mitspieler lädt | Loading | Satz in der Statuszeile | Zustands-Icon in der Spielerleiste |
| Alle da | Connected / Success | „Alle verbunden – Park.“ (nur im Fenster) | einmal „Alle sind da“, danach Ruhe |
| Host antwortet nicht | Disconnected | Toast „Keine Verbindung zum Host – warte …“ | Pille oben Mitte mit Zeit; nach 30 s Dialog „Warten / Verlassen“ |
| Verbindung wieder da | Success | Toast | Pille wird kurz grün und geht |
| Nicht synchron | Error | Satz im Fenster + Knopf im Fuß | Pille mit Knopf „Neu synchronisieren“ |
| Host in der Lobby | Waiting | „Geh ins Hauptmenü, um dabei zu bleiben.“ | Dialog mit Knopf „Ins Hauptmenü“ |
| Host hat beendet | Host unavailable | Zeile im Verlauf, sonst nichts | Dialog „Die Sitzung ist beendet“ + Wahl |
| Änderung abgelehnt | Error | Toast | Objekt pulsiert + Meldung mit Grund |
| Aktion gesperrt | Disabled | Knopf grau, ohne Grund | Tooltip mit Grund |
| Brett, Verlauf, Fahrgeschäfte leer | Empty | Satz | kurzer Satz + die passende Aktion („+ Eintrag“) |

## 6. Zielbild: Orte

Feste Orte, gleich in Park und Besuch. Die Spielelemente bleiben, wo sie sind.

| Region | Mod-Inhalt |
|---|---|
| oben rechts | **Sitzungs-Cluster:** Spielerleiste (Avatar, Name, Krone, Zustand), darunter Wettbewerbs-Uhr |
| oben Mitte (ab 5 rem, unter „Heatmaps“) | Verbindungs-Pille, nur bei Problemen |
| oberes Drittel, Mitte | **Anfrage-Karte**, eine zur Zeit |
| links | **Multiplayer-Fenster** (`Panel`), nicht modal |
| unten links | **Chat** mit Spieler-Ereignissen, blendet aus |
| unten rechts | Tastenhinweise im Spiel-Stil (Besuch; „Mittelklick Markieren“ beim Bauen) |
| Bildmitte | E-Prompt, Radialmenüs (Markieren, Emotes), Dialoge |
| Bauleiste | Reiter „Multiplayer“ und „Besuchen“ |

Hauptmenü: Seite „Multiplayer“ im Rahmen des Spiels. Die Sitzungsleiste steht auf jeder Seite
oben rechts unter den Einstellungs-Icons.

```
Hauptmenü ─ Kachel ─► Seite „Multiplayer“
   ohne Sitzung:  [Sitzung starten]  Freunde (mit Sitzung zuerst → Beitreten)
   mit Sitzung:   Plätze 1–8 (Klick auf freien Platz → Freund wählen) · Chat
                  „Öffne einen Park – alle kommen mit.“ → Spielseiten (Fortsetzen, Meine Parks, Neu, Franchise)
   überall:       Sitzungsleiste oben rechts

Park ─ F7 / Bauleiste „Multiplayer“ / Pausemenü ─► Panel links: Spieler · Planen · Verlauf · Einstellungen
Park ─ Bauleiste „Besuchen“ ─► Besuch (Tasten unten rechts, Tab zurück)
Park ─ Mittelklick ─► Markierung + Radialmenü
```

## 7. Textregeln

- **Ein Begriff pro Sache** (§3), Spielbegriffe wie im Spiel.
- **Knöpfe:** Verb oder Ziel, höchstens zwei Wörter („Beitreten“, „Mitfahren“, „Neu synchronisieren“).
- **Tasten nie im Fließtext:** Tastenhinweise oder `inputName` am Knopf.
- **Keine Bedienwege im Text** („Multiplayer > Sitzung“). Stattdessen gibt es einen Knopf, der hinführt.
- **Erklärungen:** ein Satz, als Tooltip. Ein Satz auf der Seite nur, wo das Spiel auch einen hat
  (Seitenbeschreibung).
- **Zustand + Aktion:** „Keine Verbindung zum Host“ [Verlassen], nicht „warte …“.
- **Umlaute überall**, auch in Lua-Texten (UX-B1). Geschlechtsneutral: „wer führt“ statt
  „folgst du ihm“ (UX-A4).
- **Keine Füllwörter, keine Ich-Form der Mod**, keine Ausrufezeichen.

| Vorher | Nachher |
|---|---|
| „Hoste diesen Park und lade Freunde ein – sie bekommen ihn automatisch.“ | Knopf „Sitzung starten“; Tooltip „Freunde treten bei und bauen mit.“ |
| „Lobby offen. Wähle, wo ihr spielt – alle laden den Park dann automatisch.“ | „Öffne einen Park – alle kommen mit.“ |
| „Besucher: Maus umsehen · WASD laufen · Shift rennen · E Eingang oder Shop · T Emotes · V Ich-Sicht · Tab zurück“ | Tastenhinweise: `[WASD] Laufen  [Umschalt] Rennen  [E] Anstellen  [V] Ansicht  [T] Emotes  [Tab] Zurück` |
| „Du schaust einem Gast über die Schulter – "Zurück" beendet das“ | – (Tastenhinweis „[Tab] Zurück“) |
| „Bewerten: Multiplayer > Sitzung“ | Anfrage-Karte „Zeit ist um“ [Bewerten] |
| „Nachricht an alle … (Enter sendet)“ | „Nachricht“ (Senden-Taste als Symbol) |

## 8. Machbarkeit

| Vorhaben | Stand | Risiko |
|---|---|---|
| Spiel-Variablen in unseren Styles (`var(--accent)`, `rgba(var(--accent-triplet), …)`) | Gameface kann es, alle Spiel-Komponenten tun es | gering |
| `rem` statt `px` | Spiel macht es überall | gering, Layout neu prüfen |
| Spiel-Komponenten `Panel`, `DataRow`, `ToggleRow`, `ListStepperRow`, `Stars`, `ProgressBar` importieren | wie heute `Button`/`Dialog`; Fokus- und Eingabe-Kontexte von `Panel` unklar | mittel → Prototyp |
| Host öffnet Park über die Spielmenüs, alle kommen mit | im Code angelegt (`stage = "lobby"`, Toast „Oeffne einen Park - alle laden ihn dann mit.“ in `session.lua`) | gering, im Spiel prüfen |
| Eigene Seite im Hauptmenü-Rahmen (`FrontEndNavData.js` erweitern) | unbekannt | hoch → Prototyp; Rückfall: Vollbild-Ebene im selben Look |
| Bauleiste im Besuch ausblenden | Spiel macht es im eigenen Laufmodus, Weg unbekannt | mittel → Prototyp |
| Tastenhinweise | eigene Leiste im Spiel-Look sicher; echte Spiel-Leiste befüllen unbekannt | gering/mittel |
| Aktionen im Info-Fenster eines Objekts | Eingriff wie bei der Bauleiste denkbar | hoch → Prototyp |
| Chat-Taste | DLL-Tasten vorhanden (FEAT-195); Konflikt mit Spieltasten prüfen | mittel |
| Tooltips an gesperrten Spielknöpfen | JS-Eingriff in die Statusleiste nötig | mittel |
| Dialog „Host hat beendet“ | Verhalten des Parks beim Mitspieler erst klären | mittel |

## 9. Umsetzung in Phasen

Jede Phase endet mit Unit-Tests, aktualisierter Doku (UI_INVENTORY, COMPONENTS, DESIGN_SYSTEM,
NAVIGATION, Registry) und Screenshots aus der Testkopie.

| Phase | Inhalt | fertig, wenn |
|---|---|---|
| **P0 Fundament** | Variablen statt Hex, `rem` statt `px`, Schrift- und Abstandsskala, Übergänge 0.2 s; Bausteine (Panel, Zeile, Anfrage-Karte, Pille, Tastenhinweis); alle Texte nach §3/§7 inkl. Lua | `CoopLayer.js` ohne feste Farben außer Spielerfarben, ohne `px`-Schrift; Screenshots bei 1080p, 1440p, 4K, UI-Skalierung klein/groß, ein Farbenblind-Modus, andere Akzentfarbe |
| **P1 HUD** | Sitzungs-Cluster, Verbindungs-Pille, Anfrage-Karte, Chat unten links, Markieren-Radialmenü, Konflikt-Meldung | keine zwei Mod-Elemente überlappen; jedes hat seinen Ort aus §6 |
| **P2 Fenster im Park** | Panel links, Reiter Spieler/Planen/Verlauf/Einstellungen; Besuchen-Reiter weg | Bauen bleibt bei offenem Fenster möglich |
| **P3 Hauptmenü** | Seite Multiplayer, Sitzungsleiste, Einladen über Platz, Park über Spielseiten | Host startet, lädt ein, öffnet Park ohne Mod-Parkliste |
| **P4 Besuch** | Tastenhinweise, Bauleiste aus, E-Prompt, Kauf-Panel, Fahrgeschäfte-Panel, Emote-Rad im Spiel-Look | keine Leiste oben; nichts Bau-Spezifisches im Bild |
| **P5 Zustände** | alle Zeilen aus §5, Bestätigungen (Beenden, Zurückholen) | jede Zeile in §5 einmal im Spiel ausgelöst und fotografiert |
| **P6 Abnahme** | zwei echte PCs, Maus/Tastatur echt | Eigner spielt eine Sitzung ohne Erklärung |

**Stand (2026-11-20):** P0 Schritte 1 und 2 erledigt: Farben, Einheiten, Schriftskala, Texte,
Lua-Umlaute (`docs/ui-ux/DESIGN_SYSTEM.md`). Offen in P0: Bausteine, HUD-Grund in Akzentfarbe. P1 Schritt 1 erledigt: Sitzungs-Cluster, Anfrage-Karte,
Verbindungs-Pille. P1 Schritt 2 erledigt: Markieren-Radialmenü und Tastenhinweis. Offen in P1: Chat unten links mit
eigener Taste (braucht die DLL), Konflikt-Meldung am Objekt (TP-16).

Prototypen zuerst (vor P2/P3/P4): `Panel` in unserer Ebene, Seite im Hauptmenü-Rahmen,
Bauleiste im Besuch aus. Ergebnis entscheidet, ob Ziel oder Rückfall gebaut wird.

## 10. Offene Fragen an den Eigner

1. Begriff „Sitzung“ überall (Vorschlag) – oder „Lobby“ für die Wartephase im Hauptmenü?
2. Multiplayer-Fenster im Park **links** (kollidiert nicht mit den Info-Fenstern rechts) – ok?
3. Chat dauerhaft unten links, Eingabe per Taste – welche Taste (Vorschlag Enter, prüfen)?
4. „Besuchen“ als eigener Knopf in der Bauleiste neben „Multiplayer“ – ok?
5. Reihenfolge P0 → P6 so, oder ein Bereich zuerst (z. B. Besuch)?
