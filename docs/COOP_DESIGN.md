# Gemeinsam an einem Park bauen

Anforderungen vom 01.11.2026. Ziel: mindestens drei Freunde spielen gleichzeitig
im selben PC2-Park, mit eigener Kamera, möglichst ohne technische Einrichtung
zwischen den Spielabenden. Drei Spieler sind eine Abnahmebedingung; ein
Zwei-Spieler-Test ist ein Zwischenschritt. Mehr Teilnehmer werden im Modell
bereits berücksichtigt; eine reale Obergrenze ist noch nicht ermittelt.

**Status:** Entwurf plus offline getestete Modelle. Keine der nachfolgenden
Oberflächen, Einladungen oder Weltanzeigen ist bereits im Spiel implementiert.

## Gewünschter Ablauf

1. Mod einmal installieren; einer öffnet den Park und wählt „Gemeinsam bauen“.
2. Freunde über Steam einladen oder alternativ einen privaten Einladungscode teilen.
3. Versionen, Modstand und gemeinsam nutzbare Ressourcen automatisch abgleichen.
4. Den gleichen bestätigten Parkstand laden, dann alle Teilnehmer zum Bauen freigeben.
5. Jeder sieht die anderen, kann unabhängig bauen und nach einer Unterbrechung
   möglichst ohne manuelles Kopieren zurückkehren.

Der Host verwaltet den bestätigten Parkzustand und die Reihenfolge der Änderungen.
Alle zugelassenen Freunde können bauen. Pause, Spieltempo, Laden und Speichern
brauchen eine gemeinsame Regel; zunächst entscheidet der Host über diese globalen
Aktionen. Automatische Hostübernahme und nahtloses Wiederverbinden nach jedem
beliebigen Absturz sind noch keine zugesagten Eigenschaften.

## Vorbilder und was wir daraus ableiten

- [Parkitect, Entwicklerseite](https://www.themeparkitect.com/): bis zu acht
  Spieler gemeinsam in Sandbox und Kampagne.
- [Parkitect, offizielle Multiplayer-Ankündigung](https://store.steampowered.com/news/posts/?appids=453090&enddate=1612355350&feed=steam_community_announcements):
  gemeinsame Parkbearbeitung, sichtbare Aktionen und direkte Steam-Einladungen;
  gemeinsame DLC-Auswahl. Das ist ein passendes Vorbild für den Spielablauf.
- [OpenRCT2, offizieller Changelog](https://www.openrct2.io/download/changelog):
  Spielerfenster mit Viewport/Verfolgung und Gruppen-/Baurechte.
- [OpenRCT2, öffentliches Netzwerk-Interface](https://github.com/OpenRCT2/OpenRCT2/blob/develop/src/openrct2/network/Network.h):
  letzte Spieleraktion und deren Position, ausgeführte Befehle, ausgegebenes Geld
  und Berechtigungsprüfungen. Das liefert Referenzen für Spieleranzeigen und
  Beiträge; es ist kein Beweis, dass PC2 dieselben Daten bereitstellt.

Unsere Sperrstrategie ist eine eigene Designentscheidung. Es wird nicht behauptet,
dass Parkitect oder OpenRCT2 dieselben Sperren verwenden. Wir übernehmen keinen
Spielcode aus diesen Projekten. PC2-Determinismus ist nicht bewiesen; fremde
Synchronisationsmodelle werden deshalb nicht unverändert übertragen.

## Was beim Bauen gesperrt wird

Sperren gelten für tatsächliche Bearbeitung, niemals bloß für eine Kamera,
Menüauswahl oder das Anschauen eines Objekts.

| Tätigkeit | Vorgeschlagene Sperre |
| --- | --- |
| Neue freie Deko platzieren | Eigene, vorübergehende Vorschau; beim Commit Host-Prüfung. Der übrige Park bleibt frei. |
| Vorhandene freie Deko bewegen/löschen | Dieses Objekt während der Bearbeitung. |
| Gebäudegruppe bearbeiten, verschieben, trennen/verbinden | Betroffene Gruppe und alle abhängigen Mitglieder gemeinsam anfordern. |
| Achterbahn/Flume bearbeiten | Zunächst die gesamte betroffene Anlage; feinere Teilung erst mit Nachweis. |
| Weg-/Pool-/Geländewerkzeug | Betroffener Bereich samt abhängiger Geometrie. Bis diese Abhängigkeiten zuverlässig berechnet werden können, breitere Sperre oder Werkzeug im Co-op deaktivieren. |
| Globale Parkwerte, Laden, Speichern | Host-Regel; keine zufällige Entscheidung durch das zuletzt geöffnete Menü. |

Beispiel: A baut eine Achterbahn, B dekoriert den Eingang, C baut an einer
anderen Stelle. Das soll parallel gehen. Möchte B As aktive Anlage bearbeiten,
zeigt sie „Wird gerade von A bearbeitet“. B kann weiter an anderen Dingen bauen.

Mehrere benötigte Sperren werden vollständig oder gar nicht vergeben. Die
Host-Uhr bestimmt ihre Laufzeit. Eine aktive Bearbeitung erneuert die Sperre;
Abbrechen oder Beenden gibt sie frei. Ein neues Token verhindert, dass eine
verspätete Aktion eines früheren Bearbeiters doch noch angewendet wird.

**Wichtige Laufzeitgrenze:** Das Modell hat keine asynchronen PC2-Commits. Im
Spiel darf ein Timeout ein noch laufendes oder unklar abgeschlossenes
Editor-Kommando nicht überholen. Betroffene Objekte müssen bis zum Readback/
Abgleich gesperrt bleiben. Ein Disconnect widerruft neue Anfragen der Verbindung;
alte Verbindungen dürfen sich nicht mit einer neuen Spieleranmeldung vermischen.

Ein Urhebervermerk ist keine permanente Bearbeitungssperre. Gemeinsame Bauten
sollen von Freunden weiterbearbeitet werden können. Undo gilt zuerst nur für
eigene unterstützte Aktionen, deren Ziel seitdem nicht von anderen verändert
wurde. Ein globales Undo, das fremde Arbeit entfernt, ist kein Standard.

## Mitspieler sehen

Jeder erhält eine wiedererkennbare Farbe. Geplant sind:

- Weltmarker am Blickziel bzw. Baubereich, dazu Kameraposition und Blickrichtung.
- Eine kleine beschriftete Blase, etwa „Alex · baut Deko“ oder
  „Sam · Achterbahn bearbeiten“. Der Status beschreibt das verlässlich erkannte
  Werkzeug/Menü, keine geratenen Aktionen und keine beliebigen Texteingaben.
- Optional ein transparenter Bauentwurf für gerade platzierte Objekte.
- Eine Spielerliste mit „Bei Spieler ansehen“ und optionalem Kamera-Folgen.
- Ein-/ausblendbare Vorschauen, Namen und Marker, damit ein voller Park lesbar bleibt.

Positions-/Menü-/Vorschaudaten ersetzen jeweils den letzten Wert. Alte Pakete
werden verworfen; ausbleibende Meldungen blenden Marker aus. Nach Wiederanmeldung
erhält die Verbindung eine neue Generation. Dieses kurzlebige Signal ist von
bestätigten Bauaktionen getrennt. Es erzeugt keine echten Parkobjekte, keine
Kosten und keine Save-Einträge. Darstellung und genaue Lua/UI-Hooks sind offen.

## Wer hat was gebaut?

Bei unterstützten Objekten sollen „Erstellt von“, „Zuletzt bearbeitet von“ und
eine Änderungshistorie abrufbar sein. Für gemeinsam bearbeitete Gebäude bleiben
mehrere Beiträge erhalten. Eine optionale Farbanzeige markiert Urheber, ohne die
normalen Materialien dauerhaft zu verändern.

Die Statistik zählt bestätigte Aktionen wie gesetzt, bearbeitet und gelöscht;
Nachrichtenwiederholungen zählen nicht noch einmal. Eine Vorschau zählt nicht
als Bauwerk. Baukosten und Bauzeit werden erst ergänzt, wenn deren Bedeutung
und zuverlässige Erfassung geklärt sind. Das Offline-Modell enthält noch keine
solchen Kosten- oder Zeitstatistiken.

Namen sind Anzeigeattribute. Langfristig braucht jeder Beitrag eine stabile
Spieleridentität, die Umbenennungen übersteht. Eine Mod-Metadatendatei oder
geprüfte In-Save-Integration muss Urheber und Objektzuordnung passend zum
jeweiligen Park-Checkpoint speichern. Metadaten dürfen bei fehlender Zuordnung
nicht auf zufällig passende Runtime-IDs übertragen werden.

## Steam und das vorhandene Multiplayer-Menü

[Steam-Lobbies](https://partner.steamgames.com/doc/features/multiplayer/matchmaking)
unterstützen Einladungen über das Overlay und Join-Callbacks. Die Lobby ist die
Sitzungsverwaltung; sie synchronisiert keine PC2-Bauten. Die eigentliche
Verbindung und Bau-Synchronisation bleiben Aufgaben der Mod.

[Steam Networking](https://partner.steamgames.com/doc/api/ISteamNetworkingSockets)
und [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)
sind Kandidaten für P2P/Relay ohne manuelles Portforwarding. Nutzbarer App-Kontext,
Initialisierung, Callbacks und Verträglichkeit mit PC2s vorhandener Steam-Anbindung
müssen geprüft werden. Ein generischer API-Aufruf ist noch kein Integrationsbeweis.
[Valves API-Übersicht](https://partner.steamgames.com/doc/sdk/api) beschreibt den
App-Kontext und die Initialisierungsbedingungen. Eine feste Zusage unter PC2s
AppID oder der Test-App 480 wird hier nicht gemacht.

Der bevorzugte sichtbare Einstieg ist eine eigene „Live-Co-op“-Option im Spiel,
idealerweise erreichbar beim Park-/Multiplayer-Menü. Ob wir das bestehende Menü
erweitern können, ist offen. Der vorhandene Austausch von Parkständen ersetzt
keinen Echtzeitkanal. Eine Verknüpfung mit offiziellen Cloud-/Franchise-Funktionen
wird erst nach Untersuchung ihrer Schnittstellen und Konfliktregeln entschieden.
Der erste Lauf nutzt einen separaten Sandbox-Testpark.

Fallback: private Einladung mit möglichst automatisch erreichbarer Verbindung.
Ein erforderlicher Relay-Dienst wäre eine eigene Abhängigkeit; ein solcher
Dienst ist noch nicht eingerichtet. Eine VPN-Pflicht ist kein gewünschter
Standard für das spätere Spielerlebnis.

## Implementierter Stand und Abnahme

| Teil | Aktuell |
| --- | --- |
| Mindestens drei Spieler | Modelltests für drei und vier; keine realen Spielclients. |
| Bearbeitungssperren | Offline LeaseBook; Host kann Move/Delete daran prüfen. Gruppenabhängigkeiten noch nicht an PC2 angebunden. |
| Position, Blickziel, Aktivität/Menü | Offline PresenceBook mit Ablauf, Reihenfolge und Verbindungs-Generationen; kein sichtbarer Marker. |
| Urheber, letzter Bearbeiter, Historie, Aktionszahlen | Offline ContributionLedger; keine dauerhaften Parkmetadaten. |
| Geister, Weltblasen, Spieler verfolgen | Geplant; keine Darstellung implementiert. |
| Steam-/Ingame-Beitritt | Recherche und Zielablauf; kein Transport implementiert. |
| Laufender Park inklusive Fahrgeschäften, Gästen und Wirtschaft | Gesamtziel; dafür fehlen noch nachgewiesene Lese-/Schreib-/Synchronisationspfade. |

Der erste soziale Spieltest braucht drei reale Clients: A platziert, B bewegt ein
anderes Objekt, C bearbeitet ebenfalls; alle sehen passende Marker. Zwei greifen
auf dasselbe Ziel zu, der dritte kann parallel weiterbauen. Wiederholte Pakete
duplizieren weder Objekte noch Statistik. Disconnect und Wiederanmeldung hinterlassen
keine alten Marker, Tokens oder unklaren Commits. Anschließend müssen alle
bestätigten Objektzustände und Beiträge zusammenpassen.

Vor diesem Test bleiben unverändert nötig: Mod wirklich laden, eine
Editorplatzierung mit Readback nachweisen und Save-/Reload-Verhalten prüfen.
