from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class PiWorkflowConfigurationTests(unittest.TestCase):
    def test_eight_sources_explicit_engines_remain_off_and_detect(self):
        paths = list((ROOT/'.github/workflows').glob('aw-*.md'))
        self.assertEqual(len(paths),8)
        for p in paths:
            text=p.read_text()
            self.assertIn('if: "false"',text)
            self.assertIn('  staged: true',text)
            self.assertIn('  copilot-requests: none',text)
            self.assertIn('engine:\n  id: pi\n  model: google/',text)
            self.assertIn('  threat-detection:\n    engine:\n      id: pi\n      model: google/',text)
            self.assertEqual(text.count('GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}'),2)
            self.assertNotIn('threat-detection: false',text)
            lock=p.with_suffix('.lock.yml').read_text()
            meta=json.loads(lock.splitlines()[0].split(': ',1)[1])
            self.assertEqual(meta['agent_id'],'pi')
            self.assertEqual(meta['detection_agent_id'],'pi')
            # Record compiler limitation honestly, not as readiness acceptance.
            self.assertIn('threat-detect --engine copilot',lock)
            self.assertIn('GH_AW_LLM_PROVIDER=google',lock)
            self.assertIn('Validate GEMINI_API_KEY secret',lock)
