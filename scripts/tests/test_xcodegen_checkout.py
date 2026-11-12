"""Every XcodeGen job must retain history for strict build-focus ancestry."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class XcodeGenCheckoutTests(unittest.TestCase):
    def test_every_xcodegen_job_has_explicit_full_history(self):
        checked = 0
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            text = path.read_text()
            if '\njobs:\n' not in text:
                continue
            jobs = text.split('\njobs:\n', 1)[1]
            sections = list(re.finditer(r'^  ([\w-]+):\n', jobs, re.M))
            for index, match in enumerate(sections):
                block = jobs[match.end():sections[index + 1].start() if index + 1 < len(sections) else len(jobs)]
                # Covers the repository's direct xcodegen calls and install+generate steps.
                if not re.search(r'\bxcodegen\b', block, re.I):
                    continue
                checked += 1
                checkout = re.search(r'^\s+(?:- )?uses: actions/checkout@[^\n]+\n(.*?)(?=^      - |\Z)', block, re.M | re.S)
                self.assertIsNotNone(checkout, (path.name, match[1]))
                self.assertRegex(checkout[1], r'(?m)^          fetch-depth: 0\s*$')
        # Added manual Duo exploration, with its own full-history checkout.
        self.assertEqual(checked, 25, 'Update this reviewed caller inventory if an XcodeGen job is added or removed')

    def test_pre_generation_keeps_strict_source_validation(self):
        helper = (ROOT / 'scripts/build-focus.py').read_text()
        self.assertIn('"merge-base", "--is-ancestor", anchor, source', helper)
        self.assertIn('check=True', helper)
        self.assertIn('git("rev-parse", source + ":" + path) != blob', helper)
        self.assertNotIn('--unshallow', helper)
        self.assertNotIn('fetch', helper)


if __name__ == '__main__':
    unittest.main()
