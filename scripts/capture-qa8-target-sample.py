#!/usr/bin/env python3
"""One targeted Apple sample after the existing QA8 post-Exit MainActor lag signal.
No host-wide process enumeration, sudo, debugger attachment, app launch/termination,
retry or model reads. sample itself briefly suspends its one target at sample points.
"""
import argparse, pathlib, re, signal, subprocess, time
CHILD = None

def rows(text):
    result=[]
    for line in text.splitlines():
        fields=dict(re.findall(r'(\w+)=([^\s]+)',line))
        try:
            result.append((int(fields['pid']),fields['phase'],float(fields['uptime']),float(fields.get('phaseElapsed','0'))))
        except (KeyError,ValueError): continue
    return result

def target(main, scheduler):
    m=rows(main);s=rows(scheduler)
    exit_rows=[r for r in m if r[1]=='exit-return']
    fired=[r for r in s if r[1]=='scheduler-fired' and r[3]>=5]
    if not exit_rows or not fired:return None
    pid=exit_rows[-1][0]
    if pid<=1 or any(r[0]!=pid for r in m+s):return None
    last_main=max(r[2] for r in m)
    # Five-second utility delivery with no recent MainActor progress. This does
    # not establish a cause, only that one target stack would be informative.
    if fired[-1][2]-last_main<4:return None
    return pid

def identity_matches(command, sim_id):
    path=pathlib.PurePosixPath(command.strip())
    return path.is_absolute() and sim_id in path.parts and path.parts[-2:]==('Ate.app','Ate')

def stop(signum=None, frame=None):
    global CHILD
    if CHILD is not None and CHILD.poll() is None:
        CHILD.terminate()
        try:CHILD.wait(timeout=2)
        except subprocess.TimeoutExpired:CHILD.kill();CHILD.wait()
    raise SystemExit(0)

def capture(sim_id, output):
    global CHILD
    output.mkdir(parents=True,exist_ok=True)
    started=time.time();deadline=time.monotonic()+1800
    cache=None
    with (output/'status.txt').open('w',buffering=1) as status:
        status.write('watch-start utc_epoch='+str(started)+' max_seconds=1800 poll_seconds=5 one_target_only=1\n')
        while time.monotonic()<deadline:
            if cache is None:
                try:
                    found=subprocess.run(['xcrun','simctl','get_app_container',sim_id,'com.melusik.ate','data'],capture_output=True,text=True,timeout=3)
                    if found.returncode==0:
                        candidate=pathlib.Path(found.stdout.strip())
                        if candidate.is_absolute() and sim_id in candidate.parts:cache=candidate/'Library'/'Caches'
                except (OSError,subprocess.TimeoutExpired):pass
            if cache is not None:
                main=cache/'qa8-exit-diagnostic.txt';scheduler=cache/'qa8-exit-scheduler.txt'
                try:
                    # Never reuse previous-run exit evidence or unbounded file content.
                    if min(main.stat().st_mtime,scheduler.stat().st_mtime)>=started:
                        with main.open() as f:main_text=f.read(65536)
                        with scheduler.open() as f:sched_text=f.read(65536)
                        pid=target(main_text,sched_text)
                        if pid is not None:
                            status.write('trigger pid='+str(pid)+' utc_epoch='+str(time.time())+'\n')
                            process=subprocess.run(['/bin/ps','-p',str(pid),'-o','comm='],capture_output=True,text=True,timeout=3)
                            if process.returncode!=0 or not identity_matches(process.stdout,sim_id):
                                status.write('identity-unverified no-sample no-retry\n');return
                            (output/'trigger-main.txt').write_text(main_text)
                            (output/'trigger-scheduler.txt').write_text(sched_text)
                            with (output/'sample-command-status.txt').open('w') as console:
                                CHILD=subprocess.Popen(['/usr/bin/sample',str(pid),'3','10','-file',str(output/'qa8-ate-only.sample.txt')],stdout=console,stderr=subprocess.STDOUT)
                                try:
                                    code=CHILD.wait(timeout=15)
                                    status.write('sample-returncode='+str(code)+' utc_epoch='+str(time.time())+'\n')
                                except subprocess.TimeoutExpired:
                                    CHILD.kill();CHILD.wait();status.write('sample-collector-timeout=15 incomplete=1 no-retry\n')
                            CHILD=None
                            return
                except FileNotFoundError:pass
                except (OSError,subprocess.TimeoutExpired,ValueError):
                    status.write('evidence-or-identity-read-failed no-sample no-retry\n');return
            time.sleep(5)
        status.write('watch-expired no-qualifying-target capture-unverified\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--sim-id',required=True);parser.add_argument('--output',required=True,type=pathlib.Path)
    args=parser.parse_args()
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    capture(args.sim_id,args.output.resolve())
