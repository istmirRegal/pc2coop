# Nächster spielbarer Meilenstein

Produktziel: mindestens drei gleichzeitige Spieler und möglichst einfacher
Ingame-/Steam-Beitritt. Zwei Clients bleiben nur ein früher Techniktest.

## Erreicht

Steam-Build 26255360 / PC2 1.12.2.1035111 identifiziert; vollständige unabhängige
Kopie erstellt; ACSE 0.729 und eigene Probe gepackt; Probe 0.0.3 bis ins Hauptmenü
geladen. Der Nutzer möchte ohne Sandboxie fortfahren. Daher vor weiteren Tests
das normale PC2-Profil sichern, ausschließlich eigene Testparks benutzen und
Steam-Cloud-Verhalten berücksichtigen. Eine Installationskopie trennt keine Saves.

## 1. Editor und Diagnose erfassen

Probe 0.0.3 zeigt ausgewählte API-Typen ohne Funktionsaufruf. Die Kennungen sind:
P=PreviewChangeList, C=CommitPreview, O=IsOperationComplete, io=globale IO-Library,
open=io.open, L=loadfile. Typen: f=Funktion, t=Tabelle, u=Userdata, n=nil,
-=fehlender Parent, !=fehlgeschlagener Feldzugriff. Diese Probe läuft beim
Datenbankstart; Welt-APIs können erst nach Laden eines Parks verfügbar werden.

Eine auslesbare, begrenzte Diagnoseausgabe aufbauen und den normalen Editor-
Commit zunächst beobachtend instrumentieren. Argumente, Rückgaben und Yield-
Verhalten erhalten. Nicht aus vorhandenen Funktionsnamen auf richtige Signaturen
oder erfolgreich abgeschlossene Operationen schließen. Native Adressen sind
weiterhin unbekannt und dürfen nicht aus älteren Builds übernommen werden.

## 2. Dauerhafte Bauaktion beweisen

Ein einfaches Basisspiel-Dekoobjekt in einem eigenen leeren Testpark verwenden.
Nach dem normalen Commit Ressourcenname und Transform zurücklesen. Genau eine
Aktion nachstellen, speichern und zweimal neu laden, ohne automatisches
Nachspawnen. Objektzahl, Ressource und Transform müssen stimmen. Move/Delete
separat prüfen. Für wiederholte Szenarien einen In-Game-Bot bauen.

## 3. Erst zwei, dann mindestens drei echte Clients

Nichtblockierende Verbindung außerhalb des Spielthreads. Nur bestätigte Aktionen
verteilen; logische IDs auf lokale Instanzen abbilden. Create/Move/Delete in
beiden Richtungen, Duplikate, Konflikte, Unterbrechung und Reload testen und beide
Welten zurücklesen. Anschließend drei parallele Bearbeiter, Sperren,
Disconnect/Wiederanmeldung und erneuten Beitritt prüfen.

Kamera-/Aktivitätsdaten getrennt von zuverlässigen Bauaktionen übertragen.
Sichtbare Marker zuerst, Geistervorschauen und Menütiefe danach. Beiträge und
Statistiken aus bestätigten Aktionen ableiten und mit dem Park dauerhaft speichern.

## 4. Online und weitere Bauelemente

Nach lokalem Nachweis: Verbindung zwischen PCs, Zugangskontrolle, Ressourcen-/DLC-
Berechtigungen, Fehlerbehandlung und Paketierung. Steam-Lobby/Einladungen und einen
eigenen Live-Co-op-Einstieg im Spiel prüfen. Die asynchrone Parkfreigabe ist kein
geprüfter Live-Transport. Wege, Gelände, Fahrgeschäfte und Grid-Gruppen benötigen
eigene Tests; Gäste und Wirtschaft eine eigene Synchronisationsstrategie.
