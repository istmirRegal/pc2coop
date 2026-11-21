# ADR-021: Einstieg über einen runden Knopf links oben

- **Status:** Akzeptiert
- **Datum:** 2026-11-21
- **Betrifft:** FEAT-120, FEAT-111

## Kontext

Erster eigener Test des Eigners (UX-Overhaul P6, Fund A5/A6): Der Reiter „Multiplayer“ rechts an
der Bauleiste (ADR-007) machte die Leiste unsymmetrisch, und das Fenster öffnet links – der Weg
mit der Maus ging quer über den Bildschirm.

## Entscheidung

Der Einstieg ist ein runder Knopf in der Knopfspalte des Spiels links oben (unter den
Benachrichtigungen), gebaut mit dem `ManagementMenuButton` des Spiels. Das Fenster klappt direkt
darunter vom linken Rand aus. Der Reiter in der Bauleiste entfällt. F7 und das Pausemenü bleiben.

## Alternativen

- Knopf links in die Bauleiste: die Leiste gehört dem Spiel, jeder Eingriff dort war heikel
  (1.12.1, ADR-007).
- Eigener Griff am linken Rand: sähe nicht aus wie das Spiel.

## Folgen

- Der Eingriff hängt an `ManagementMenu.js`; nach Spiel-Updates prüfen (COMPONENTS.md).
- Die Oberkante des Fensters wird gemessen (`trackMenuButton`), weil die Spalte je nach Spielmodus
  mehr Knöpfe hat.
