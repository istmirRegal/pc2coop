# PC2Coop – Konzept für das Mehrspieler-Erlebnis

Stand: 2026-11-18. Arbeitsgrundlage für die nächsten Versionen; wird mit jeder Version
fortgeschrieben (Abschnitt „Stand“ am Ende).

## Grundsätze

1. **Eine stabile gemeinsame Basis zuerst.** Alles, was den Park für alle gleich macht, hat
   Vorrang vor Komfort. Was nicht übertragen wird, sagt die Mod offen (Hinweis statt stiller
   Abweichung).
2. **Aktionen dort, wo sie gebraucht werden.** Rechtsklick bzw. Info-Fenster eines Objekts
   bietet die passende Aktion („Team zur Testfahrt einladen“, „Kommentar anheften“). Das
   Multiplayer-Fenster bündelt die Zusammenarbeit, ersetzt diese Wege aber nicht.
3. **Spielt sich wie ein Teil des Spiels.** Eigene Teile sehen aus wie die des Spiels
   (Bau-Leiste, Info-Fenster, Radialmenü). Neue Bedienung wird beim ersten Mal kurz im Spiel
   erklärt; alles Weitere steht in der LIESMICH.
4. **Der Host ist die Instanz für die Simulation.** Geld, Gäste, Wetter, Pannen laufen beim
   Host. Mitspieler sehen dieselben Zahlen und Ereignisse; ihre eigenen Gäste sind Kulisse.
5. **Fremde Arbeit ist geschützt.** Rückgängig betrifft nur eigene Schritte; einen älteren
   Parkstand zurückzuholen betrifft alle und braucht eine Abstimmung.

## Was synchron ist – und was bewusst nicht

| Bereich | Weg | Stand |
|---|---|---|
| Deko, Gebäude, Gelände, Linien-Wege | Objekt-Abgleich / Aufzeichnung | fertig |
| Ebene Fahrgeschäfte | Aufzeichnung (bauen, verschieben, abreißen) | fertig |
| Achterbahnen, Schienenbahnen, Rutschen | Bauplan-Datei je Bahn | fertig (1.10) |
| Wege-Pinsel, Radierer, Stempel, Pools aus Formen, gezeichnete Flächen | Aufzeichnung | 1.12 (im Spiel teils geprüft) |
| Wege/Pools mit Anfassern bearbeiten, Widget | – | Hinweis an den Bauenden; folgt |
| Park-Zahlen, Meldungen (Pannen, Wartung, eingeschlossene Gäste, Blitz) | Host sendet | Meldungen fertig; **Marker im Park neu** |
| Einzelne Gäste, Warteschlangen, Erbrechen, Bedürfnisse | – | nicht möglich (Simulation im C++-Teil des Spiels, keine Skript-Schnittstelle) |

Gäste selbst bleiben pro Spieler simuliert. Damit es sich trotzdem gleich anfühlt, zeigen
**Ereignis-Marker** im Park, was beim Host passiert: Panne an „Conlan“ (Marker am
Fahrgeschäft, bis es repariert ist), Gäste eingeschlossen, Blitzeinschlag. Klick auf den
Hinweis fliegt hin.

## Einstiege (wo was ist)

| Ort | Inhalt |
|---|---|
| **Bau-Leiste unten, neuer Tab „Multiplayer“** (rechts neben Mehrfachauswahl) | öffnet das Multiplayer-Fenster |
| Pausenmenü „Multiplayer“, F7 | dasselbe Fenster (bestehend) |
| Spieler-Chips oben rechts | wer ist da, was tut er; Klick = folgen; Emotes kurz sichtbar |
| Info-Fenster / Rechtsklick an Objekten | Testfahrt einladen, Kommentar, Urheber (bestehend) |
| Besucher-Ansicht | eigenes kleines HUD, Steuerung per Tastatur (siehe unten) |
| Hauptmenü-Kachel „Mehrspieler“ | Lobby (bestehend) |

## Das Multiplayer-Fenster (im Park)

Fünf Bereiche als Reiter. Host und Mitspieler sehen dieselben Reiter; was nur der Host
ändern darf, ist für Mitspieler sichtbar, aber gesperrt (mit Begründung).

1. **Team** – Spieler mit Status und Bauwerkzeug, Folgen, Einladen, Freunde, Chat.
   *(heute: das Lobby-Fenster im Park)*
2. **Besuchen** – Als Besucher losgehen, Ich-Sicht des Spiels, Fahrgeschäfte mit Werten und
   Bewertungen, **gemeinsame Testfahrt** (Einladung an alle zu einer Bahn), **Führung**
   (einer führt, die anderen folgen automatisch).
3. **Planen** – **Baugebiete** markieren (Fläche + Auftrag „Familienattraktion, max.
   15.000 €, Wikingerstil“ + Zuständige), **Aufgaben** (offen/erledigt, zugewiesen),
   **Kommentare** an Objekten („Hier entsteht ein Engpass“), **Treffpunkt** setzen. Alles als
   Marker im Park sichtbar. *Bauvorschläge als transparente Vorschau: späterer Schritt.*
4. **Verlauf** – Ereignisse der Sitzung (wer hat was gebaut/abgerissen, große Ausgaben,
   Pannen), **„Seit deinem letzten Besuch“** (neue Fahrgeschäfte, Ausgaben, erledigte
   Aufgaben, offene Probleme) beim Betreten, **Sicherungspunkte** (Host speichert eine Kopie;
   Zurückholen nur nach Abstimmung aller).
5. **Sitzung** – Beitritt (nur Freunde / nachfragen), Rechte (Spieltempo: alle oder nur
   Host; Ausgaben über X € brauchen Freigabe; Abreißen fremder Bauten fragen; Besucher-Modus
   erlaubt), **Abwesenheit**: Standard „Park pausiert, wenn nur der Host da ist und er
   pausiert“ – dauerhaft laufende Parks sind kein Ziel dieser Mod (ein Park läuft nur beim
   Host).

## Besucher-Modus (v2)

- **Ansicht:** Dritte Person mit sichtbarer Figur; die anderen sehen die Figur im Park.
  Umsetzung: eigene Figur (Prefab) + Kamera dahinter; die Ich-Sicht bleibt als Option.
  Seit 1.13.0 (figure.lua): das Gast-Prefab des Spiels ohne Gast-Logik, mit festen Modellen
  und einer Gast-Animation je Zustand (stehen, gehen, rennen, Emotes) per ACSE
  CompilePrefab; Aussehen aus dem Frontier-Avatar (Gruppe, Farben), an alle verteilt.
- **Steuerung** wie in Actionspielen: Maus dreht direkt (Zeiger unsichtbar), WASD laufen,
  Shift schneller, **T halten** = Emote-Rad, **E** = interagieren (an der Station: mitfahren;
  später anstellen), **Tab** = zurück zum Bauen. Erster Start zeigt die Belegung kurz an.
- **Kollision:** keine Wände/Objekte durchlaufen (Strahl in Laufrichtung, Figur bleibt
  stehen), Boden folgt Gelände und Wegen.
- **Mitfahren** mit dem Sitz-Blick des Spiels; gemeinsame Testfahrt setzt alle in denselben
  Zug.
- **Grenzen:** Kaufen, Toiletten, Hunger/Laune sind im Spielcode nicht erreichbar (die
  Gäste-Simulation hat keine Skript-Schnittstelle). „Ich-Sicht“ nutzt den eingebauten
  Laufmodus des Spiels (Kamera „Visitor“: Boden, Springen, Ducken, Schwimmen, Lampe).

## Lobby, Status, Host und Mitspieler

- **Lobby (Hauptmenü):** wie heute Park wählen; zusätzlich Voreinstellungen der Sitzung
  (Rechte, Abwesenheit) sichtbar und vom Host einstellbar; später Modus „Wettbewerb“.
- **Status oben rechts:** bleibt schlank (Name, Tätigkeit, Emote, Folgen). Ereignisse
  erscheinen als Hinweise links unten und als Marker im Park, nicht in den Chips.
- **Host:** alle Reiter, ändert Sitzungsregeln, startet Sicherungspunkte/Abstimmungen.
- **Mitspieler:** dieselben Reiter; Sitzungsregeln nur lesbar; Anfragen (z. B. Freigabe
  einer Ausgabe, Übernahme einer Bahn) gehen an den Host bzw. an den, der gerade baut.

## Wettbewerb

Bauduell (beste Familienachterbahn mit festem Budget), Management-Challenge (gleicher
Startpark, Zufriedenheit nach 12 Monaten), Koop gegen eine Aufgabe (Park retten),
Team-Wettbewerb (zwei Themenbereiche). Voraussetzungen: gleiche Startbedingungen, gleiches
Bauangebot, klar erklärte Wertung; Gestaltung und Technik getrennt bewerten. Herausforderungen
und Szenarien des Spiels im eigenen Stil einbinden (Lobby-Reiter „Karriere/Herausforderung“).

Umgesetzt (1.12.0): **Bauduell** (Thema, 15/30/60 Minuten auf Echtzeit des Hosts, jeder in
seinem Baugebiet, danach Gestaltung und Technik getrennt 1–5, Ergebnis für alle) und
**Koop gegen die Uhr** (Brett-Aufgaben mit Zeitlimit). Szenarien und Herausforderungen
laufen unverändert beim Host – ihre Ziele gelten gemeinsam. Offen: Management-Challenge
(braucht getrennte Parks, geht mit einem gemeinsamen Spielstand nicht), Team-Wettbewerb.

## Kontextaktionen

Kurzer Mittelklick = Ping + kleines Menü am Mauszeiger für diese Stelle: Testfahrt
einladen / selbst mitfahren (Fahrgeschäft in 30 m), Übernahme anfragen (wer dort gerade
bearbeitet), Kommentar, Bauvorschlag, Baugebiet, Treffpunkt. Rechtsklick bleibt beim Spiel
(Kamera, Abbrechen) – so stört das Menü kein Werkzeug.

## Bauvorschläge

Brett-Eintrag „Vorschlag“ mit Ort, alle stimmen dafür/dagegen (eine Stimme pro Spieler,
der Host setzt den Namen). Eine durchscheinende Vorschau fremder Bauten geht nicht: das
Spiel zeigt Vorschauen nur für das eigene Werkzeug.

## Erklären

- Erste Benutzung einer Funktion: ein kurzer Hinweis im Spiel (einmal pro Spielstart:
  Mittelklick-Menü und Multiplayer-Reiter).
- Tooltips an den eigenen Knöpfen.
- LIESMICH im Paket: nur installieren in drei Schritten; Bedienung und Grenzen auf GitHub (README).

## Reihenfolge

1. Bau-Leiste: Tab „Multiplayer“ → Fenster mit den fünf Reitern (Team = heutiger Inhalt).
2. Ereignis-Marker für Meldungen des Host-Parks.
3. Planen: Baugebiete, Aufgaben, Kommentare, Treffpunkt (Marker im Park).
4. Verlauf: Ereignisliste, „Seit deinem letzten Besuch“, Sicherungspunkte.
5. Sitzung: Rechte und Abwesenheit.
6. Besucher v2: Steuerung (Tab/T/E, Maus-Look), Kollision, dritte Person mit Figur.
7. Gemeinsame Testfahrt, Führung.
8. Wettbewerb, Herausforderungen/Szenarien.

## Stand

- 1.12.0 (in Arbeit, alles noch im Spiel zu testen): fünf Reiter, Brett mit Vorschlägen,
  Ereignis-Marker, Verlauf, Sicherungspunkte mit Abstimmung, Regeln mit Voreinstellungen
  (bleiben über Parkwechsel), Mittelklick-Menü, Testfahrt-Einladung, Übernahme anfragen,
  Wettbewerb, Besucher v2. Dazu: Wege-Pinsel/Radierer, Löschen unter dem Mauszeiger, Stempel/Pools aus
  Formen, gezeichnete Flächen, Löschen per Mehrfachauswahl; Bauplan-Fahrgeschäfte;
  Bewertungen bleiben gespeichert; Ich-Sicht des Spiels; Hinweis bei nicht übertragenen Wege-Werkzeugen.
