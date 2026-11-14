"""Pack probe/PC2CoopProbe/ui/** into the mod's Gameface UI package (.ppuipkg XML).

The game mounts UI packages under <basic_path>; views load them as coui://<file_name>.
"""
import base64
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / 'probe' / 'PC2CoopProbe' / 'ui'
TARGET = PROJECT / 'probe' / 'PC2CoopProbe' / 'Main' / 'pc2coopui.ppuipkg'


def main():
    entries = []
    for path in sorted(SOURCE.rglob('*')):
        if path.is_file():
            data = path.read_bytes()
            name = path.relative_to(SOURCE).as_posix()
            entries.append(
                f'\t\t<ppuipkgfile file_size="{len(data)}">\n'
                f'\t\t\t<file_name>{name}</file_name>\n'
                f'\t\t\t<file_content encoding="base64">{base64.b64encode(data).decode("ascii")}</file_content>\n'
                f'\t\t</ppuipkgfile>\n')
    xml = ('<PPUIPKGRoot game="Planet Coaster 2">\n\t<basic_path>GameMain/Content</basic_path>\n\t<files>\n'
           + ''.join(entries) + '\t</files>\n\t<icondata />\n</PPUIPKGRoot>\n')
    TARGET.write_text(xml, encoding='utf8')
    print(f'{TARGET.name}: {len(entries)} files')


if __name__ == '__main__':
    main()
