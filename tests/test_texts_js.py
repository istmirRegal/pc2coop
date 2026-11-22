"""Texts.js: the English texts of the multiplayer layer (ADR-022), run with Node.

The layer's German texts (CoopLayer.js) and the German texts Lua sends to it (toasts, the
session's log, activities, join errors) must come out in English; names, numbers and what
players wrote stay as they are.
"""
from pathlib import Path
import json
import shutil
import subprocess
import unittest

TEXTS = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/Texts.js'
NODE = shutil.which('node')

CASES = {
    # layer texts
    'Spieler': 'Players',
    'Sitzung starten': 'Start session',
    'Starte eine Sitzung – Freunde treten bei und bauen mit.': 'Start a session – friends join and build with you.',
    'Vici (du)': 'Vici (you)',
    'Sitzung von Vici': 'Vici’s session',
    'Vici – baut · Klicken zum Folgen': 'Vici – is building · Click to follow',
    'Vici – formt das Gelände': 'Vici – is shaping the terrain',
    '3 / 8 Spieler · Seepark': '3 / 8 players · Seepark',
    'Aufgabe · Vici → Sam · 2 dafür, 1 dagegen': 'Task · Vici → Sam · 2 for, 1 against',
    'Spaß 6.5 · Angst 4.2 · Übelkeit 1.8': 'Excitement 6.5 · Fear 4.2 · Nausea 1.8',
    'Keine Verbindung zum Host · 0:42': 'No connection to the host · 0:42',
    'Empfange den Park von Vici … 42 %': 'Receiving Vici’s park … 42 %',
    'Der Host wählt im Hauptmenü einen Park.': 'The host is choosing a park in the main menu.',
    'Vici öffnet einen Park – gleich lädt er bei allen.': 'Vici is opening a park – it will load for everyone shortly.',
    'Geld 12.345': 'Money 12,345',
    '1.234 Besucher · Geld unbegrenzt': '1,234 guests · Unlimited money',
    'Bauduell · Thema: Wikinger · noch 4:59': 'Build duel · Theme: Wikinger · 4:59 left',
    'Gestaltung 4.5 · Technik 3.0 (1 Stimme)': 'Design 4.5 · Engineering 3.0 (1 vote)',
    'Sam möchte bei „Achterbahn“ weitermachen.': 'Sam would like to carry on with “Achterbahn”.',
    # texts from Lua
    'Vici hat 3 Objekte platziert': 'Vici placed 3 objects',
    'Vici hat Rock_04 gelöscht': 'Vici deleted Rock_04',
    'Ein Mitspieler hat das Spiel pausiert': 'A player paused the game',
    'Host lässt das Spiel laufen (x5)': 'Host lets the game run (x5)',
    'Vici ist der Sitzung beigetreten': 'Vici joined the session',
    'Vici bewertet Conlan mit 4/5: mehr Schatten': 'Vici rates Conlan 4/5: mehr Schatten',
    'Regeln "Geordnet": Spieltempo: nur der Host, Fremde Bauten abreißen: erst fragen':
        'Rules "Orderly": Game speed: host only, Demolish others’ builds: ask first',
    'Seit deinem letzten Besuch: 2 neue Fahrgeschäfte (A, B); Kasse -300 EUR':
        'Since your last visit: 2 new rides (A, B); Cash -300 EUR',
    'Wartung fällig: Conlan': 'Maintenance due: Conlan',
    'Die Sitzung ist voll.': 'The session is full.',
    'Beitritt nicht möglich (Steam-Code 5). Lass dich neu einladen.': 'Can’t join (Steam code 5). Ask for a new invitation.',
    'Der Host hat PC2Coop 1.13.0, du 2.1.0. Ihr braucht dieselbe Version: Spiel beenden, PC2Coop-Setup → „Nach Update suchen“.':
        'The host has PC2Coop 1.13.0, you have 2.1.0. You need the same version: quit the game, PC2Coop Setup → “Check for update”.',
    'Tipp: Markieren zeigt allen eine Stelle und bietet Aktionen dafür an (Kommentar, Testfahrt, Übernahme). '
    'Alles Weitere öffnet der runde Knopf „Multiplayer“ links oben.':
        'Tip: Mark shows everyone a spot and offers actions for it (comment, test ride, takeover). '
        'The round “Multiplayer” button top left opens everything else.',
    'Änderung von Vici zurückgenommen: hier nicht möglich (z. B. außerhalb der Parkgrenze)':
        'Vici’s change undone: not possible here (e.g. outside the park boundary)',
    'fährt Conlan': 'is riding Conlan',
    'Vici kauft Burger (4,50 €)': 'Vici buys Burger (4,50 €)',
    'Gekauft: Burger (4,50 €)': 'Bought: Burger (4,50 €)',
    'Chat unten links einblenden': 'Show chat bottom left',
    'Stand 3': 'Checkpoint 3',
    # what players wrote, names and keys stay
    'Hallo zusammen': 'Hallo zusammen',
    'Vici': 'Vici',
    'E': 'E',
    '': '',
}


@unittest.skipIf(NODE is None, 'Node is not installed')
class TextsTests(unittest.TestCase):
    def translate(self, texts):
        script = ("import { createTranslator } from " + json.dumps(TEXTS.as_uri()) + ";\n"
                  "const tr = createTranslator();\n"
                  "const input = JSON.parse(process.argv[1]);\n"
                  "process.stdout.write(JSON.stringify(input.map(tr)));\n")
        out = subprocess.run([NODE, '--input-type=module', '-e', script, json.dumps(texts)],
                             capture_output=True, text=True, encoding='utf8', timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_german_texts_come_out_in_english(self):
        german = list(CASES)
        for text, english in zip(german, self.translate(german)):
            self.assertEqual(english, CASES[text], text)

    def test_every_exact_entry_is_english(self):
        # No German left in the English column (umlauts are a sure sign).
        source = TEXTS.read_text(encoding='utf8')
        exact = source[source.index('const EXACT = {'):source.index('\n};\n')]
        import re
        for german, english in re.findall(r"'((?:[^'\\]|\\.)*)': '((?:[^'\\]|\\.)*)'", exact):
            self.assertNotRegex(english, '[äöüÄÖÜß]', german)


if __name__ == '__main__':
    unittest.main()
