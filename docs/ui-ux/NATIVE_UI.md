# Wie Planet Coaster 2 seine Oberfläche baut

Grundlage für das UX-Overhaul (`docs/ui-ux/UX_OVERHAUL.md`). Stand: Spielversion 1.12.2, 2026-11-20.

**Quelle:** der entpackte UI-Code der Testkopie (Gameface: HTML/CSS/JS, Preact). Er liegt nur
lokal im Arbeitsordner (`work/coop-anything/local/editor-research/ui-source/UIGameface`) und
kommt **nie** ins Repository. Die Mod läuft in derselben Seite wie die Spiel-Oberfläche und kann
alles hier Genannte zur Laufzeit benutzen (Komponenten importieren, CSS-Variablen lesen,
Icons über `/img/icons/…` anzeigen), ohne Dateien des Spiels mitzuliefern.
Pfade unten sind Pfade **im Spiel** (`/js/…`, `/css/…`).

Das Spiel hat eine interne Komponenten-Übersicht („Bible“, `/js/project/modules/bible/`):
Farben, Schriften, Knöpfe, Eingaben, Stepper, Icons, Animationen. Sie ist unser Maßstab.

## 1. Skalierung

| Regel | Wert | Quelle |
|---|---|---|
| Einheit | alles in `rem`/`em` | alle CSS-Dateien |
| Bezug | 1 rem = 20 px bei 1920 × 1080 | `/js/config/UIScaleConfig.js` (`BASE_FONT_SIZE`, `HOME_RESOLUTION_*`) |
| Auto-Skalierung | Faktor = min(Breite/1920, Höhe/1080) | `/js/common/core/UIScale.js`, Modus 3 |
| Spieler-Einstellung | UI-Skalierung im Optionsmenü multipliziert dazu | `/js/project/utils/UIScaleUtil.js` |
| Kleinste Schrift | 12 px (auch bei kleiner Skalierung) | `MIN_FONT_SIZE` |

**Folge für uns:** Die Mod rechnet in festen Pixeln (1320 × 780 px Fenster, 13–28 px Schrift).
Bei 2560 × 1440 ist alles Spiel-Eigene ein Drittel größer, unseres nicht; bei 4K halb so groß wie
das Spiel. Umrechnung: `rem = px / 20` (Entwurf bei 1080p).

## 2. Farben

Das Spiel definiert alle Farben als CSS-Variablen auf `body` (`/css/project/Shared.css`,
`.default_theme, body`). Komponenten benutzen nur diese Variablen.

| Variable | Standard | Wofür |
|---|---|---|
| `--panel` | `#FFFFFF` | Fensterinhalt |
| `--area` / `--background` / `--neutral0` | `#E8EFF4` | Flächen in Fenstern, Zeilen (`DataRow`) |
| `--neutral1`…`--neutral5` | `#d7e3ec` … `#3f6884` | Abstufungen, Linien |
| `--text` / `--icon` | `#51646E` | Fließtext, Icons |
| `--accent` | `#008ACC` | Titelleisten, aktive Elemente |
| `--accentText` | `#0b3a56` | Text auf Knöpfen |
| `--accentButtonFair` / `--accentButtonDark` | `#56c3fb` / `#00435c` | Knopf-Rahmen normal / Hover |
| `--accentPanelBackground` / `--accentPanelDark` | `#00203d` / `#002d4d` | dunkle Leisten (Statusleiste, Hinweise) |
| `--accentBright` / `--whiteColor` | weiß | Text auf Akzent |
| `--highlight` | `#FFBB00` | Hervorhebung |
| `--positive` | `#00CA65` | gut, verbunden, bestätigt |
| `--warning` | `#EE7722` | Warnung |
| `--negative` | `#FF574B` | Fehler, schlecht |
| `--alert` | `#FF3363` | dringend (Online-Meldung) |
| `--disabled` | `#46575f` | gesperrt |

Jede Variable gibt es zusätzlich als `--name-triplet` (für `rgba(var(--name-triplet), 0.5)`).

- **Akzentfarbe ist einstellbar:** 9 Akzente (`accent_blue`, `accent_lightBlue`, `accent_green`,
  `accent_darkGreen`, `accent_orange`, `accent_red`, `accent_pink`, `accent_purple`,
  `accent_darkBlue`; `/js/config/ThemeConfig.js`). Alle `--accent*` wechseln mit.
- **Farbenblind-Modi:** `protanopia`, `deuteranopia`, `tritanopia` setzen alle Variablen neu.
- **Folge für uns:** Die Mod benutzt 25 feste Hex-Farben und 35 `rgba`-Werte. Sie folgt weder
  der Akzentfarbe noch den Farbenblind-Modi des Spielers.

## 3. Schrift

Eine Familie: `StandardFont` (+ 7 Ausweichschriften für andere Sprachen). Größen als `em`
(1 em = 20 px bei 1080p). Häufigkeit im ganzen Spiel-CSS:

| Größe | px @1080p | Häufigkeit | Rolle (Bible) |
|---|---|---|---|
| 1.6 em fett | 32 | 65 | Seitentitel (`HeaderBold(32px)`) |
| 1.2 em | 24 | 111 | Überschrift (`Header(24px)`) |
| 1.1 em | 22 | 89 | Unterüberschrift |
| 1 em | 20 | 463 | Text, Knöpfe, Fenstertitel (`Paragraph(20px)`) |
| 0.9 em | 18 | 14 | Nebentext (selten) |
| 0.8 em | 16 | 3 | sehr selten |

Zeilenhöhe zu 1 em: 1.55 rem. Gewicht nur normal und fett. **Folge für uns:** Die Mod nutzt
zehn Größen (13–28 px); 15 px ist die häufigste – kleiner als alles, was das Spiel für Text benutzt.

## 4. Abstände, Formen, Tiefe

| Merkmal | Spiel | Häufigkeit |
|---|---|---|
| Abstände | Raster 0.25 rem: **0.5 rem** (10 px), 0.25, 1, 0.75, 1.5, 2 rem | 1205 / 755 / 454 / 197 / 65 / 80 |
| Rundung | **0.5 rem** Standard, 1 rem Fenster, 0.75 rem, Knöpfe als Pille (1.45 rem) | 218 / 104 / 69 |
| Rahmen | 0.1 rem, unten 0.2 rem (Knöpfe) | – |
| Schatten Fenster | `0 0 1.8rem rgba(0,0,0,0.4)` (`Panel_panel`) | – |
| Schatten Tooltip | `0 0 0.5rem rgba(0,0,0,0.3)` | – |
| Fensterbreite | **23.5 rem** für Info- und Werkzeug-Fenster | `Panel_root.infoPanel` |
| Zeile | min. 2 rem hoch, Innenabstand 0.25 / 0.5 rem, Grund `--area` | `DataRow_root` |

## 5. Bewegung

`FadeIn`/`FadeOut`, `ModalBackgroundShow` (Abdunkeln auf 50 %), `bounceIn` für Belohnungen,
`highlightPulse` (1 s) für Hinweise. Übergänge meist **0.2 s**, sonst 0.1–0.3 s.
Die Mod hat bisher keine Übergänge: Elemente erscheinen und verschwinden hart.

## 6. Bausteine

| Spiel-Komponente | Pfad | Was | Für die Mod |
|---|---|---|---|
| `Panel` | `/js/project/components/panel/Panel.js` | Fenster: Titelleiste in `--accent` mit Icon + Titel + Schließen, Symbol-Reiter (`TabNavigator`), Inhalt, Fußleiste; in 76 Spiel-Fenstern | Multiplayer-Fenster im Park |
| `Button` | `/js/project/components/Button.js` | Pille; Varianten `alt`, `positive`, `negative`, `warning`, `small`, `round`, `noChrome`; `icon`, `tooltip`, `inputName` (zeigt die Taste) | alle Knöpfe (benutzen wir, aber ohne Tooltip/Taste/Icon) |
| `CloseButton` | `/js/project/components/CloseButton.js` | Schließen-Kreuz | Fenster, Leisten |
| `DataRow`, `ExpandableDataRow` | `/js/project/components/` | Zeile mit Icon, Text, Werten, Icon-Knöpfen | Spieler, Meldungen, Brett, Fahrgeschäfte |
| `ToggleRow`, `ListStepperRow`, `SliderRow`, `CheckBoxRow`, `RadioButtonRow` | `/js/project/components/` | Einstellungszeilen wie im Optionsmenü | Regeln, Wettbewerb |
| `ScrollPane` | `/js/common/components/ScrollPane.js` | Scrollbereich mit Spiel-Scrollleiste | Listen, Chat |
| `Dialog`, `Prompt`, `PopupPanel` | `/js/project/components/` | Rückfragen, Bestätigungen | Beitritt, Zurückholen, Beenden |
| `Tooltip` | `/js/project/components/Tooltip.js` | weiß, max. 10 rem breit, über `Button tooltip` | Erklärungen statt Fließtext, Sperrgründe |
| `Notification` | `/js/project/modules/notifications/Notification.js` | Meldungszeile mit Icon-Knöpfen „Hinbringen“ (`takemeto.svg`), „Verwerfen“ | Park-Meldungen, Brett |
| `CommsNotification` | `/js/project/modules/commsNotification/` | Meldungskarte oben Mitte (ab 5 rem) | Spieler-Ereignisse |
| `OnlineNotification` | `/js/project/modules/onlineNotifications/` | Pille oben Mitte in `--alert` | Verbindung verloren |
| `InputHintsModule`, `HUDButtonPromptBar` | `/js/project/modules/inputHints/`, `/js/project/modules/HUD/HUD.js` | Tastenhinweise unten rechts (`[Alt] Springen  [Strg] Ducken …`) | Besucher-Steuerung |
| `CenterPromptModule` | `/js/project/modules/centerPrompt/` | Hinweis in der Bildmitte, 27 rem | „E Anstellen“ |
| `RadialMenuModule` | `/js/project/modules/radialMenu/` | Radialmenü (Alt halten) | Emote-Rad, Ping-Menü |
| `LoadingSpinner`, `ProgressBar`, `ProgressSteps` | `/js/project/components/` | Laden, Fortschritt | Beitritt |
| `Stars`, `StatusTag`, `PlayerTag` | `/js/project/components/` | Sterne, Status-Etikett, Spieler-Etikett | Bewertung, Rolle, Spieler |
| Hauptmenü-Seiten | `/js/project/modules/frontEnd/` (`FrontEndNavData.js`) | Vollbild-Seiten mit Brotkrumen, Kopf- und Fußleiste, Kacheln (`FrontEndTileButton`), Seitenpanel (`FrontEndInfoSidePanel`), Freundesliste (`FrontEndFriendsListPopUp`, `FriendsHub`) | Multiplayer im Hauptmenü |

Die Mod benutzt heute vier davon: `Button`, `Dialog`, `InputField`, `Icon`.

## 7. Icons

1234 Icons unter `/img/icons/`. Passend für Multiplayer (Auswahl): `collaborate.svg`,
`crown.svg` (Host), `takemeto.svg` (Hinbringen), `eye.svg` (zuschauen/folgen),
`followCreator.svg`/`unfollowCreator.svg`, `plusCircle.svg` (einladen), `exit.svg` (verlassen),
`connectionStateConnected.svg`/`connectionStateDisconnected.svg`, `franchisePlayerKick.svg`,
`Icon_BlockUser.svg`, `thumbsUp.svg`/`thumbsDown.svg` (abstimmen), `star.svg`/`starOutline.svg`,
`history.svg`, `delete.svg`, `pinActive.svg`, `marker.svg`, `flag.svg`, `trophyGeneral.svg`,
`clock.svg`, `lock.svg`, `undo.svg`, `shoppingBag.svg`, `rides.svg`, `RideCamGuestCamera.svg`,
`spinner.svg`, `checkCircle.svg`, `warning.svg`, `information.svg`.

## 8. Wo was im Bild sitzt

**Im Park** (`/js/project/modules/HUD/HUD.js`, Screenshots der Testkopie):

| Region | Spiel |
|---|---|
| oben links | Icons Ziele/Meldungen |
| oben Mitte | „Heatmaps“-Pille; darunter Comms-Meldungen (ab 5 rem) und Online-Meldungen |
| oben rechts | Speicher-Anzeige |
| rechts | Info- und Werkzeug-Fenster (23.5 rem), am rechten Rand gestapelt |
| Mitte | Hinweise (`CenterPrompt`), Radialmenü, Dialoge mit abgedunkeltem Hintergrund |
| unten | Bauleiste mit Reitern; darunter dunkle Statusleiste (Park, Geld, Gäste, Bewertung, Wetter, Datum, Tempo); Tastenhinweise rechts über der Statusleiste |

Im eigenen Laufmodus (Ich-Sicht) blendet das Spiel die Bauleiste aus und zeigt nur die
Tastenhinweise (Springen, Rennen, Ducken, Lampe, Interagieren, Zurück).

**Hauptmenü** (`FrontEndNavData.js`): jede Funktion ist eine **Seite** im selben Rahmen –
Brotkrumen oben, Fußleiste mit Tastenhinweisen („Esc Zurück“), Inhalt links mit 6.05 rem
Rand, Titel 1.6 em fett weiß, ein Satz Beschreibung (max. 38 rem), darunter Kacheln oder Liste,
rechts ein Info-Seitenpanel. Schwebende Fenster gibt es dort nur als kleine Popups.

## 9. Muster, an die sich das Spiel hält

1. **Tasten stehen am Knopf** (`inputName`) oder in der Hinweisleiste – nicht im Fließtext.
2. **Erklärungen sind Tooltips**, keine Absätze im Fenster.
3. **Ein Fenstertyp, eine Breite:** Info-Fenster sind alle 23.5 rem breit und sitzen rechts.
4. **Hinbringen ist ein Icon** (`takemeto.svg`) an der Zeile, kein Textknopf.
5. **Statusfarben nur für Status** (`--positive`, `--warning`, `--negative`), Akzent für Bedienung.
6. **Zwei Gewichte, wenige Größen**, Titel fett. Großbuchstaben nur für kleine Etiketten
   (`StatusTag`, Tastenhinweise, Kopfleiste im Hauptmenü), nie für Abschnittstitel in Fenstern.
7. **Gesperrte Knöpfe bleiben sichtbar** und sagen im Tooltip, warum (z. B. Speichern:
   `disabled` + `tooltip`).
