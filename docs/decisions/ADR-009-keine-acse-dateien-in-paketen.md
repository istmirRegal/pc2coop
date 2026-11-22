# ADR-009: Keine ACSE-Dateien in Paketen

- **Status:** Akzeptiert
- **Datum:** 2026-11-19
- **Betrifft:** FEAT-002, FEAT-007

## Kontext

Frühere Pakete brachten ACSE mit. Das kollidierte mit vorhandenen ACSE-Installationen und
ließ Virenscanner und Nexus das Paket markieren.

## Entscheidung

Ab 1.12.3 enthält kein Paket ACSE. Spieler installieren ACSE selbst (Nexus); der Installer
bricht ohne ACSE mit klarer Meldung ab. Ein von alten Paketen installiertes ACSE bleibt.

## Alternativen

- ACSE mitliefern, nur wenn keins da ist (bis 1.12.2).

## Begründung

Klare Verantwortung, kleinere Pakete, keine fremden Binärdateien.

## Konsequenzen

- `tools/package_release.py` `check()` lehnt Pakete mit ACSE ab.
- README/LIESMICH nennen ACSE als Voraussetzung.

_Nachträglich dokumentiert am 2026-11-20 aus Code, Commits und Gesprächen._

_Nachtrag 2026-11-22 (ADR-023):_ ACSE (OpenNaja/ACSE) steht unter GPL-3; unverändert mitliefern
mit Lizenz und Quellenhinweis wäre erlaubt. Der Eigner fragt das ACSE-Team vorher. Bis dahin
bleibt ACSE draußen; Setup erkennt ein fehlendes ACSE und bietet die Seite bei Nexus an.
Mitgeliefert würde es nur, wo noch keins ist (die Kollision von 1.12.2 kam vom Überschreiben).
