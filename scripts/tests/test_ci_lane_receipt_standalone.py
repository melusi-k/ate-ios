"""Standalone receipt helper rejects wrong/malformed sources and writes provenance only."""
from pathlib import Path
import importlib.util,json,os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('receipt_standalone',ROOT/'scripts/ci-lane-receipt.py')
receipt=importlib.util.module_from_spec(spec);spec.loader.exec_module(receipt)
class ReceiptTests(unittest.TestCase):
 def test_exact_sha_required(self):
  self.assertEqual(receipt.verify_source('a'*40,'a'*40),'a'*40)
  for expected,actual in [(None,'a'*40),('a'*39,'a'*39),('A'*40,'A'*40),('a'*40,'b'*40),('a'*40,None)]:
   with self.assertRaises(ValueError):receipt.verify_source(expected,actual)
 def test_cli_verifies_real_checkout_and_never_accepts_wrong_source(self):
  with tempfile.TemporaryDirectory() as d:
   r=Path(d);subprocess.run(['git','init','-q',d],check=True)
   (r/'sample').write_text('source\n')
   subprocess.run(['git','-C',d,'add','.'],check=True)
   subprocess.run(['git','-C',d,'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture'],check=True)
   sha=subprocess.check_output(['git','-C',d,'rev-parse','HEAD'],text=True).strip()
   cmd=['python3',str(ROOT/'scripts/ci-lane-receipt.py')]
   good=subprocess.run(cmd+['write','--expected',sha,'--lane','qa-critical-flows','--path','receipt.json'],cwd=d,text=True,capture_output=True,env=dict(os.environ,GITHUB_RUN_ID='17',GITHUB_RUN_ATTEMPT='1'))
   self.assertEqual(good.returncode,0,good.stderr)
   record=json.loads((r/'receipt.json').read_text())
   self.assertEqual(record['source_sha'],sha);self.assertEqual(record['run_id'],'17');self.assertEqual(record['run_attempt'],'1');self.assertEqual(record['lane'],'qa-critical-flows')
   self.assertEqual(record['source_tree'],subprocess.check_output(['git','-C',d,'rev-parse','HEAD^{tree}'],text=True).strip())
   self.assertNotIn('passed',record);self.assertNotIn('result',record)
   for args in [['verify','--expected','a'*40],['write','--expected',sha,'--lane','invalid/lane','--path','wrong.json'],['write','--expected',sha,'--lane','qa-critical-flows']]:
    bad=subprocess.run(cmd+args,cwd=d,text=True,capture_output=True);self.assertNotEqual(bad.returncode,0)
   self.assertFalse((r/'wrong.json').exists())
if __name__=='__main__':unittest.main()
