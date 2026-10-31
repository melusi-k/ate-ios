import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
SCRIPT = Path(__file__).resolve().parents[1] / "validate-stacked-pr.py"

def run(body, base_ref="stack/issue-179/01-foundation"):
    event={"pull_request":{"number":22,"body":body,"base":{"ref":base_ref,"repo":{"full_name":"melusi-k/ate-ios"}}}}
    with tempfile.NamedTemporaryFile("w",encoding="utf-8",delete=False) as handle:
        json.dump(event,handle); path=handle.name
    try:
        env=dict(os.environ,GITHUB_EVENT_PATH=path); env.pop("GITHUB_TOKEN",None)
        return subprocess.run([sys.executable,str(SCRIPT)],env=env,text=True,capture_output=True)
    finally: os.unlink(path)

class StackMetadataTests(unittest.TestCase):
    def test_standalone_is_valid_without_api_token(self):
        r=run("## Stack\n- **Stack ID:** None\n- **Parent PR:** None\n- **Position:** None\n")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
    def test_stack_root_is_valid_on_main(self):
        r=run("## Stack\\n- **Stack ID:** issue-179\\n- **Parent PR:** None\\n- **Position:** 1/2\\n", base_ref="main")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
    def test_stack_root_must_be_first_and_target_main(self):
        wrong_position=run("## Stack\\n- **Stack ID:** issue-179\\n- **Parent PR:** None\\n- **Position:** 2/2\\n", base_ref="main")
        wrong_base=run("## Stack\\n- **Stack ID:** issue-179\\n- **Parent PR:** None\\n- **Position:** 1/2\\n")
        self.assertNotEqual(wrong_position.returncode,0)
        self.assertNotEqual(wrong_base.returncode,0)
    def test_missing_stack_section_fails(self):
        r=run("## Summary\nchange")
        self.assertNotEqual(r.returncode,0); self.assertIn("## Stack",r.stdout)
    def test_partial_metadata_fails(self):
        r=run("## Stack\n- **Stack ID:** issue-179\n- **Parent PR:** None\n- **Position:** None\n")
        self.assertNotEqual(r.returncode,0)
    def test_invalid_position_fails_before_api_call(self):
        r=run("## Stack\n- **Stack ID:** issue-179\n- **Parent PR:** 10\n- **Position:** 1/3\n")
        self.assertNotEqual(r.returncode,0); self.assertIn("at least 2",r.stdout)

if __name__ == "__main__": unittest.main()
