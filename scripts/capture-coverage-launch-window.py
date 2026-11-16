#!/usr/bin/env python3
"""One read-only system launch window, not an app restart or test retry.
Only launchd/runningboard/SpringBoard records mentioning this bundle ID.
"""
import argparse,pathlib,subprocess

def capture(sim_id,output):
    start=(output/'start-utc.txt').read_text().strip()
    end=(output/'end-utc.txt').read_text().strip()
    predicate='(process == "runningboardd" OR process == "launchd" OR process == "SpringBoard") AND eventMessage CONTAINS "com.melusik.ate"'
    command=['log','show','--start',start,'--end',end,'--timezone','UTC','--style','compact','--info','--debug','--predicate',predicate]
    for name,prefix in [('host',['/usr/bin/log']),('simulator',['xcrun','simctl','spawn',sim_id,'log'])]:
        with (output/(name+'-launch-unified.log')).open('w') as sink:
            try:
                result=subprocess.run(prefix+command[1:],stdout=sink,stderr=subprocess.STDOUT,text=True,timeout=15)
                print('COVERAGE-LAUNCH-COLLECTOR source='+name+' returncode='+str(result.returncode),flush=True)
            except subprocess.TimeoutExpired:
                sink.write('\nCollector exceeded its 15-second bound; window incomplete.\n')
                print('COVERAGE-LAUNCH-COLLECTOR source='+name+' incomplete=1',flush=True)
            except OSError:
                sink.write('\nCollector OS error; window unavailable.\n')
                print('COVERAGE-LAUNCH-COLLECTOR source='+name+' os_error=1',flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--sim-id',required=True);parser.add_argument('--output',required=True,type=pathlib.Path)
    args=parser.parse_args();capture(args.sim_id,args.output)
