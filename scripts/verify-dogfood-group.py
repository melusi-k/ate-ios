#!/usr/bin/env python3
"""Strict native Dogfood group evidence. No pass marker overrides any failure."""
import argparse,json,re,subprocess
from pathlib import Path
GROUPS={
 'qa':[
  'KeyFlowsQATests/testQA1_AddFromURL_JSONLD',
  'KeyFlowsQATests/testQA1_AddFromURL_InstagramCaption',
  'KeyFlowsQATests/testQA1_AddFromURL_HiddenCaptionFallback',
  'KeyFlowsQATests/testQA2_AddFromPhoto',
  'KeyFlowsQATests/testQA3_GenerateAndEdit',
  'KeyFlowsQATests/testQA4_Save',
  'KeyFlowsQATests/testQA5_Share',
  'KeyFlowsQATests/testQA6_OpenShared',
  'KeyFlowsQATests/testQA8_Timers'],
 'library':[
  'AteUITests/test28_GroupSortAndMenus',
  'AteUITests/test29_ReorderMyOrder',
  'AteUITests/test29b_ReorderMyOrderActions']}
def validate(log,group,document,exit_code=0):
 if exit_code!=0:raise ValueError('Nonzero exit or termination cannot qualify')
 expected=GROUPS[group]
 verdicts=re.findall(r'^\*\* TEST (SUCCEEDED|FAILED) \*\*\s*$',log,re.M)
 if not verdicts or verdicts[-1]!='SUCCEEDED' or 'FAILED' in verdicts:raise ValueError('Missing or failing anchored final verdict')
 if re.search(r'Test Case .* failed|exceeded execution time allowance|Fatal error:|Testing failed:',log):raise ValueError('Native failure evidence cannot be overridden')
 summaries=re.findall(r'^\s*Executed (\d+) tests?, with (\d+) failures?(?:\s|\().*$',log,re.M)
 if not summaries or tuple(map(int,summaries[-1]))!=(len(expected),0) or any(int(f) for _,f in summaries):raise ValueError('Exact group count and zero failures required')
 if not isinstance(document,dict) or not isinstance(document.get('testNodes'),list):raise ValueError('Unknown or partial xcresult tree')
 found={}
 def walk(nodes):
  for node in nodes:
   if not isinstance(node,dict):raise ValueError('Malformed xcresult node')
   if node.get('nodeType')=='Test Case':
    identity=node.get('nodeIdentifier')
    if not isinstance(identity,str):raise ValueError('Missing native test identity')
    identity=identity.removesuffix('()')
    if identity in found:raise ValueError('Repeated native test identity')
    found[identity]=node.get('result')
   children=node.get('children',[])
   if not isinstance(children,list):raise ValueError('Malformed xcresult children')
   walk(children)
 walk(document['testNodes'])
 if set(found)!=set(expected) or any(v!='Passed' for v in found.values()):raise ValueError('Exact unique named native passes required')
 return sorted(found)
def main():
 p=argparse.ArgumentParser();p.add_argument('--group',choices=GROUPS,required=True);p.add_argument('--log',type=Path,required=True);p.add_argument('--bundle',type=Path,required=True);p.add_argument('--exit-code',type=int,required=True)
 a=p.parse_args()
 if a.exit_code!=0:raise ValueError('Nonzero xcodebuild/termination exit remains red')
 if not a.bundle.is_dir():raise ValueError('Missing xcresult bundle')
 result=subprocess.run(['xcrun','xcresulttool','get','test-results','tests','--path',str(a.bundle)],capture_output=True,text=True,timeout=60)
 Path(str(a.log)+'.xcresult.json').write_text(result.stdout);Path(str(a.log)+'.xcresult-errors.txt').write_text(result.stderr)
 if result.returncode:raise ValueError('xcresulttool failed')
 names=validate(a.log.read_text(errors='replace'),a.group,json.loads(result.stdout),a.exit_code)
 Path(str(a.log)+'.verified.json').write_text(json.dumps({'group':a.group,'cases':names,'count':len(names),'xcodebuild_rc':a.exit_code},indent=2)+'\n')
 for name in names:print('VERIFIED NATIVE PASS '+name)
if __name__=='__main__':
 try:main()
 except (ValueError,OSError,subprocess.TimeoutExpired) as error:raise SystemExit('Dogfood group remains RED: '+str(error))
