# Navigation

Wie der Spieler zwischen den Teilen der Mod wechselt (Ist-Zustand 1.13.0).

## Hauptmenü

```
Hauptmenü ─ Kachel „Multiplayer“ / F7 ─► Multiplayer-Fenster (Team-Ansicht)
   │                                        ├─ „Sitzung starten“ → Lobby (Host)
   │                                        ├─ Freund „Beitreten“ → Beitritt
   │                                        └─ Host: „Wo spielen wir?“ → „Park öffnen“ → alle laden den Park
   └─ Fenster zu, in Lobby ─► Mini-Lobby-Karte („Sitzung öffnen“ / „Verlassen“)
```

Steam-Einladung angenommen → (`JoinConfirm`, wenn per Startparameter) → `JoinProgress` →
Lobby oder direkt der Park des Hosts. Fehler → `JoinFailed`. Nach Absturz beim nächsten
Start → `Rejoin`.

## Im Park

```
Bauen ─ F7 / Reiter „Multiplayer“ (Bauleiste) / Pausemenü „Multiplayer“ ─► Fenster links (nicht modal)
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
Besuch ─ E vor Laden  ─► Kaufliste ─ 1–6 ─► kaufen, Figur isst/trinkt ─ E/Tab ─► Besuch
Besuch ─ T halten ─► Emote-Rad ─ T los ─► Emote
Besuch ─ „Fahrgeschäfte“ ─► Liste (mitfahren, bewerten, Vorschlag)
Besuch ─ Tab / „Zurück zum Bauen“ ─► Bauen
```

Wer die Navigation ändert, aktualisiert diese Datei und `docs/ui-ux/UI_INVENTORY.md`.
