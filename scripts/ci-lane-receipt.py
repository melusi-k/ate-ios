#!/usr/bin/env python3
"""Exact-source execution receipts, not a test-result or native-pass substitute."""
import argparse,json,os,re,subprocess
from pathlib import Path

def verify_source(expected, actual):
    if not isinstance(expected,str) or not re.fullmatch(r'[0-9a-f]{40}',expected):
        raise ValueError('Missing or malformed frozen source SHA')
    if actual != expected:
        raise ValueError('Checkout does not match frozen source')
    return expected

def main():
    p=argparse.ArgumentParser()
    p.add_argument('mode',choices=['verify','write'])
    p.add_argument('--expected',required=True)
    p.add_argument('--lane')
    p.add_argument('--path',type=Path)
    args=p.parse_args()
    actual=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
    sha=verify_source(args.expected,actual)
    if args.mode=='write':
        if not args.lane or not re.fullmatch(r'[a-z0-9-]+',args.lane) or args.path is None:
            raise ValueError('Receipt needs a fixed lane and path')
        tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip()
        record={'source_sha':sha,'source_tree':tree,'lane':args.lane,
                'run_id':os.environ.get('GITHUB_RUN_ID'),
                'run_attempt':os.environ.get('GITHUB_RUN_ATTEMPT')}
        args.path.write_text(json.dumps(record,sort_keys=True,indent=2)+'\n')
        print('sha='+sha)

if __name__=='__main__':
    try:main()
    except (ValueError,subprocess.CalledProcessError) as error:
        raise SystemExit('Exact-source receipt refused: '+str(error))
