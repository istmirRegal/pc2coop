# Glossar

| Begriff | Bedeutung |
|---|---|
| **ACSE** | Mod-Loader für Planet Coaster 2; lädt unsere Lua-Datenbank. Nicht in unseren Paketen. |
| **ADR** | Architecture Decision Record, `docs/decisions/ADR-nnn-*.md` |
| **Alias** | Zuordnung Host-gid → lokale Teil-Nummer nach dem Laden des Host-Parks (`A`-Zeile) |
| **Baseline** | Anzahl der Teile, die beim Laden schon im Park waren (`base`) |
| **Bauplan** (Blueprint) | Datei des Spiels mit einer Bahn; so werden Achterbahnen übertragen (ADR-006) |
| **Brett** | Planungsdaten pro Park: Gebiete, Aufgaben, Vorschläge, Kommentare, Treffpunkte |
| **Content Guard** | „Nur gemeinsame Inhalte“: DLC-Objekte nur, wenn alle das DLC haben |
| **Desync** | Ein Gast hat etwas nicht übernehmen können; „Neu synchronisieren“ holt den Park neu |
| **Dev-Flag** | `pc2coop-dev.flag` im Mod-Ordner der Testkopie; schaltet QA ein |
| **DLL** | `PC2CoopDiagnostic.dll`: Steam, Dateien, Tasten, Log |
| **Eigner** | Der Projektleiter (Owner); entscheidet Richtung und Veröffentlichung |
| **Emote** | kurze Geste der Figur (winken, jubeln …) |
| **FEAT-nnn** | ID einer Funktion in der Registry |
| **Figur** | Gast-Modell eines Spielers im Besucher-Modus (`figure.lua`) |
| **Gameface** | HTML/JS-UI-Technik des Spiels |
| **Gast** | 1) Mitspieler, der einer Sitzung beitritt (Client); 2) Parkbesucher des Spiels. Im Code: `client` bzw. `guest` |
| **Geist** | halbdurchsichtige Vorschau dessen, was ein Mitspieler hält |
| **gid** | sitzungsweite Kennung eines Teils: `P<n>` (Park) oder `<sid>-<n>` (neu) |
| **Halten** (hold) | Ein Spieler bearbeitet ein Objekt; für andere gesperrt |
| **Host** | Spieler, bei dem der Park läuft; einzige Autorität (ADR-003) |
| **Ich-Sicht** | Laufmodus des Spiels (`VisitorCamera`) im Besucher-Modus |
| **Look** | Aussehen der Figur (aus dem Avatar), Text von `Figure.LookText` |
| **Lobby** | Steam-Lobby der Sitzung; auch das Fenster im Hauptmenü |
| **ops** | Block von Änderungszeilen vom Host (`U`, `D`, `M`, `A`, `R`, `Y`, `K`) |
| **Part / Teil** | Szenerie-Teil des Spiels (Placement Part) mit lokaler Nummer |
| **Ping** | Markierung „hier!“ per kurzem Mittelklick |
| **Replay** | Wiederholen erlaubter Editor-Aufrufe beim Mitspieler (ADR-005) |
| **Restore** | Host setzt eine abgelehnte Änderung beim Autor zurück |
| **Revision** (rev) | Zähler pro Objekt; veraltete Änderungen werden abgelehnt |
| **Roster** | Spielerliste vom Host, alle 30 Frames |
| **sid** | Steam-ID eines Spielers |
| **Sitzung** | gemeinsames Spiel von Host und Gästen |
| **Stage** | wo die Sitzung gerade ist: `lobby` (Hauptmenü) oder `park` |
| **Testkopie** | vollständige Kopie des Spiels nur für Tests (ADR-008) |
| **Toast** | kurze Meldung unten links |
| **Tombstone** (Grabstein) | gelöschte gid beim Host; spätere Änderungen daran werden abgelehnt |
| **Viz** | Darstellung der Mitspieler in der Welt (`viz.lua`) |
