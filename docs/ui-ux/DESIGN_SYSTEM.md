# Design-System

Teil A beschreibt das **Ziel** des UX-Overhauls (`docs/ui-ux/UX_OVERHAUL.md`, ADR-020). Es ist
noch nicht umgesetzt und wartet auf die Freigabe des Eigners. Teil B beschreibt, wie die
Oberfläche **heute** (1.13.0) aussieht. Erst ändert sich diese Datei, dann der Code; danach
wandert Teil A nach Teil B.

Leitlinie: Die Mod soll zu Planet Coaster 2 gehören. Sie benutzt Variablen, Bausteine und
Icons des Spiels (`docs/ui-ux/NATIVE_UI.md`) und erfindet nur, was das Spiel nicht hat.

## A. Ziel (UX-Overhaul)

**Umgesetzt (P0, Schritt 1, 2026-11-20, im Spiel fotografiert):**
- A1: alle Größen in `rem`, Mauskoordinaten bleiben in px.
- A2: alle Farben über `C(name)`.
- Abschnittstitel fett statt in Großbuchstaben.

**Umgesetzt (P0, Schritt 2, 2026-11-20, im Spiel fotografiert):**
- A3: Schriftskala 0.9 / 1 / 1.1 / 1.2 rem, nichts unter 0.9 rem.
- Texte im JS nach UX_OVERHAUL §3/§7: „Sitzung“ statt Lobby/hosten, „Hinbringen“,
  „Ich-Sicht“, keine Tasten mehr in Eingabefeldern.
- Umlaute in den Lua-Meldungen (Toasts, Verlauf, Beitrittsfehler).

**Umgesetzt (P0, Schritt 3, 2026-11-20, im Spiel fotografiert bei 1080p, Standard-Akzent):**
- HUD-Grund über `--accentPanelBackground-triplet`, Linien und Rahmen über `--accent-triplet`
  (`HUD_BG`, `ACCENT_A`). Keine feste Akzentfarbe mehr in `CoopLayer.js`.
- Bausteine A6 im Code: siehe Tabelle unten.
- Lua-Meldungen sagen „Sitzung“ statt „Lobby“.
- F8-Dialog nur mit Dev-Flag (TP-31); „Für dich“ im Reiter Sitzung (Anfang TP-32).

**Abnahme-Bilder (P0, 2026-11-20, Testkopie 1080p, umgestellt mit `Ui._QaLook`, nichts gespeichert):**
- Akzent Standard, Orange, Lila; Protanopie, Tritanopie; UI-Skalierung 0.7 und 1.0: Fenster und
  HUD folgen. Dabei behoben:
  - die Mod las die Farben nur alle 3 s und zeichnete danach nicht neu (alte Farben bis zur
    nächsten Zustandsänderung)
  - Streifen der Meldungskarten mit festen Lua-Farben (`noticeColor`)
  - Krone im Fenster unsichtbar (weißes Icon auf weißer Karte)
  - „Hinbringen“/„Folgen“ liefen aus der Spieler-Karte
- Letzte `px`-Linien in `rem` umgestellt; übrig sind nur 0-Werte und Mauskoordinaten.
- 1440p und 4K nicht fotografierbar (Bildschirm 1080p); durch `rem` proportional wie das Spiel.
- Bei UI-Skalierung 1.0 bricht im Spiel „Ebene Fahrgeschäfte“ in der Bauleiste um, auch ohne
  unseren Reiter (geprüft mit ausgeblendetem Reiter): Verhalten des Spiels.

Der Ist-Teil B beschreibt bei Farben und Maßen den Stand **vor** diesem Schritt.

**Technik:** Gameface wendet `var(--…)` im Inline-Kurzattribut `background` nicht an (Fenster
ohne Hintergrund). Deshalb liest die Mod die Werte wie die Bible des Spiels per
`getComputedStyle` aus (`C(name)`, `refreshPalette()`) und setzt feste Werte. Außerdem setzt sie
`backgroundColor` statt `background` und Rahmenfarben einzeln (`borderColor`).

### A1. Einheiten

- Alle Größen in `rem` (Abstände, Breiten) und `em` (Schrift). Entwurf bei 1080p: `rem = px / 20`.
- Keine `px`, außer 1–2 px für Haarlinien und Canvas-Pixel (Avatare).
- Damit folgt die Mod Auflösung und UI-Skalierung des Spielers.

### A2. Farben

Nur Variablen des Spiels. Feste Farben gibt es nur für die Spielerfarben (FEAT-043), denn die
müssen bei allen Spielern gleich sein.

| Rolle | Variable | ersetzt (heute) |
|---|---|---|
| Fenstergrund | `var(--panel)` | `#f4f8fa` |
| Fläche, Zeile | `var(--area)` | `#e3edf2`, `#eef3f6` |
| Titelleiste | `var(--accent)` (über `Panel`) | `#0e2130` |
| Text | `var(--text)` | `INK #1b3a4e` |
| Werte, betonter Text | `var(--accentText)` | `INK` |
| Nebentext | `var(--accentButtonDesaturatedDark)` (wie `DataRow_subLabel`) | `MUTED #4b6a7c` |
| Bedienelemente, aktiver Reiter | `var(--accent)` | `BLUE #0079ad` |
| HUD-Grund (Pillen, Chat, Karte) | `rgba(var(--accentPanelBackground-triplet), 0.85)`, Text `var(--whiteColor)` | `rgba(14,33,48,0.72–0.94)` |
| Tastenhinweis-Grund | `rgba(0,0,0,0.3)` wie `InputHintsItem` | – |
| Hervorhebung (du folgst, Auswahl) | `var(--highlight)` | `#fcc419`, `#ffd43b` |
| Zustand ok | `var(--positive)` | `#3fbf5f` |
| Zustand Warnung | `var(--warning)` | `#ff922b` |
| Zustand Fehler | `var(--negative)` | – |
| Zustand dringend | `var(--alert)` | – |
| Zustand beschäftigt | `var(--accentLight)` | `#00c6ff` |
| gesperrt | `var(--disabled)` | `#9fb3bf` |

Farbe ist nie das einzige Signal: Zustände haben immer auch Icon oder Text
(Farbenblind-Modi des Spiels, Game Accessibility Guidelines).

### A3. Schrift

Familie `StandardFont` mit den Ausweichschriften des Spiels. Gewichte normal und fett. Zeilenhöhe
1.55 rem bei 1 em.

| Stufe | Größe | Wofür |
|---|---|---|
| Titel | 1.6 em fett | Seitentitel im Hauptmenü |
| Überschrift | 1.2 em | Abschnitt in großen Fenstern |
| Fenstertitel, Text, Knöpfe | 1 em | fast alles |
| Nebentext | 0.9 em | Tätigkeit, Zeitstempel |

Keine Großbuchstaben für Abschnittstitel (heute „SPIELER“, „CHAT“). Großbuchstaben gibt es nur
in kleinen Etiketten wie `StatusTag`.

### A4. Abstände und Formen

| Merkmal | Wert |
|---|---|
| Raster | 0.25 rem; üblich 0.5 rem (Standard), 0.25, 0.75, 1, 1.5, 2 rem |
| Innenabstand Fenster/Zeile | 0.5 rem / 0.25 × 0.5 rem |
| Rundung | 0.5 rem (Zeilen, Karten, Tooltips), 1 rem (Fenster), Pille für Knöpfe und HUD-Pillen |
| Schatten Fenster | `0 0 1.8rem rgba(0,0,0,0.4)` |
| Schatten HUD/Tooltip | `0 0 0.5rem rgba(0,0,0,0.3)` |
| Fensterbreite | 23.5 rem (eine Spalte), 47 rem (zwei Spalten) |
| Zeilenhöhe min. | 2 rem |
| Abstand zum Bildrand | 1 rem |

### A5. Bewegung

- Erscheinen und Verschwinden: Einblenden 0.2 s, linear.
- HUD-Elemente gleiten zusätzlich 0.5 rem.
- Hinweis auf ein Objekt oder eine Zeile: Pulsieren wie `highlightPulse`, 1 s, zweimal.
- Keine Bewegung bei Zahlen und Texten, die sich oft ändern.

### A6. Bausteine

| Baustein | Quelle | Einsatz |
|---|---|---|
| Fenster | Spiel-`Panel` (Titelleiste, Icon-Reiter, Schließen) | Multiplayer-Fenster, Fahrgeschäfte, Kaufen |
| Zeile | Spiel-`DataRow` + Icon-Knöpfe | Spieler, Brett, Meldungen, Fahrgeschäfte |
| Einstellung | `ToggleRow`, `ListStepperRow`, `SliderRow` | Regeln, Wettbewerb, „Für dich“ |
| Knopf | Spiel-`Button` mit `tooltip`, `inputName`, `icon`; Varianten `positive`/`negative` für Ja/Nein | überall |
| Rückfrage | Spiel-`Dialog` | Beitritt, Beenden, Zurückholen, Host weg |
| Tooltip | `Button tooltip` / `Tooltip` | Erklärungen, Sperrgründe |
| Fortschritt | `ProgressBar`, `LoadingSpinner` | Beitritt, Laden |
| Sterne | `Stars` | Bewertung |
| **Anfrage-Karte** (eigen) | Spiel-Look: `--panel`, Rundung 0.5 rem, Schatten, Knöpfe `positive`/`negative`, Ablaufbalken | Beitritt, Abstimmung, Testfahrt, Übernahme, Bewerten |
| **Pille** (eigen) | wie `OnlineNotification` | Verbindung, Sync |
| **Tastenhinweis** (eigen, bis die Spiel-Leiste nutzbar ist) | wie `InputHintsItem`: Tastensymbol + Wort | Besuch, Markieren |
| **Spieler-Pille** (eigen) | HUD-Grund, Avatar, Name, Krone, Zustands-Icon | Sitzungs-Cluster |

Im Code (`CoopLayer.js`, P0 Schritt 3): Zeile `row`, Anfrage-Karte `RequestCard`, Pille `hudPill`,
HUD-Karte `hudCard`, Tastenhinweis `keyCap`/`keyHint`/`hintBar`. Fenster im Park (P2):
`renderParkPanel` mit den Klassen `Panel_*`/`TabBar_*`, Spiel-`Tab`, `CloseButton`, Zeilen mit
`iconButton` (rund, Tooltip) wie `LinkedObjectRow` des Spiels.

### A7. Icons

Nur Spiel-Icons (`/img/icons/…`), immer mit Tooltip oder Text daneben. Ein Icon kommt nur dorthin,
wo es eine feste Bedeutung hat:

| Bedeutung | Icon |
|---|---|
| Multiplayer | `collaborate.svg` |
| Host | `crown.svg` |
| Hinbringen | `takemeto.svg` |
| Folgen | `eye.svg` |
| Einladen | `plusCircle.svg` |
| Verlassen | `exit.svg` |
| Verbunden / getrennt | `connectionStateConnected.svg` / `connectionStateDisconnected.svg` |
| Dafür / dagegen | `thumbsUp.svg` / `thumbsDown.svg` |
| Bewertung | `star.svg` / `starOutline.svg` |
| Verlauf | `history.svg` |
| Löschen | `delete.svg` |
| Wettbewerb | `trophyGeneral.svg` |
| Zeit | `clock.svg` |
| Gesperrt | `lock.svg` |
| Besuchen | `RideCamGuestCamera.svg` (im Spiel prüfen) |

### A8. Orte

Siehe `docs/ui-ux/UX_OVERHAUL.md` §6. Jede Art von Information hat genau einen Ort. Der Ort
bleibt in Park, Besuch und Hauptmenü derselbe.

## B. Ist-Zustand 1.13.0

### Technische Grenzen (Gameface)

- Nur Inline-Styles in `CoopLayer.js`, keine eigene CSS-Datei.
- Feste Pixelgrößen: Gameface schrumpft Flex-Boxen nicht zuverlässig (deshalb `box(height)`,
  feste Spaltenbreiten).
- Texte für Spiel-Komponenten über `literal()` (`[STRING_LITERAL:Value=|…|]`); `:` und `|`
  werden ersetzt (sonst zeigt der Dialog nichts). Spieltexte (Lokalisierungs-Schlüssel) über
  `shown()` → `translate()`.
- Preact des Spiels überspringt `setState` mit gleichen Werten → `revision` erzwingt Neuzeichnen.
- Ebene `CoopLayer`: `zIndex 10000`, `pointerEvents: none`; nur Fenster/Banner/Leisten fangen Klicks.

### Farben

| Name | Wert | Verwendung |
|---|---|---|
| `BLUE` | `#0079ad` | Abschnittstitel, aktiver Reiter, Rad-Auswahl, Links |
| `INK` | `#1b3a4e` | Text auf hellem Grund |
| `MUTED` | `#4b6a7c` | Nebentext, leere Zustände |
| Fenster-Grund | `#f4f8fa` | Multiplayer-Fenster, Fahrgeschäfte-Liste |
| Fenster-Kopf | `#0e2130` | Kopfleisten |
| Fuß/Reiterleiste | `#e3edf2` | Fußleiste, Reiterleiste, Auswahl |
| HUD-Grund | `rgba(14, 33, 48, 0.72–0.94)` | Spielerleiste, Toasts, Banner, Kontextmenü, Besucher-Leiste |
| Akzent hell | `#9fd8f0` | Text auf dunklem Grund (Aktivität, Hilfezeile) |
| Gelb | `#fcc419` / `#ffd43b` | „du folgst“, E-Hinweis, Kaufliste |
| Linien | `rgba(0, 120, 170, 0.15–0.2)` | Trennlinien |

Zustandsfarben (`TONE`, Status-Punkt im Fuß): ok `#3fbf5f`, busy `#00c6ff`, wait `#fcc419`,
warn `#ff922b`, idle `#9fb3bf`. Toast-Rand: Farbe aus Lua (`ff922b` Warnung, Spielerfarbe
bei Spieler-Ereignissen, sonst `00c6ff`). Spielerfarben: FEAT-043 (`session.lua`).

### Schrift

`FONT` = Schriften des Spiels (`StandardFont` + Fallbacks). Größen in px:
28 (Fenstertitel), 22/20 (Karten-Titel), 18–19 (Text im Fenster, Abschnittstitel in
Großbuchstaben mit 1 px Sperrung), 17 (Listen, Toasts), 15–16 (Nebentext, Hilfen), 13–14 (Aktivität).

### Formen und Abstände

- Fenster: 1320 × 780, Radius 14, Schatten `0 12px 40px rgba(0,0,0,0.45)`, Kopf 64 px, Fuß 80 px,
  Spalten 360 / 540 / 420 mit 18 px Innenabstand.
- Pillen (Spielerleiste, Besucher-Leiste, Wettbewerbs-Uhr): Radius 16–20.
- Banner und Karten: Radius 10–12, Innenabstand 12–18.
- Knöpfe: Spiel-`Button`, rechtsbündig in Reihen (`buttons()`), 6 px Abstand.

### Sprache

- Deutsch, „du“, kurze Sätze, ohne Fachwörter (ADR-018). Knöpfe = Verb oder Ziel
  („Mitfahren“, „Zurück zum Bauen“).
- Texte aus Lua (Toasts, Feed) sind teils ohne Umlaute geschrieben („geloescht“) – siehe
  UX-Audit B1.
- Spielbegriffe wie im Spiel (Fahrgeschäft, Achterbahn, Szenerie, Baugebiet).

### Platzierung im Bild

| Bereich | Belegt durch |
|---|---|
| oben Mitte 18 px | Wettbewerbs-Uhr |
| oben Mitte 52 px | Besucher-Leiste (+ Liste 1000 px breit) |
| oben Mitte 140 px | Abstimmungs- und Einladungs-Banner |
| oben rechts 84 px | Spielerleiste |
| unten links 120 px | Toasts |
| Mitte | Multiplayer-Fenster, Emote-Rad, Dialoge |
| an der Maus | Kontextmenü |
