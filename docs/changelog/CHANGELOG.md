# Changelog

Für Spieler: was sich in jeder Version geändert hat. Interne Änderungen stehen in
`docs/changelog/DEVLOG.md`. Neue Einträge zuerst unter „Unveröffentlicht“ sammeln.

## Unveröffentlicht

## 2.1.0 – 2026-11-22

Einfacher installieren, Probleme leichter finden.

- **Eine ZIP für alle.** Auf GitHub und Nexus Mods liegt dieselbe Datei. Entpacken,
  PC2Coop-Setup.exe doppelklicken, „Installieren“ – fertig. Setup findet das Spiel selbst,
  merkt, wenn ACSE fehlt (und öffnet dann die Download-Seite), und holt auf Knopfdruck Updates.
- **Vortex** legt PC2Coop jetzt richtig ins Spiel, nur den Mod-Ordner.
- **Problembericht.** Klappt etwas nicht, erstellt „Problembericht erstellen“ eine Datei auf dem
  Desktop (im Park: Multiplayer → Einstellungen; im Hauptmenü unten auf der Seite
  „Multiplayer“). Steam-IDs und Namen sind darin ersetzt. Einfach dem Entwickler schicken.
- Fehler der Mod werden mit der genauen Stelle aufgeschrieben; stürzt das Spiel ab, steht es im
  Log. Bei einem Fehler der Mod läuft das Spiel weiter.
- Haben zwei Spieler verschiedene Versionen, sagt die Meldung jetzt: Setup → „Nach Update suchen“.

**Wer PC2Coop schon hat:** Das alte UPDATE.cmd kann diese Version nicht installieren. Einmal die
neue ZIP herunterladen und Setup starten – danach aktualisiert Setup selbst.

## 2.0.0 – 2026-11-21

Die große Überarbeitung: PC2Coop sieht aus wie ein Teil des Spiels, spricht Englisch und ist
sicherer übers Netz. (Während der Entwicklung hieß diese Version 1.14.0.)

**Neu**
- Englisch: Läuft Planet Coaster 2 nicht auf Deutsch, ist auch die Mod englisch.
- Seite „Multiplayer“ im Hauptmenü: acht Plätze, Freunde einladen mit einem Klick, Chat. Den
  Park öffnet der Host auf den Seiten des Spiels, alle laden ihn mit.
- Im Park: runder Knopf „Multiplayer“ links oben, das Fenster klappt darunter auf. Du baust
  weiter, während es offen ist.
- Chat unten links mit Enter (abschaltbar unter „Für dich“).
- Eine Karte oben für alles, was eine Antwort braucht: Beitritt, Abstimmungen, Testfahrten,
  Übernahmen.
- Beitreten in vier sichtbaren Schritten, bis zum Laden abbrechbar.

**Besser**
- Alles im Stil des Spiels: Farben, Schrift, Knöpfe, Scrollen und Tooltips; folgt Akzentfarbe,
  Farbenblind-Modus, Auflösung und UI-Skalierung.
- Markieren verdeckt nichts mehr: Am Objekt blinkt sein Umriss, am Boden liegt ein Punktkreis.
- Klare Hinweise, wenn der Host nicht mehr antwortet, ins Hauptmenü geht oder die Sitzung endet,
  jeweils mit Warten, Mitkommen oder Verlassen.
- Wird eine Änderung zurückgenommen, steht am Objekt, warum („Vici baut hier gerade“).
- Besuch: weichere Figur, Tasten wie im Laufmodus des Spiels, Kaufen per Klick.
- Stabiler bei wackeliger Verbindung: Kommt der Park nicht an, fragt die Mod neu. Nach dem
  Neuladen sind Brett, Regeln und Bewertungen wieder da.
- Sicherer: Niemand kann die anderen mit Nachrichten fluten oder fremde Dateien überschreiben.

**Behoben**
- Gespeicherte Parks ließen sich manchmal nicht öffnen („unknown park“).
- Die Log-Datei zeigte im Editor nur chinesische Zeichen.
- Der Installer warnte bei jedem, die Spielversion sei nicht getestet.
- Meldungen ohne Umlaute, unsichtbare Icons, Tooltips unter dem Fenster.

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
