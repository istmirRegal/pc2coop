# Navigation

Wie der Spieler zwischen den Teilen der Mod wechselt (Ist-Zustand 1.13.0).

## Hauptmenü

```
Hauptmenü ─ Kachel „Multiplayer“ / F7 / Sitzungsleiste „Öffnen“ ─► Seite „Multiplayer“ (Esc zurück)
   │                                        ├─ „Sitzung starten“ → Lobby (Host)
   │                                        ├─ Freund „Beitreten“ → Beitritt
   │                                        ├─ freier Platz „+ Einladen“ → Freundesliste rechts
   │                                        └─ Host: Kachel „Sandbox“/„Franchise“ → Seite des Spiels → Park öffnen → alle laden ihn
   └─ in einer Sitzung, Seite nicht offen ─► Sitzungsleiste oben rechts auf jeder Seite („Öffnen“ / „Beenden“)
```

Steam-Einladung angenommen → (`JoinConfirm`, wenn per Startparameter) → `JoinProgress` →
Lobby oder direkt der Park des Hosts. Fehler → `JoinFailed`. Nach Absturz beim nächsten
Start → `Rejoin`.

## Im Park

```
Bauen ─ F7 / runder Knopf links oben (Knopfspalte des Spiels) / Pausemenü „Multiplayer“ ─► Fenster links darunter (nicht modal, klappt aus)
          Reiter: Spieler · Planen · Verlauf · Einstellungen   (X/Esc zu; Bauen geht weiter)
          Fuß: „Besuchen“ ─► Besuch (Tab zurück)

Bauen ─ Mittelklick kurz ─► Markierung + Radialmenü (Testfahrt, mitfahren, Übernahme, Brett-Eintrag)
Bauen/Besuch ─ Enter ─► Chat-Eingabe unten links ─ Enter senden / Esc ─► zurück
Bauen ─ Klick auf Mitspieler oben rechts ─► folgen (nochmal klicken beendet)
Bauen ─ F8 ─► Entwickler-Dialog, nur mit Dev-Flag (Seite „Entwickler“ ↔ „Zurueck“)
```

## Besucher-Modus

```
Fenster „Besuchen“ ─ „Als Besucher losgehen“ ─► Besuch (von hinten, Figur)
                   ─ „Ich-Sicht“     ─► Besuch in der Ich-Sicht (Laufmodus des Spiels)
                   ─ Fahrgeschäft „Mitfahren“ ─► Besuch + Mitfahren

Besuch (von hinten) ⇄ V ⇄ Ich-Sicht
Besuch ─ E vor Eingang ─► Spiel-Interaktion (Anstellen/Einsteigen) → Mitfahren → „Zurück“ (Spiel) → Besuch
Besuch ─ E vor Laden  ─► Kaufliste (Maus frei) ─ Klick ─► kaufen, Figur isst/trinkt ─ E/Tab ─► Besuch
Besuch ─ T halten ─► Emote-Rad ─ T los ─► Emote
Besuch ─ „Fahrgeschäfte“ ─► Liste (mitfahren, bewerten, Vorschlag)
Besuch ─ Tab / „Zurück zum Bauen“ ─► Bauen
```

Wer die Navigation ändert, aktualisiert diese Datei und `docs/ui-ux/UI_INVENTORY.md`.
