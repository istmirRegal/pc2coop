# Navigation

Wie der Spieler zwischen den Teilen der Mod wechselt (Ist-Zustand 1.13.0).

## Hauptmenü

```
Hauptmenü ─ Kachel „Multiplayer“ / F7 ─► Multiplayer-Fenster (Team-Ansicht)
   │                                        ├─ „Lobby erstellen“ → Lobby (Host)
   │                                        ├─ Freund „Beitreten“ → Beitritt
   │                                        └─ Host: „Wo spielen wir?“ → „Park öffnen“ → alle laden den Park
   └─ Fenster zu, in Lobby ─► Mini-Lobby-Karte („Lobby öffnen“ / „Verlassen“)
```

Steam-Einladung angenommen → (`JoinConfirm`, wenn per Startparameter) → `JoinProgress` →
Lobby oder direkt der Park des Hosts. Fehler → `JoinFailed`. Nach Absturz beim nächsten
Start → `Rejoin`.

## Im Park

```
Bauen ─ F7 / Reiter „Multiplayer“ (Bauleiste) / Pausemenü „Multiplayer“ ─► Fenster
          Reiter: Team · Besuchen · Planen · Verlauf · Sitzung   (Esc/„Schließen“ zurück)

Bauen ─ Mittelklick kurz ─► Ping + Kontextmenü (einladen, mitfahren, Übernahme, Brett-Eintrag)
Bauen ─ Klick auf Mitspieler oben rechts ─► folgen (nochmal klicken beendet)
Bauen ─ F8 ─► Entwickler-Dialog (Seite „Entwickler“ ↔ „Zurueck“)
```

## Besucher-Modus

```
Fenster „Besuchen“ ─ „Als Besucher losgehen“ ─► Besuch (von hinten, Figur)
                   ─ „Ich-Sicht (Spiel)“     ─► Besuch in der Ich-Sicht (Laufmodus des Spiels)
                   ─ Fahrgeschäft „Mitfahren“ ─► Besuch + Mitfahren

Besuch (von hinten) ⇄ V ⇄ Ich-Sicht
Besuch ─ E vor Eingang ─► Spiel-Interaktion (Anstellen/Einsteigen) → Mitfahren → „Zurück“ (Spiel) → Besuch
Besuch ─ E vor Laden  ─► Kaufliste ─ 1–6 ─► kaufen, Figur isst/trinkt ─ E/Tab ─► Besuch
Besuch ─ T halten ─► Emote-Rad ─ T los ─► Emote
Besuch ─ „Fahrgeschäfte“ ─► Liste (mitfahren, bewerten, Vorschlag)
Besuch ─ Tab / „Zurück zum Bauen“ ─► Bauen
```

Wer die Navigation ändert, aktualisiert diese Datei und `docs/ui-ux/UI_INVENTORY.md`.
