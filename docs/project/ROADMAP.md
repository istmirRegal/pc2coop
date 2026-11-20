# Roadmap und offene Punkte

Richtung: `docs/KONZEPT.md` (Konzept des Eigners). Diese Datei sammelt, was offen ist.
Erledigtes wandert in CHANGELOG/DEVLOG; die Funktion bekommt ihren Status in der Registry.

## Als Nächstes

| Punkt | Notiz |
|---|---|
| **UX-Overhaul** | angekündigt vom Eigner; Ausgangslage `docs/ui-ux/UX_AUDIT.md`, `DESIGN_SYSTEM.md` |
| Test mit zwei (und drei) echten PCs | Abnahmebedingung aus `docs/COOP_DESIGN.md`; nach 1.5.0 nur mit nachgestelltem Mitspieler geprüft |
| Nexus-Quarantäne klären | Eigner lädt das Nexus-Zip ohne Skripte hoch und bittet um Prüfung (ADR-010) |

## Ungetestet im Spiel

- Echte Maus und Tasten im Besucher-Modus (bisher simulierte Eingaben).
- E an einem echten Eingang in der Ansicht von hinten mit einem zweiten Spieler.
- Seen und Wasserfälle über zwei PCs (FEAT-068).
- Fahrende Bahnen beim Tauschen des Bauplans (FEAT-072); Rückgängig an Achterbahnen.
- Alles aus 1.12.0/1.13.0 mit zwei echten Spielern.

## Später (aus KONZEPT.md)

- Wege/Pools mit Anfassern bearbeiten, Widget (heute nur Hinweis).
- Karriere und Herausforderungen/Szenarien gemeinsam spielen.
- Weitere Wettbewerbs-Formen.

## Aufräumen

Siehe `docs/changelog/DEVLOG.md`, Abschnitt „Bekannte Probleme und Aufräum-Kandidaten“
(`key:ping`, Legacy-Python, veraltete Kommentare).

## Nicht geplant (bewusst)

- Einzelne Gäste synchronisieren (keine Schnittstelle, siehe PROJECT_OVERVIEW).
- Einzelspieler-Funktionen des Spiels erweitern (ADR-014).
- Eigener Server oder Programm neben dem Spiel (ADR-001).
