# Datenfluss

Wie Daten durch die Mod laufen. Nachrichten-Formate: `docs/architecture/NETWORKING.md`.

## 1. Ein Szenerie-Teil wird gebaut oder geändert (FEAT-060, FEAT-061)

```
Spieler setzt Objekt
  → Spiel: api.undo.CommitPreview (von capture.lua ummantelt)
  → Handlers.BeforeCommit / Handlers.AfterCommit (sync.lua) lesen den Endzustand der Teile
  → sync:up|part|gid|rev|res|x|y|z|qx|qy|qz|qw|s   (gid leer = neu)
  → Session.OnSyncLine
       Host:  hostChange(me, …)            Gast: send(host, "up|…")
  → Host: authorityUp prüft Felder, Sperre, Content Guard, Revision, Grabstein
       ok:      Autor bekommt  M|gid|part|rev   (Host-gid für sein lokales Teil)
                alle anderen   U|gid|…           (Teil anlegen/setzen)
       Konflikt: Autor bekommt R|gid|grund|wer + U oder D (Host-Stand zurück) – restore()
                 → beim Autor Meldung am Objekt (Session.Conflicts, FEAT-082)
  → deliver → sendOps: "ops\n<Zeile>\n<Zeile>…" (≤ 3900 Zeichen pro Nachricht)
  → beim Empfänger toGame: Zeilen nummeriert (Folge-Nr.) → Sync.Receive
  → Sync.Tick: runOp in Reihenfolge, gleichartige Läufe gebündelt (FEAT-064)
```

Löschen läuft genauso mit `del` → `authorityDelete` → `D|gid|wer|rev`; gelöschte gids
kommen in `tombstones` (spätere Änderungen daran werden zurückgenommen).

Die gid: `P<n>` = Teil, das schon im Park des Hosts war (Teil-Nummer); `<sid-Ende>-<n>` = in
der Sitzung neu gebaut. Beim Laden des Host-Parks bekommt der Gast ein Manifest (`A|gid|part|rev`),
damit seine Teil-Nummern auf die gids passen.

## 2. Ein Editor-Aufruf wird abgespielt (Gelände, Wege, Seen, Stempel – FEAT-065)

```
Spieler malt Gelände / zieht Weg
  → replay.lua hat die erlaubten API-Methoden ummantelt (Whitelist)
  → Aufruf mit Argumenten als Text "!api.method(args)" gesammelt, bei Commit als Batch
  → sync:cmd|<batch> → Session → Host
  → Host: K|<batch> an alle anderen (Setter auch zurück an den Autor, damit alle denselben Wert haben)
  → Empfänger: Replay.Apply ruft dieselben Methoden mit geprüften Argumenten auf
```

Nichts davon ist Code: der Text wird gegen die Whitelist geparst (ADR-005).

## 3. Eine Achterbahn wird gebaut (FEAT-072)

```
Spieler verlässt den Streckeneditor
  → rides.lua speichert die Bahn als Bauplan pc2coop-ride-<n>-<m>.blueprint
  → sync:ride|old|new|file → Gast schickt die Datei per DLL (file) zum Host
  → Host: Y|old|new|file an alle, Datei per DLL an alle
  → Empfänger: Rides.Apply ersetzt die alte Bahn durch den Bauplan, wenn die Datei da ist
```

## 4. Beitritt (FEAT-025–031)

```
Gast nimmt Steam-Einladung an → DLL lobby:entered → Session: hello|…
Host: Versionsprüfung (reject) → Freigabe (wait / welcome / denied)
  → Host speichert eine Kopie seines Parks, sendet park|… und die Datei (file)
  → Gast lädt den Park (Parks.Load), meldet base|<anzahl>
  → Host schickt das Manifest (A-Zeilen) und alles, was inzwischen passiert ist (pending)
  → Gast: sync:started, roster kommt alle 30 Frames
```

## 5. Anwesenheit (FEAT-090–099)

```
Sync.Tick liest Kamera, Blickpunkt, Aktivität → sync:pres|… (nicht ins Log)
  → Gast → Host: pres → Host verteilt sofort p|sid|… an alle anderen
  → Session.View() → pc2coopqa.lua (Frame-Schleife) → Viz.Update + Labels.Show
```

## 6. Besuch: Kaufen (FEAT-169)

```
Spieler steht vor einem Laden, E → Visitor.Interact → Visitor.Shop (Menü mit Shop.Items)
  → Zahl 1–6 → Session.BuyPick → Gast: buy|shop-gid|index   Host: _HostBuy direkt
  → Host: Laden offen? Ware vorhanden? → Shop.Credit (AddCashDelta in den Park des Hosts)
  → sold|ok|… an den Käufer, em|sid|eat/drink|q an alle (Figur isst/trinkt)
```

## 7. Oberfläche (FEAT-118)

```
Lua → UI:  ui.lua schreibt den Zustand in den DataStore 'pc2coop' (nur bei Änderung)
           CoopLayer.js liest ihn und zeichnet
UI → Lua:  Engine.sendEvent('PC2Coop_Request', 'n|cmd|arg') → Ui._Request → Aktionstabelle
           in ui.lua (siehe docs/ui-ux/UI_INVENTORY.md)
Log:       Engine.sendEvent('PC2Coop_Log', …) → Diagnose-Log "js|…"
```

## 8. Was lokal gespeichert wird

| Datei (im Spielordner `Win64\ovldata\PC2CoopProbe\`) | Inhalt | Funktion |
|---|---|---|
| `pc2coop-diagnostic-<pid>.log` | Diagnose-Log | FEAT-216 |
| `pc2coop-lastsession.txt` | letzte Sitzung (Wiederbeitritt) | FEAT-039 |
| `pc2coop-authors-<park>.txt` | Urheber der Objekte | FEAT-098 |
| `pc2coop-board-<park>.txt` | Brett | FEAT-135 |
| `pc2coop-ratings-<park>.txt` | Bewertungen | FEAT-167 |
| `pc2coop-visits-<park>.txt` | letzter Besuch | FEAT-139 |
| `pc2coop-ride-*.blueprint` | übertragene Bahnen | FEAT-072 |
| `pc2coop-dev.flag` | nur Testkopie: QA an | FEAT-210 |

Der Spielstand selbst wird nur beim Host gespeichert (normal über das Spiel).
