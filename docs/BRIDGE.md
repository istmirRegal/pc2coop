# Spielanbindung

Die eigene DLL wird über `package.loadlib` aus dem eigenen Inhaltspaket geladen.
ACSEDebug verwendet denselben Ladeweg; dessen fehlende native Implementierung
wurde nicht übernommen. Die DLL enthält nur eigenen MIT-Code.

Die Diagnoseausgabe nutzt ausschließlich C-Callbacks ohne Argumentzugriff und
ohne Lua-Rückgaben: Begin, zwei Halbbytes je Byte und End. So hängt die erste
auslesbare Ausgabe nicht von Frontier-spezifischen Lua-Datenstrukturen ab.
Datensätze sind auf 4096 Bytes und die lokale Datei auf 4 MiB begrenzt. Die Datei
liegt neben der DLL und enthält die Prozess-ID. Es gibt keine Internetverbindung.
Das ist ein Diagnosekanal für geringe Datenmengen, kein fertiger Netztransport.

Probe 0.0.4 schrieb im echten Spiel die Testfolge mit UTF-8 und eingebettetem
Nullbyte unverändert. Sie bestätigte die Typen der Undo-Funktionen, einschließlich
`IsOperationComplete`, als Funktionen. Editor-Hooks waren registriert, eine
Platzierung wurde damit noch nicht beobachtet.

Der Commit-Hook erfasst Metadaten vor dem ursprünglichen Aufruf und meldet eine
abgeschlossene Aktion erst nach dessen Rückkehr. Der ursprüngliche Aufruf liegt
außerhalb eines Fehlerfängers; Yields, Fehler und sämtliche Rückgaben bleiben
erhalten. Nur die zusätzliche Diagnose wird mit `pcall` abgefangen. Vorhandene
Spielmethoden werden referenziert, dekompilierte Spielquellen werden nicht
ausgeliefert.

Der experimentelle Rückgabetest in `native/string_probe.cpp` verwendet die
Stringroutine des exakten Steam-Builds 26255360 bei RVA `0x1e29f50`. Voraussetzungen
sind EXE-Größe und vollständiger SHA-256, PE64, ausführbarer Speicher und 64
übereinstimmende Funktionsbytes. Er läuft ausschließlich auf dem aufrufenden
Lua-Thread. Die DLL liest begrenzt beobachtete Stackfelder, schreibt aber keine
eigenen Lua-Tags oder GC-Objekte. Auf anderen EXEs gibt sie null Ergebnisse zurück.
Es wird keine Standard-Lua-DLL mit dem Spiel verlinkt.

Ein früher Rückgabetest beendete den Spielprozess schon bei der Hashprüfung.
Messpunkte und kleinere Stackframes wurden ergänzt. Anschließend bestand Probe
0.0.5 im echten Spiel Greeting, leeren String, UTF-8 mit Nullbyte und 256
zurückbehaltene feste Strings nach `collectgarbage("collect")`. Die vollständige
EXE-Hashprüfung und der Vergleich des gemappten Funktionsanfangs bestanden.
Der Prozess erreichte danach das Hauptmenü. Ohne Crashdump bleibt Stackmangel
eine begründete Vermutung für die früheren Abbrüche, keine bewiesene Diagnose.

Der Stand 0.0.6 ergänzt eine PID-gebundene lokale Eingabedatei mit maximal 4096
Bytes. Der Spielthread prüft sie alle 30 Manager-Advances. Nur feste Befehle
werden akzeptiert; eingelesener Text wird niemals als Lua ausgeführt. Das ist
vorübergehende lokale Teststeuerung, kein produktiver Mehrspielertransport.

Die Windows-Speicherprüfung folgt [VirtualQuery](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualquery).
Die Hashprüfung verwendet [Windows CNG](https://learn.microsoft.com/en-us/windows/win32/seccng/creating-a-hash-with-cng).
Der [Lua-Stringvertrag](https://www.lua.org/manual/5.3/manual.html#lua_pushlstring)
erlaubt eingebettete Nullbytes; das beweist keine Übereinstimmung interner
Frontier-Datenstrukturen mit Standard-Lua.

## Lokal bauen

Bereits installiertes x64 MSVC und Windows SDK verwenden, zum Beispiel:

```powershell
python tools/build_native.py --msvc '<MSVC-Versionsordner>' --sdk '<Windows Kits/10>' --sdk-version '10.0.26100.0'
python tools/verify_native.py build/native/PC2CoopDiagnostic.dll
```

Der zweite Befehl lädt eine Kopie der DLL in einem wegwerfbaren Python-Prozess.
Er prüft alle 256 Bytewerte, UTF-8, Nullbytes, leere Daten, die Größenbegrenzung,
abgeschnittene Datensätze und die Ablehnung des Rückgabepfads außerhalb von PC2.
Dies ersetzt keinen Test mit einer echten Lua-State-Instanz im Spiel.
