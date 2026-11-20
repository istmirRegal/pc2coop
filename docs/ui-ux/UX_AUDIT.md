# UX-Audit (Stand 1.13.0)

Beobachtungen aus dem Code und den Tests in der Testkopie, als Grundlage für das geplante
UX-Overhaul. **Nichts davon ist bisher geändert.** Jede Zeile hat eine ID (`UX-…`), damit
Änderungen darauf verweisen können. Erledigte Punkte bleiben mit Vermerk stehen.

Seit 2026-11-20 ist `docs/ui-ux/UX_OVERHAUL.md` die Arbeitsgrundlage (Inventar aller
Berührungspunkte, Bewertung, Zielbild). Dort sind alle IDs dieser Datei einem Berührungspunkt
`TP-nn` zugeordnet.

## A. Inhalt und Hilfetexte

| ID | Befund | Ort |
|---|---|---|
| UX-A1 | Reiter „Besuchen“, Abschnitt „Steuerung“ ist veraltet: nennt „E: einsteigen“, aber nicht Läden, V (Ich-Sicht) oder Kaufen; die Besucher-Leiste sagt es anders | `Lobby.renderVisit` |
| UX-A2 | Hilfezeile der Besucher-Leiste ist ein langer Satz mit 7–8 Tasten; schwer zu lesen im Laufen | `VisitorBar` |
| UX-A3 | Zwei Namen für dieselbe Sache: „Ich-Sicht (Spiel)“ im Fenster, „Ich-Sicht“ in der Leiste; der Fensterknopf schickt zwei Anfragen (`visitor`, `guest`) | `Lobby.renderVisit` |
| UX-A4 | „Führung: … dann folgst du ihm“ – feste männliche Form | `Lobby.renderVisit` |
| UX-A5 | Wettbewerbs-Uhr sagt „Bewerten: Multiplayer > Sitzung“ – Weg statt Knopf | `CompBanner` |
| UX-A6 | „Karriere · später“ und „Herausforderung – kommt später“ sind sichtbar, aber ohne Funktion | `renderChooser`, `MODES` |

## B. Sprache und Einheitlichkeit

| ID | Befund | Ort |
|---|---|---|
| UX-B1 | Texte aus Lua (Feed, Toasts, F8-Dialog) ohne Umlaute („geloescht“, „Fahrgeschaeft“, „Schliessen“, „Zurueck“), JS-Texte mit Umlauten | `session.lua`, `menu.lua` |
| UX-B2 | F8-Dialog benutzt den Spiel-Dialog mit Fließtext; sieht anders aus als das Multiplayer-Fenster und doppelt Teile davon (Hosten, Einladen, Verlassen) | `menu.lua` |
| UX-B3 | Bezeichnungen wechseln: „Raum hosten“ (F8) / „Lobby erstellen“ / „Diesen Park hosten“; „Sitzung“ / „Lobby“ / „Raum“ | `menu.lua`, `Lobby` |

## C. Auffindbarkeit

| ID | Befund | Ort |
|---|---|---|
| UX-C1 | Kontextmenü (Übernahme, Kommentar, Testfahrt) erscheint nur nach einem kurzen Mittelklick; nirgends erklärt außer in „Deine Rolle“ | `ContextMenu` |
| UX-C2 | Folgen per Klick auf die Spielerleiste ist nicht beschriftet, bis man folgt | `PlayerBar` |
| UX-C3 | Zuständigen eines Brett-Eintrags kann man nur beim Anlegen setzen (Aktion `board_assign` hat keinen Knopf) | `Lobby.renderPlan` |
| UX-C4 | Sterne-Bewertung sind Knöpfe „1“…„5“, die eigene Wahl als „(n)“ – schwache Rückmeldung | `VisitorBar` |
| UX-C5 | Vier Wege ins Fenster (F7, Bauleiste, Pausemenü, Hauptmenü-Kachel) – gut; aber kein Hinweis auf F7 in der Oberfläche | – |

## D. Layout

| ID | Befund | Ort |
|---|---|---|
| UX-D1 | Fenster fest 1320 × 780 px, Liste 1000 px: bei kleiner Auflösung oder großer UI-Skalierung nicht geprüft | `Lobby`, `VisitorBar` |
| UX-D2 | Abstimmungs- und Einladungs-Banner liegen beide bei 140 px oben Mitte und können sich überdecken | `VoteBanner`, `InviteBanner` |
| UX-D3 | Besucher-Leiste (52 px) und Wettbewerbs-Uhr (18 px) oben Mitte: Abstand zur Spiel-HUD oben nicht in allen Modi geprüft | `VisitorBar`, `CompBanner` |
| UX-D4 | Spielerleiste verschwindet beim Mitfahren (Kamera-Leiste des Spiels) – gewollt, aber dann sieht man keine Mitspieler | `PlayerBar` |
| UX-D5 | Toasts: max. 5, 6 s, kein Weg zurück außer Reiter „Verlauf“ (P1: `ChatArea`, Enter zeigt die letzten 12 Zeilen) | `Toasts` |

## E. Rückmeldung und Zustände

| ID | Befund | Ort |
|---|---|---|
| UX-E1 | Gesperrte Knöpfe (z. B. Hosten nicht möglich) sagen nicht warum | `Lobby` Fuß |
| UX-E2 | Abgelehnte Änderungen (Konflikt, Regel) nur als Toast; das Objekt springt zurück ohne Markierung (erledigt 2026-11-20: Meldung am Objekt, FEAT-082; Regel-Ablehnungen bleiben Karten) | `session.lua` `restore` |
| UX-E3 | Statuszeile im Fuß ist die einzige Stelle für den Verbindungszustand im Fenster | `statusOf` |

## Noch nicht geprüft

Echte Maus/Tasten statt simulierter Eingaben, zwei echte PCs, Controller, andere
Auflösungen und UI-Skalierungen, Spielsprachen außer Deutsch (die Mod-Texte sind nur Deutsch).
