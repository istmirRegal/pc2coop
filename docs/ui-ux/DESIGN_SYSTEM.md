# Design-System (Ist-Zustand 1.13.0)

Beschreibt, wie die Oberfläche **heute** aussieht. Ein späteres UX-Overhaul ändert diese
Datei zuerst (Ziel-Zustand), dann den Code. Leitlinie: soll sich wie ein Teil von
Planet Coaster 2 anfühlen – Komponenten des Spiels benutzen, wo es geht (`Button`, `Dialog`,
`InputField`, `Icon`, `BrowserTab`, `TileButton`).

## Technische Grenzen (Gameface)

- Nur Inline-Styles in `CoopLayer.js`, keine eigene CSS-Datei.
- Feste Pixelgrößen: Gameface schrumpft Flex-Boxen nicht zuverlässig (deshalb `box(height)`,
  feste Spaltenbreiten).
- Texte für Spiel-Komponenten über `literal()` (`[STRING_LITERAL:Value=|…|]`); `:` und `|`
  werden ersetzt (sonst zeigt der Dialog nichts). Spieltexte (Lokalisierungs-Schlüssel) über
  `shown()` → `translate()`.
- Preact des Spiels überspringt `setState` mit gleichen Werten → `revision` erzwingt Neuzeichnen.
- Ebene `CoopLayer`: `zIndex 10000`, `pointerEvents: none`; nur Fenster/Banner/Leisten fangen Klicks.

## Farben

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

## Schrift

`FONT` = Schriften des Spiels (`StandardFont` + Fallbacks). Größen in px:
28 (Fenstertitel), 22/20 (Karten-Titel), 18–19 (Text im Fenster, Abschnittstitel in
Großbuchstaben mit 1 px Sperrung), 17 (Listen, Toasts), 15–16 (Nebentext, Hilfen), 13–14 (Aktivität).

## Formen und Abstände

- Fenster: 1320 × 780, Radius 14, Schatten `0 12px 40px rgba(0,0,0,0.45)`, Kopf 64 px, Fuß 80 px,
  Spalten 360 / 540 / 420 mit 18 px Innenabstand.
- Pillen (Spielerleiste, Besucher-Leiste, Wettbewerbs-Uhr): Radius 16–20.
- Banner und Karten: Radius 10–12, Innenabstand 12–18.
- Knöpfe: Spiel-`Button`, rechtsbündig in Reihen (`buttons()`), 6 px Abstand.

## Sprache

- Deutsch, „du“, kurze Sätze, ohne Fachwörter (ADR-018). Knöpfe = Verb oder Ziel
  („Mitfahren“, „Zurück zum Bauen“).
- Texte aus Lua (Toasts, Feed) sind teils ohne Umlaute geschrieben („geloescht“) – siehe
  UX-Audit B1.
- Spielbegriffe wie im Spiel (Fahrgeschäft, Achterbahn, Szenerie, Baugebiet).

## Platzierung im Bild

| Bereich | Belegt durch |
|---|---|
| oben Mitte 18 px | Wettbewerbs-Uhr |
| oben Mitte 52 px | Besucher-Leiste (+ Liste 1000 px breit) |
| oben Mitte 140 px | Abstimmungs- und Einladungs-Banner |
| oben rechts 84 px | Spielerleiste |
| unten links 120 px | Toasts |
| Mitte | Multiplayer-Fenster, Emote-Rad, Dialoge |
| an der Maus | Kontextmenü |
