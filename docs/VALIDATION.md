# Prüfstand am 01.11.2026

## Ausgeführte Codeprüfungen

Letzter vollständiger Lauf unter Windows mit Python 3.11.9 und Lupa 2.6:

~~~text
Ran 57 tests in 0.377s
OK
~~~

- 11 Tests für Steam-Erkennung, unvollständige Downloads, VDF, Pfadbegrenzung,
  EXE-Architektur und Paket-Hashes mit künstlichen temporären Dateien.
- 18 Tests für das Offline-Befehlsmodell. Darunter 100 reproduzierbare Sitzungen
  mit je 100 vorgeschlagenen Aktionen: je 50 mit drei beziehungsweise vier
  Teilnehmern. Jedes akzeptierte Ereignis wird doppelt zugestellt; Zustand,
  Ereigniszahl und Hash müssen auf allen Replikaten dem Host entsprechen.
- 12 Tests für Sperren: parallele unabhängige Ziele, atomare Gruppensperren,
  veraltete/fremde Tokens, Ablauf, Erneuerung, Freigabe, Disconnect und Host-Uhr.
- 7 Tests für Präsenz: Sequenz, Ablauf, Absender/Parkstand und Wiederanmeldung.
- 3 Tests für Urheber, letzte Bearbeitung und Aktionsstatistik; Duplikate und
  abgelehnte Aktionen zählen nicht erneut.
- 6 Tests führen die Probe in Lua 5.3 mit simulierten APIs und strengem
  Modul-Environment aus: Registrierung, fehlendes/altes ACSE, Init, Marker-
  Deduplizierung und fehlender Logger/API. Editor-Aufrufe würden dort scheitern.

## Installation und Build

Die reale Steam-Installation wurde nach Abschluss des Downloads erneut gelesen:
Build 26255360, Version 1.12.2.1035111, x64, EXE 301397504 Bytes,
SHA-256 9da90ae2611bf41af532a30611082bd90cdda6b325e570ac63a469051e736c12.
Eine unabhängige Kopie mit 5685 Dateien und 39621003660 Bytes wurde geprüft.

Eigene Probe 0.0.3: OVL-Version 20, ZLIB, eine Lua-Datei. Der Build lud das
Archiv erneut und verglich den vollständigen Lua-Inhalt bytegenau mit der Quelle.
OVL-SHA-256: 738764327526fd44bf63fefb80933a10b9364d43d8f81b271994d59779ddb562.

ACSE 0.729 wurde separat aus Commit 8a843e61bcb57779778536e635d334d882cee7b1
gebaut: Init, Main und Extras, insgesamt 17 Lua-Roundtrips. Das ist ein lokaler
Quellbuild, keine Aussage über ein identisches Nexus-Downloadpaket. ACSEDebug und
ForgeUtils wurden nicht installiert.

## Beobachteter Spielstart

Ein erster Kopiestart ohne App-ID-Datei öffnete durch Steam die Original-EXE.
Dieser Lauf wurde an der Ersteinrichtung beendet und zählt nicht als Mod-Test.
Nach Ergänzung der echten PC2-App-ID nur in der Kopie wurde deren EXE bestätigt.
Die Ersteinrichtung führte der Nutzer selbst aus.

Im Hauptmenü der Kopie war sichtbar:

~~~text
Build 1.12.2.1035111 ACSE 0.729 PC2CoopProbe 0.0.3 Init OK
~~~

Das bestätigt den Datenbank-Init der eigenen Probe auf diesem Build. Es beweist
keine beliebige ACSE-/Mod-Kompatibilität und keine erfolgreiche Bauaktion.
Private Pfade, Profilinventare und Startberichte liegen außerhalb dieser
Auslieferung. Die Kopie verwendet auf Nutzerwunsch kein Sandboxie und hat kein
nachgewiesen getrenntes Speicherprofil.

## Noch nicht ausgeführt

Persistenter Editor-Commit, Platzieren/Verschieben/Löschen mit Save/Reload,
In-Game-Testbot, zwei oder drei reale Spielclients, sichtbare Mitspieler,
Geistervorschauen, persistente Beiträge, Steam-Einladungen und Netzwerktests
zwischen PCs. Spiel-QA: beobachteter Boot-Smoke-Test; keine automatisierte
Gameplay-/Multiplayer-QA. Die Offline-Modelltests ersetzen diese Nachweise nicht.

Auch Probe 0.0.3 erreichte nach einem Neustart sichtbar den Init-Marker im
Hauptmenü. Ihre längere API-Typzeile überlappt dort teilweise das Spiellogo;
sie ist noch kein zuverlässig maschinenlesbarer Schnittstellenbericht.
