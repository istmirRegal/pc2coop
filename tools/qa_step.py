"""Run a fixed local game-bot step and require its own runtime acknowledgement."""
import argparse
from pathlib import Path
import os
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mod-dir',type=Path,required=True)
parser.add_argument('--pid',type=int,required=True)
parser.add_argument('--done',required=True,help='Completion substring expected after this command')
parser.add_argument('--timeout',type=float,default=60)
parser.add_argument('command',choices=('inspect','introspect','terrain-stroke','last-cmd','path-test','ride-probe','flatride-test','replay-last','transfer-test','join-load-test','stale-invite-test','join-dismiss','lobby-close','viz-probe','viz-clean','menu-lobby-test','menu-lobby-close','dlc-probe','extras-test','rejoin-test','rejoin-go','editor-hold-test','ghost-sweep','ghost-test','held-delete-test','profile-test','scale-probe','world-probe','gate-test','gate-check','lobby-test','chat-test','ui-test','focus-paths','recorder-on','rename-park','park-name','terrain-height','sync-stats','menu-test','save-probe','list-rocks','label-test','hold-test-rock','commit-held-rock','new-test-park','create-test-rock','verify-test-rock','save-test-park','reload-test-park','inspect-test-rock','move-test-rock','delete-test-rock'))
args=parser.parse_args()
directory=args.mod_dir.resolve(strict=True)
if directory.name!='PC2CoopProbe' or args.pid<=0 or not 0<args.timeout<=180:
    parser.error('Expected test mod directory, positive PID and bounded timeout')
log=directory/f'pc2coop-diagnostic-{args.pid}.log'
offset=len(log.read_bytes())
target=directory/f'pc2coop-inbox-{args.pid}.txt'
temporary=target.with_suffix('.tmp')
identity=str(time.time_ns())
temporary.write_text(identity+'|'+args.command,encoding='ascii')
os.replace(temporary,target)
print('Waiting for game acknowledgement:',identity,args.command,flush=True)
deadline=time.monotonic()+args.timeout
acknowledgement='qa:command:'+identity+':'+args.command
tail=''
while time.monotonic()<deadline:
    tail=log.read_bytes()[offset:].decode('utf8',errors='replace')
    if acknowledgement in tail:
        if any(error in tail for error in ('qa:task-error:','tick-error:','qa:rejected:','qa:create:rejected:','qa:reload:rejected:')):
            print(tail,flush=True)
            raise SystemExit('Runtime step rejected or failed')
        if args.done in tail:
            print(tail,flush=True)
            print('Runtime step completed:',args.command,flush=True)
            break
    time.sleep(0.2)
else:
    print(tail,flush=True)
    raise SystemExit('Timed out without this step completing')
