#!/usr/bin/env python3
"""Fail closed unless both required Dogfood groups succeeded on one source."""
import argparse,json,subprocess
from pathlib import Path
import importlib.util
spec=importlib.util.spec_from_file_location('lane_receipt',Path(__file__).with_name('ci-lane-receipt.py'))
receipt=importlib.util.module_from_spec(spec);spec.loader.exec_module(receipt)
LANES=('qa-critical-flows','library-popup')
def validate(source,needs):
    receipt.verify_source(source,source)
    if not isinstance(needs,dict):raise ValueError('Needs must be an object')
    pin=needs.get('pin-source',{})
    if pin.get('result')!='success' or pin.get('outputs',{}).get('sha')!=source:
        raise ValueError('Source pin incomplete or mismatched')
    scope=needs.get('changes',{})
    if scope.get('result')!='success' or scope.get('outputs',{}).get('app')!='true':
        raise ValueError('Native classification incomplete')
    for lane in LANES:
        job=needs.get(lane,{})
        if job.get('result')!='success' or job.get('outputs',{}).get('sha')!=source:
            raise ValueError('Required lane incomplete or wrong source: '+lane)
    return list(LANES)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--needs-json',required=True)
    args=p.parse_args()
    try:
        actual=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
        receipt.verify_source(args.source,actual)
        for lane in validate(args.source,json.loads(args.needs_json)):print('EXACT-SOURCE JOB SUCCESS '+lane)
    except (ValueError,TypeError,AttributeError,subprocess.CalledProcessError) as error:
        raise SystemExit('Qualification refused: '+str(error))
