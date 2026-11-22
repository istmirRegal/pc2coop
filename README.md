# PC2Coop – Planet Coaster 2 zusammen bauen

Mit PC2Coop baut ihr zu zweit oder zu acht live im selben Park. Ihr seht, wo die anderen gerade
bauen, chattet, plant zusammen und könnt den Park als Besucher ablaufen. Alles läuft über
Steam-Einladungen – kein Server, keine Portfreigabe, kein Zusatzprogramm.

*English below.*

## Installieren

1. Die neueste ZIP unter [Releases](../../releases/latest) (oder bei Nexus Mods) herunterladen
   und entpacken.
2. `PC2Coop-Setup.exe` doppelklicken und „Installieren“ drücken. Setup findet das Spiel selbst.
   Fragt Windows „Der Computer wurde durch Windows geschützt“: „Weitere Informationen“ →
   „Trotzdem ausführen“ (Setup ist nur nicht signiert).
3. Fehlt der Mod-Loader [ACSE](https://www.nexusmods.com/planetcoaster2/mods/1), sagt Setup es
   und öffnet die Download-Seite.

Updates holt Setup mit „Nach Update suchen“. Alle Mitspieler brauchen dieselbe Version von
PC2Coop und vom Spiel. Mit Vortex geht es auch: die ZIP wie jede andere Mod installieren und
einspielen – dann aber nicht zusätzlich Setup benutzen.

## Spielen

- **Hauptmenü → Multiplayer:** Sitzung starten und Freunde auf die freien Plätze einladen. Der
  Host öffnet den Park wie gewohnt über „Sandbox“ oder „Franchise“, alle laden ihn mit.
- **Im Park:** der runde Knopf „Multiplayer“ links oben. Mittelklick markiert eine Stelle für
  alle, Enter öffnet den Chat.
- Lade nur Leute ein, denen du deinen Park anvertraust: Mitspieler können bauen und abreißen.

## Wenn etwas nicht klappt

Im Multiplayer-Fenster unter „Einstellungen“ (oder unten auf der Seite „Multiplayer“) auf
**„Problembericht erstellen“** klicken. Die Datei liegt dann auf dem Desktop; schick sie per
Discord oder als [Issue](../../issues). Steam-IDs und Namen sind darin ersetzt, Chat steht nie
drin.

## Was schon geht – und was noch nicht

Synchronisiert werden Szenerie, Gelände, Wege, Wasser, Fahrgeschäfte, Achterbahnen, Shops,
Pause und Tempo, dazu Chat, Brett, Abstimmungen und der Besucher-Modus. Getestet wird jede
Version im Spiel mit nachgestellten Mitspielern; mit mehreren echten PCs ist längst nicht alles
geprüft. Was offen ist, steht in [docs/project/ROADMAP.md](docs/project/ROADMAP.md), was sich
geändert hat, im [Changelog](docs/changelog/CHANGELOG.md).

Sicherheitslücke gefunden? Bitte als Issue melden – ohne Logs mit fremden Steam-IDs.

## Für Entwickler

Lua-Mod über [ACSE](https://github.com/OpenNaja/ACSE), eine Oberfläche in der Gameface-UI des
Spiels und eine kleine DLL für Steam. Der Host ist maßgeblich: Er ordnet alle Änderungen und
schickt beim Beitritt seinen Park. Bauänderungen werden aus den Editor-Aufrufen des Spiels
mitgeschnitten und bei den anderen genauso abgespielt; aus dem Netz wird nie Code ausgeführt.

Einstieg: [docs/README.md](docs/README.md). Regeln für Menschen und KI, die mitarbeiten:
[CLAUDE.md](CLAUDE.md). Bauen und Release: [docs/development/RELEASE.md](docs/development/RELEASE.md).
Lizenz: MIT. ACSE ist nicht enthalten (eigenes Projekt, GPL-3).

---

## English

PC2Coop lets two to eight players build live in the same Planet Coaster 2 park over Steam
invites – no server, no port forwarding, no extra program.

**Install:** download the newest ZIP from [Releases](../../releases/latest) or Nexus Mods and
extract it. Double-click `PC2Coop-Setup.exe` and press "Install". If Windows says "Windows
protected your PC", click "More info" → "Run anyway" (Setup is just not signed). If the mod
loader [ACSE](https://www.nexusmods.com/planetcoaster2/mods/1) is missing, Setup tells you and
opens its page. Updates: "Check for update" in Setup. Everyone needs the same version.

**Play:** main menu → "Multiplayer", start a session and invite friends. In a park, the round
"Multiplayer" button top left; middle click marks a spot for everyone, Enter opens the chat. The
mod speaks English when the game is not set to German.

**Problems?** "Create problem report" in the multiplayer window (Settings) or at the bottom of
the "Multiplayer" page puts a file on your desktop – send it via Discord or an issue. Steam IDs
and names are replaced, chat is never in it.
