# Roadmap und offene Punkte

Richtung: `docs/KONZEPT.md` (Konzept des Eigners). Diese Datei sammelt, was offen ist.
Erledigtes wandert in CHANGELOG/DEVLOG; die Funktion bekommt ihren Status in der Registry.

## Als Nächstes

| Punkt | Notiz |
|---|---|
| **UX-Overhaul** | gebaut bis P6 (`docs/ui-ux/UX_OVERHAUL.md`, ADR-020); Abnahme mit zwei PCs offen |
| Test mit zwei (und drei) echten PCs | Abnahmebedingung aus `docs/COOP_DESIGN.md`; nach 1.5.0 nur mit nachgestelltem Mitspieler geprüft |
| Nexus mit Setup.exe | Eigner lädt die eine ZIP (ADR-023) bei Nexus hoch; zeigen, ob Nexus die EXE annimmt |
| ACSE mitliefern? | Eigner fragt das ACSE-Team (GPL-3 erlaubt es); bei Ja installiert Setup ACSE, wo keins ist |
| Code-Signatur für Setup | gegen die SmartScreen-Frage; kostet (z. B. Azure Trusted Signing), braucht eine Identitätsprüfung des Eigners |

## Ungetestet im Spiel

- Echte Maus und Tasten im Besucher-Modus (bisher simulierte Eingaben).
- E an einem echten Eingang in der Ansicht von hinten mit einem zweiten Spieler.
- Seen und Wasserfälle über zwei PCs (FEAT-068).
- Fahrende Bahnen beim Tauschen des Bauplans (FEAT-072); Rückgängig an Achterbahnen.
- Alles aus 1.12.0/1.13.0/2.0.0 mit zwei echten Spielern.
- Die Oberfläche aus 2.0.0 mit echter Maus und Tastatur (UX-Overhaul P6).
- Setup-Fenster mit echter Maus auf einem fremden PC; Installation über Vortex (2.1.0).

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
