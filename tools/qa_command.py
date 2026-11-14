"""Send one fixed local diagnostic command to the prepared test mod."""
import argparse
from pathlib import Path
import os
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mod-dir',type=Path,required=True)
parser.add_argument('--pid',type=int,required=True)
parser.add_argument('command',choices=('inspect','introspect','terrain-stroke','last-cmd','path-test','ride-probe','flatride-test','replay-last','transfer-test','gate-test','gate-check','lobby-test','chat-test','ui-test','focus-paths','recorder-on','rename-park','park-name','terrain-height','sync-stats','menu-test','save-probe','list-rocks','label-test','hold-test-rock','commit-held-rock','new-test-park','create-test-rock','verify-test-rock','save-test-park','reload-test-park','inspect-test-rock','move-test-rock','delete-test-rock'))
args=parser.parse_args()
directory=args.mod_dir.resolve(strict=True)
if directory.name!='PC2CoopProbe' or args.pid<=0:
    parser.error('Expected the PC2CoopProbe test directory and a positive PID')
if not (directory/f'pc2coop-diagnostic-{args.pid}.log').is_file():
    parser.error('No diagnostic log for this process in this directory')
target=directory/f'pc2coop-inbox-{args.pid}.txt'
temporary=target.with_suffix('.tmp')
message=f'{time.time_ns()}|{args.command}'
temporary.write_text(message,encoding='ascii')
os.replace(temporary,target)
print('Queued local command; success requires a matching qa log result:',message)
