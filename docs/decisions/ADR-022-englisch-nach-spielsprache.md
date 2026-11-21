# ADR-022: Englisch nach der Sprache des Spiels

- **Status:** Akzeptiert
- **Datum:** 2026-11-21
- **Betrifft:** FEAT-121, FEAT-118, ADR-018

## Kontext

Seit November 2026 testen auch fremde, englischsprachige Spieler (Discord). Ein Tester hat um eine
englische Übersetzung gebeten, der Eigner hat sie freigegeben. ADR-018 legte alle Texte auf
Deutsch fest; Komponenten des Spiels bekommen eigene Texte als `STRING_LITERAL`.

## Entscheidung

- Die Mod-Oberfläche folgt der Sprache des Spiels: **Deutsch**, wenn das Spiel Deutsch läuft
  (`System.getLanguage()` des Spiels), sonst **Englisch**. Weitere Sprachen gibt es nicht.
- Die Texte bleiben im Code Deutsch (CoopLayer.js und Lua). `Texts.js` übersetzt sie beim
  Anzeigen: `EXACT` für ganze Texte, `PATTERNS` für Texte mit Namen oder Zahlen, Texte mit „ · “
  Teil für Teil. `tr()` läuft in `h()` auf jedem Text-Kind und in `literal()`.
- Was Spieler schreiben (Chat, Brett), geht durch `keep()` und wird nie übersetzt.
- Texte, die Lua selbst an Objekte zeichnet („Erstellt von …“, „… baut hier gerade“), übersetzt
  `lang.lua`; die Oberfläche meldet die Sprache dazu mit der UI-Aktion `lang`.
- Netzwerk und Log bleiben unverändert: Lua schickt weiter deutsche Texte, jeder Empfänger zeigt
  sie in seiner Sprache (gemischte Sitzungen gehen).

## Alternativen

- Schlüssel statt Texte in Lua und JS (`t("session.start")`): sauberer, aber jeder Text in
  zwei Sprachen an zwei Orten zu pflegen und ein Umbau aller Meldungen samt Netzformat.
- Lokalisierungsdateien des Spiels erweitern: Eingriff in Spieldateien (ADR-018).
- Nur die Oberfläche (JS) übersetzen: Toasts, Verlauf und Fehlermeldungen aus Lua blieben Deutsch.

## Begründung

Ein Ort für alle englischen Texte, kein Umbau der Meldungen, kein neues Netzformat; ein
fehlender Eintrag fällt sanft auf Deutsch zurück statt etwas zu zerbrechen.

## Konsequenzen

- **Jeder neue Spielertext braucht einen Eintrag in `Texts.js`** (ganz oder als Muster);
  `tests/test_texts_js.py` prüft Beispiele aus Oberfläche und Lua mit Node.
- Muster hängen am genauen deutschen Wortlaut: Wer einen Lua- oder JS-Text ändert, ändert das
  Muster mit.
- ADR-018 gilt weiter für Tonfall und `literal()`; „keine Übersetzung“ ist damit aufgehoben.
- Testen in der Testkopie: QA-Feld 6 von `Ui._QaLook` (1 Englisch, 2 Deutsch), nie die
  Spracheinstellung des Spiels (die gehört dem Eigner).
