# ADR-018: Deutsche Texte, STRING_LITERAL für Spiel-Komponenten

- **Status:** Akzeptiert
- **Datum:** 2026-11-14
- **Betrifft:** FEAT-110, FEAT-118

## Kontext

Die Spieler sind deutschsprachig. Komponenten des Spiels (`Button`, `Dialog`) erwarten
Lokalisierungs-Schlüssel.

## Entscheidung

Alle Mod-Texte sind Deutsch („du“, kurz). Eigene Texte gehen als
`[STRING_LITERAL:Value=|…|]` (`literal()` in JS, `literal` in `menu.lua`) an die Spiel-Komponenten;
`:` und `|` werden ersetzt. Spieltexte (Schlüssel) zeigt `shown()`/`translate()`.

## Alternativen

- Eigene Lokalisierungsdateien (müssten ins Spiel-Paket).
- Englisch.

## Begründung

Keine Eingriffe in Spiel-Lokalisierung; ein Doppelpunkt im Text ließ einen Dialog leer (1.5.0).

## Konsequenzen

- Keine Übersetzung in andere Sprachen ohne neues Konzept. Seit 1.14.0: Englisch nach der
  Sprache des Spiels, die Texte bleiben im Code Deutsch (ADR-022).
- Siehe UX-Audit B1 (Umlaute in Lua-Texten).

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._
