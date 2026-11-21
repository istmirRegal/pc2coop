# Changelog

Für Spieler: was sich in jeder Version geändert hat. Interne Änderungen stehen in
`docs/changelog/DEVLOG.md`. Neue Einträge zuerst unter „Unveröffentlicht“ sammeln.

## Unveröffentlicht

Funde aus dem ersten eigenen Test:

- Das Multiplayer-Fenster öffnest du im Park über einen runden Knopf links oben, wie die Knöpfe
  des Spiels dort. Das Fenster klappt direkt darunter aus. Der Reiter rechts an der Bauleiste ist
  weg, die Leiste ist wieder symmetrisch.
- Fenster und Listen scrollen mit dem Mausrad und haben die Scrollleiste des Spiels; keine
  Einstellung ist mehr verdeckt.
- „Enter Chat“ und „Markieren“ stehen in der Hinweiszeile des Spiels statt in einem eigenen
  Kasten über der Bauleiste.
- Die Sitzungsleiste im Hauptmenü sieht aus wie der Newsletter-Kasten und hat dieselben Kanten.
- Auf den Spielseiten (Sandbox, Franchise …) steht oben, dass der Park für alle öffnet.
- „+ Einladen“ markiert den Platz, bis du rechts einen Freund wählst.
- Pings sind kleiner, durchsichtiger und richten sich nach dem Abstand der Kamera.
- Besuch: Die Figur fährt an, bremst und dreht sich weich. Eingänge und Läden werden auch in
  Blickrichtung der Kamera und etwas zur Seite gefunden. Der Mauszeiger ist beim Umsehen weg.
  Die Tastenhinweise sehen aus wie die des Spiels. Zahlentasten tun im Besuch nichts mehr
  (Emotes mit der Maus, Kaufen per Klick).

- Die Knöpfe des Spiels für Pause, Tempo und Rückgängig sagen im Tooltip, warum sie in der
  Sitzung gesperrt sind (Regel „nur der Host“, nur der eigene letzte Schritt).
- Die Spieler oben rechts verdecken keine Fenster des Spiels mehr (z. B. Gelände oder
  Szeneriepinsel). Ist dort ein Fenster offen, rücken sie links daneben.
- Fehlt die Steam-Verbindung der Mod (zum Beispiel wenn der Virenscanner die DLL blockiert),
  sagen die Kachel und die Seite „Multiplayer“, woran es liegt und was hilft.
- Die Freundesliste zeigt nur, wer gerade erreichbar ist. Ist keiner online, steht das da.
- „Zurückholen…“ bei einem Sicherungspunkt fragt erst nach.

## 1.14.0 – 2026-11-21

Neue Oberfläche im Stil des Spiels (UX-Overhaul P0 bis P5).

- Beitreten zeigt vier Schritte (Verbinden, Zustimmung, Park kommt, Park lädt) mit
  Fortschritt, und du kannst bis zum Laden abbrechen.
- „Sitzung starten“ ist gesperrt, bis Steam antwortet. Klappt es nicht, siehst du warum.
- Eine Einladung ohne Antwort zeigt nach 2 Minuten „keine Antwort“; du kannst noch einmal
  einladen.
- Antwortet der Host nicht, steht oben „Keine Verbindung zum Host“ mit der Zeit und „Verlassen“;
  nach einer halben Minute fragst du „Warten“ oder „Verlassen“. Kommt die Verbindung wieder,
  wird die Anzeige kurz grün.
- Geht der Host ins Hauptmenü, fragt ein Dialog, ob du mitkommst oder im Park wartest.
- Ist der Host weg, sagt dir ein Dialog „Die Sitzung ist beendet“. Du kannst im Park allein
  weiterspielen oder ins Hauptmenü gehen.
- Das Emote-Rad sieht aus wie die Radialmenüs des Spiels, mit den Gast-Symbolen des Spiels.
- Fahrgeschäfte: Die Bewertung steht als Sterne da; deine Wertung gibst du mit fünf Sternen statt
  mit den Knöpfen 1 bis 5.
- Besuch wie der Laufmodus des Spiels: Die Leiste oben ist weg, die Tasten stehen unten rechts.
  Die Bauleiste ist im Besuch ausgeblendet. Was E vor einem Eingang tut, steht unter der
  Bildmitte, mit Grund, wenn es gerade nicht geht. Ein Laden zeigt ein kleines Kauf-Panel.
- Neu im Besuch: Taste **F** öffnet die Fahrgeschäfte links, solange ist die Maus frei zum Klicken.
- Die sechs Emote-Knöpfe sind weg; Emotes gibt es mit T (Rad).
- Wer beitreten möchte, wartet auf der Multiplayer-Seite als Karte in einem Platz; der Host
  lässt ihn mit Haken oder X zu oder lehnt ab.
- Öffnet der Host einen Park, sehen alle anderen sofort „… öffnet einen Park“. Im Park steht
  einmal „Alle sind da“, sobald niemand mehr lädt.
- Neu im Hauptmenü: die Seite „Multiplayer“ im Stil des Spiels (Esc führt zurück). Acht Plätze
  für die Spieler; ein Klick auf einen freien Platz lädt Freunde ein. Eingeladene stehen blass im
  Platz, bis sie kommen. Daneben der Chat.
- Den Park öffnet der Host jetzt auf den Seiten des Spiels („Sandbox“, „Franchise“). Alle in der
  Sitzung laden ihn mit. Die eigene Parkliste der Mod ist weg.
- Die kleine Sitzungskarte im Hauptmenü ist jetzt eine Leiste oben rechts und bleibt auf allen
  Seiten des Hauptmenüs sichtbar.
- Die Kachel „Multiplayer“ zeigt, ob eine Sitzung offen ist oder ein Freund eine hat.
- Vorschläge auf dem Brett zeigen „Dagegen“ nicht mehr als gewählt, wenn du noch gar nicht
  abgestimmt hast.
- Brett: Jeder Eintrag hat ein Icon für seine Art. Wer für eine Aufgabe oder ein Baugebiet
  zuständig ist, kannst du jetzt auch nachträglich ändern. Beim neuen Eintrag wählst du Art,
  Zuständig und Größe mit Pfeilen wie im Optionsmenü.
- Verlauf: Park-Meldungen haben „Hinbringen“ und „Ausblenden“. „Seit deinem letzten Besuch“
  kommt beim Beitritt einmal als Meldung und steht danach im Verlauf.
- Im Pausemenü kannst du die Sitzung jetzt auch verlassen oder (als Host) beenden.
- Schilder im Park zeigen keinen Punkt mehr vor dem Text.
- Der Reiter „Einstellungen“ sieht aus wie das Optionsmenü des Spiels: Schalter und
  Auswahl mit Pfeilen. Was eine Regel bedeutet, steht im Tooltip. Mitspieler sehen die Regeln
  gesperrt. Die Erklärtexte „Deine Rolle“ und „Abwesenheit“ sind jetzt Tooltips.
- „Beenden“ fragt jetzt nach („Für alle beenden?“), solange noch jemand in der Sitzung ist.
- Tooltips der Mod liegen nicht mehr unter dem Multiplayer-Fenster.
- Namensschilder im Park zeigen nur noch den Namen, in der Farbe des Mitspielers. Was er gerade
  tut, siehst du, wenn du mit der Maus auf seinen Namen oben rechts fährst.
- Die Spieler oben rechts zeigen statt abgeschnittenem Text ein Icon (baut, schaut zu, hält
  etwas, lädt). Der Tooltip sagt, was er tut, und dass ein Klick ihm folgt.
- Das Multiplayer-Fenster im Park ist jetzt ein Fenster wie die des Spiels am linken Rand. Du
  kannst weiterbauen, während es offen ist. Vier Reiter: Spieler, Planen, Verlauf, Einstellungen.
  Freunde lädst du über „+ Einladen“ ein. Der Chat rückt bei offenem Fenster daneben.
- „Besuchen“ ist ein Knopf im Fuß des Fensters statt eines eigenen Reiters.
- Einträge auf dem Brett haben Icon-Knöpfe (Haken, Daumen, Hinbringen, Löschen); ein neuer Eintrag
  geht über „+ Neuer Eintrag“.
- Änderst du Akzentfarbe oder Farbenblind-Modus, folgt die Mod-Oberfläche nach etwa einer
  Sekunde, auch die farbigen Streifen der Meldungen.
- Die Krone des Hosts ist in der Spielerliste des Fensters wieder zu sehen.
- „Hinbringen“ und „Folgen“ stehen in der Spieler-Karte in einer eigenen Zeile und passen wieder.
- F8 öffnet kein Entwickler-Menü mehr. Sitzung starten, einladen und verlassen geht im
  Multiplayer-Fenster (F7).
- Neu im Multiplayer-Fenster, Reiter „Einstellungen“: „Für dich“ mit dem Schalter „Mitspieler in
  der Welt zeigen“ (vorher nur im Entwickler-Menü).
- Dunkle Flächen der Mod (Chat, Meldungen, Karten) und die Linien im Fenster folgen jetzt
  deiner Akzentfarbe.
- Auch die Meldungen sagen jetzt „Sitzung“ statt „Lobby“.
- Wird eine Änderung von dir zurückgenommen, steht der Grund jetzt direkt am Objekt, mit
  Namen: „Vici baut hier gerade“ oder „Vici war schneller“. Das Objekt blinkt kurz in Vicis
  Farbe. Vorher kam nur eine Meldung ohne Namen.
- Die Oberfläche der Mod benutzt die Farben des Spiels. Sie folgt deiner Akzentfarbe und den
  Farbenblind-Modi.
- Die Oberfläche wächst mit Auflösung und UI-Skalierung wie das Spiel (vorher feste Pixel,
  bei 1440p und 4K zu klein).
- Abschnittstitel im Multiplayer-Fenster ohne Großbuchstaben, wie im Spiel.
- Größere, besser lesbare Schrift in der Größenordnung des Spiels.
- Einheitliche Begriffe:
  - „Sitzung“ statt „Lobby“ und „Park hosten“
  - „Hinbringen“ wie im Spiel
- Meldungen jetzt mit Umlauten.
- Neu: eine Anfrage-Karte oben für alles, was eine Antwort braucht: Beitrittsanfragen,
  Abstimmungen, Testfahrt-Einladungen und „Bewerten“ nach einem Bauduell. Vorher konnten sich
  zwei Banner überdecken, und Beitrittsanfragen standen nur im Fenster.
- Die Wettbewerbs-Uhr steht jetzt unter den Spielern oben rechts. Die Spielerleiste bleibt
  beim Mitfahren sichtbar (nur Avatare).
- Verbindungsprobleme erscheinen als Hinweis oben in der Mitte, „Nicht synchron“ mit dem Knopf
  „Neu synchronisieren“ direkt daneben. Vorher stand das nur im Fenster oder als großer Kasten
  in der Bildmitte.
- Icons sind sichtbar, z. B. die Krone des Hosts. Vorher waren sie unsichtbar.
- Der kurze Mittelklick (Markieren) öffnet jetzt ein Radialmenü mit Icons statt einer Liste.
  Unten rechts steht der Hinweis „Mittelklick Markieren“, damit man es findet.
- Neu: Chat unten links. **Enter** öffnet die Eingabe, Enter sendet, Esc schließt. Nachrichten
  und Ereignisse wie „Vici ist beigetreten“ stehen dort und blenden nach ein paar Sekunden aus;
  Warnungen erscheinen als Karten darüber.

## 1.13.0 – 2026-11-19

- Besucher-Figur ist jetzt ein animierter Parkgast im Look deines Frontier-Avatars; deine
  Mitspieler sehen dich gehen, rennen, winken.
- **V** wechselt zwischen Ansicht von hinten und der Ich-Sicht (Laufmodus des Spiels).
- **E** an Eingängen wie im Spiel (Fahrgeschäfte, Rutschen-Treppen, Shows) – mit den Texten des Spiels.
- Kaufen an Shops und Automaten: **E** zeigt die Waren, **1–6** kauft; der Preis geht in die
  Parkkasse des Hosts; deine Figur isst oder trinkt beim Gehen.
- „G – Gast begleiten“ aus einer Testversion ist wieder entfernt (doppelt zum Spiel).

## 1.12.3 – 2026-11-19

- Wege und Pools, die per Mehrfachauswahl gelöscht werden, verschwinden auch bei den Mitspielern.
- Pakete enthalten kein ACSE mehr – bitte ACSE selbst von Nexus installieren.
- Nexus-Paket ohne Skripte (zum Kopieren in den Spielordner).

## 1.12.2 – 2026-11-18

- Der Reiter „Multiplayer“ in der Bauleiste sperrt die Oberfläche nicht mehr.

## 1.12.1 – 2026-11-18

- Reiter in der Bauleiste heißt sichtbar „Multiplayer“.

## 1.12.0 – 2026-11-18

- Multiplayer-Fenster mit Reitern Team, Besuchen, Planen, Verlauf, Sitzung; Reiter in der Bauleiste.
- Brett pro Park: Baugebiete, Aufgaben, Bauvorschläge mit Abstimmung, Kommentare, Treffpunkte.
- Mittelklick-Menü: Testfahrt-Einladung, Mitfahren, Übernahme anfragen, Brett-Einträge.
- Verlauf mit Park-Meldungen und „Seit deinem letzten Besuch“; Sicherungspunkte mit Abstimmung.
- Sitzungsregeln mit Schnellwahl; Wettbewerbe (Bauduell, Koop gegen die Uhr).
- Besucher-Modus v2: Figur, Maus-Steuerung, Emote-Rad (T), Kollision.
- Pinsel/Radierer für Wege, Stempel, ebene Fahrgeschäfte als Bauplan.

## 1.11.0 – 2026-11-18

- Besucher-Modus: als Gast durch den Park laufen, mitfahren, Fahrgeschäfte bewerten, Emotes.

## 1.10.0 – 2026-11-18

- Achterbahnen, Schienenbahnen und Wasserrutschen werden synchronisiert (beim Verlassen des Editors).
- Eine Bahn im Streckeneditor ist für die anderen gesperrt.

## 1.9.1 – 2026-11-17

- Abreißen von ebenen Fahrgeschäften wird synchronisiert.

## 1.9.0 – 2026-11-17

- Park in der Lobby wählen (gespeichert, neu, Franchise); Chat-Feld; Klick auf Mitspieler = folgen;
  Ping mit kurzem Mittelklick (statt F6).

## 1.8.0 – 2026-11-17

- Lobby im Hauptmenü: Freunde warten dort und laden den Park, den der Host öffnet.
- Steam-Profilbilder, offene Lobbys von Freunden, DLC- und Mod-Vergleich, „Nur gemeinsame Inhalte“.
- Installer nutzt ein vorhandenes ACSE.

## 1.7.0 – 2026-11-17

- Ping für alle, Kamera folgen, Urheber am Objekt, Wiederbeitritt nach Absturz.

## 1.6.1 – 2026-11-17

- Sicherer Beitritt: nur Sitzungen von Steam-Freunden, Freigabe durch den Host, Dateien nur vom Host.

## 1.6.0 – 2026-11-15

- Mitspieler im Park sehen (Bodenmarke, Sichtkegel, Geist, Färbung); Sperren beim Bearbeiten.
- Pause und Tempo für alle; Zahlen und Meldungen des Host-Parks; Rückgängig nur für eigene Schritte.

## 1.5.0 – 2026-11-14

- Beitritt zuverlässiger (doppelte Steam-Meldung), viele Änderungen gebündelt, flüssigere Namensschilder.
- Dialoge mit Doppelpunkt im Text werden wieder angezeigt.

## 1.4.3 – 2026-11-14

- Park-Übertragung beim Beitritt bleibt nicht mehr bei 7 % hängen.

## 1.4.2 – 2026-11-14

- Läuft unabhängig von der genauen Spielversion.

## 1.4.1 – 2026-11-14

- Erste öffentliche Version: Live-Multiplayer über Steam mit Installer und Updater.
