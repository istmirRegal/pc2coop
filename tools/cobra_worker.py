"""Build the original probe using a separately supplied Cobra Tools checkout."""
from pathlib import Path
import argparse
import contextlib
import hashlib
import json
import logging
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--cobra-tools', type=Path, required=True)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
if sys.version_info[:2] != (3, 11):
    raise RuntimeError('This pinned Cobra Tools build declares Python 3.11 support')
sys.path.insert(0, str(args.cobra_tools.resolve()))

from generated.formats.ovl import OvlFile
from modules.formats.shared import DummyReporter
from utils.config import Config

if not hasattr(logging, 'success'):
    logging.success = logging.info


class Reporter(DummyReporter):
    @contextlib.contextmanager
    def report_error_files(self, operation):
        errors = []
        yield errors
        if errors:
            raise RuntimeError(f'{operation}: {errors}')


def instance():
    ovl = OvlFile()
    config = Config(str(args.cobra_tools.resolve()))
    config.load()
    config['lua_flatten'] = True
    config['lua_decompile'] = False
    ovl.cfg = config
    ovl.reporter = Reporter()
    return ovl


ovl = instance()
ovl.game = 'Planet Coaster 2'
ovl.load_hash_table()
ovl.create(str(args.source.resolve()))
ovl.save(str(args.output.resolve()), commands={'update_aux': False})
check = instance()
check.load(str(args.output.resolve()), commands={'game': 'Planet Coaster 2'})
expected = {}
for source in args.source.rglob('*.lua'):
    name = source.relative_to(args.source).as_posix().replace('/', '.').lower()
    expected[name] = source.read_bytes()
extra = {source.relative_to(args.source).as_posix().replace('/', '.').lower()
         for source in args.source.rglob('*') if source.is_file() and source.suffix != '.lua'}
if set(check.loaders) != set(expected) | extra:
    raise RuntimeError('Unexpected archive entries: ' + repr(sorted(set(check.loaders) ^ (set(expected) | extra))))
for name, data in expected.items():
    if check.loaders[name].data_entry.buffer_datas[0] != data:
        raise RuntimeError(f'Lua round trip mismatch: {name}')
report = {
    'schema': 1,
    'package': 'PC2CoopProbe',
    'probe_version': '1.12.0',
    'cobra_tools_commit': '2dd9d1445608d6171c1ec1f2333cefb4d81a1317',
    'python': sys.version.split()[0],
    'game': check.game,
    'archive_version': int(check.version),
    'compression': check.user_version.compression.name,
    'lua_roundtrips': len(expected),
    'ovl_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
    'runtime_tested': False,
}
args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
print(json.dumps(report))
