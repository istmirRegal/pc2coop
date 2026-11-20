# ADR-020: Native Oberfläche – Bausteine, Variablen und Einheiten des Spiels

- **Status:** Vorgeschlagen
- **Datum:** 2026-11-20
- **Betrifft:** FEAT-110, FEAT-090, FEAT-116, FEAT-160 (alle sichtbaren Teile der Mod)

## Kontext

Der Eigner will ein UX-Overhaul: Die Mod soll wirken, als hätten die Entwickler des Spiels sie
gebaut. Heute zeichnet die Mod das Spiel nach: 25 feste Hex-Farben, zehn Schriftgrößen in `px`
und ein eigenes Fenster. Von den Spiel-Komponenten nutzt sie nur vier. Sie folgt deshalb weder
Auflösung, UI-Skalierung, Akzentfarbe noch Farbenblind-Modus des Spielers. Die Analyse des
Spiel-UI-Codes (`docs/ui-ux/NATIVE_UI.md`) zeigt: Das Spiel hat ein vollständiges System aus
CSS-Variablen, `rem`-Skalierung und Komponenten (`Panel`, `DataRow`, Tooltip, Tastenhinweise).
Die Mod läuft in derselben Seite und kann all das zur Laufzeit benutzen.

## Entscheidung

1. Farben nur über die CSS-Variablen des Spiels; feste Farben nur für Spielerfarben.
2. Größen nur in `rem`/`em` (Entwurf bei 1080p, `rem = px / 20`).
3. Wo das Spiel einen Baustein hat, benutzt die Mod ihn (Fenster, Zeilen, Einstellungen,
   Dialoge, Tooltips, Fortschritt, Sterne, Icons). Eigene Bausteine nur, wo das Spiel keinen hat
   (Anfrage-Karte, Spieler-Pille), und dann im Spiel-Look.
4. Jede Art von Information hat einen festen Ort (`docs/ui-ux/UX_OVERHAUL.md` §6).
5. Bevor Oberfläche gebaut wird, wird geprüft, ob das Spiel die Aufgabe schon löst. Beispiel:
   Der Host wählt den Park über die Spielmenüs, statt dass die Mod eine eigene Parkliste hat.
6. Rangfolge der Maßstäbe: das Spiel → Nielsens Heuristiken → Norman → Apple HIG →
   Spiele-Barrierefreiheit (Game Accessibility Guidelines, Xbox Accessibility Guidelines).

## Alternativen

- **Eigenes modernes Designsystem:** sauber, aber sichtbar fremd im Spiel. Verworfen, das ist
  das Gegenteil des Ziels.
- **Spiel-Look mit eigenen Werten nachbauen (wie heute):** bricht bei jeder Auflösung,
  Skalierung, Akzentfarbe und jedem Spiel-Update, das Farben ändert.
- **Spiel-Dateien (CSS, Bilder) kopieren und mitliefern:** verboten (keine Spiel-Assets im
  Repository) und unnötig, weil alles zur Laufzeit da ist.

## Begründung

Nur mit den Bausteinen und Variablen des Spiels sieht die Mod bei jeder Einstellung des
Spielers so aus wie das Spiel. Konsistenz entsteht dann automatisch und muss nicht für jeden
Screen neu nachgemessen werden.

## Konsequenzen

- `CoopLayer.js` wird in Phasen umgebaut (P0–P6 in `UX_OVERHAUL.md`); alle Screens werden neu
  im Spiel fotografiert und abgenommen.
- Wir hängen stärker an Komponenten des Spiels: Nach Spiel-Updates gehören die genutzten
  Komponenten auf die Prüfliste (`docs/development/TESTING.md`, „Nach einem Spiel-Update“).
- Komponenten mit eigener Eingabe-/Fokus-Logik (`Panel`) brauchen vorher einen Prototyp.
- Spielerfarben bleiben fest. Sie müssen bei allen Spielern gleich sein und tragen immer auch
  Name oder Icon.
