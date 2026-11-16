#!/usr/bin/env python3
"""Bounded process metadata only, started before the unchanged Nutrition invocation.
No app data, command arguments, unified message bodies, paths or crash contents.
"""
import argparse, json, pathlib, subprocess, time

def filter_launchctl(text):
    rows=[]
    for line in text.splitlines():
        parts=line.split()
        if len(parts)!=3: continue
        pid,status,label=parts
        if 'com.melusik.ate' not in label and not any(x in label.lower() for x in ['testmanagerd','runningboardd','springboard']): continue
        if not (pid=='-' or pid.isdigit()) or not status.lstrip('-').isdigit(): continue
        # Fixed category instead of service label: labels may contain UUIDs.
        category='ate' if 'com.melusik.ate' in label else next(x for x in ['testmanagerd','runningboardd','springboard'] if x in label.lower())
        rows.append({'pid':int(pid) if pid.isdigit() else None,'status':int(status),'category':category})
    return rows[:32]

def capture(sim_id, output):
    output.mkdir(parents=True,exist_ok=True)
    start=time.monotonic()
    with (output/'process-metadata.jsonl').open('w') as sink:
        for index in range(49):
            delay=index*5-(time.monotonic()-start)
            if delay>0: time.sleep(delay)
            row={'sample':index,'monotonic':time.monotonic(),'elapsed':time.monotonic()-start,'utc_epoch':time.time()}
            try:
                result=subprocess.run(['xcrun','simctl','spawn',sim_id,'launchctl','list'],capture_output=True,text=True,timeout=4)
                row.update(returncode=result.returncode,processes=filter_launchctl(result.stdout))
            except subprocess.TimeoutExpired: row['collector_timeout']=1
            except OSError: row['collector_oserror']=1
            sink.write(json.dumps(row,separators=(',',':'))+'\n');sink.flush()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--sim-id',required=True);parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args();capture(args.sim_id,args.output)
