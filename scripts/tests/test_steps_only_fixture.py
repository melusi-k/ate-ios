from pathlib import Path
import unittest,json,hashlib
from steps_only_fixture_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class StepsOnlyFixtureCorrection(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        for path,c in json.loads((ROOT/'scripts/tests/steps_only_fixture_inverse.json').read_text()).items():
            s=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,changed)
