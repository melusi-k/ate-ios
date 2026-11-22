"""Guard the snapshot-only query correction, not native qualification."""
from pathlib import Path
import hashlib
import re
import unittest
import yaml
from journal_delete_snapshot_delta import contract, restore
ROOT = Path(__file__).resolve().parents[2]

class JournalDeleteSnapshotTests(unittest.TestCase):
    def test_exact_inverse_and_all_historical_pins(self):
        for path, entry in contract()['files'].items():
            source = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), entry['current_sha256'])
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), entry['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            self.assertEqual(restore(path, source.encode()), old.encode())
            for mutant in [source + '// unrelated', source[:-1]]:
                with self.assertRaises(AssertionError): restore(path, mutant)
        for path, digest in contract()['protected_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)

    def test_every_journey_and_assertion_stays_byte_identical(self):
        path = 'AteUITests/JournalOpenStateUITests.swift'
        current = (ROOT / path).read_text(); old = restore(path, current)
        start = '    private func uniqueDeleteAlertAction'; end = '    private func any('
        split = lambda s: (s.split(start, 1)[0], s.split(end, 1)[1])
        self.assertEqual(split(current), split(old))
        assertions = lambda s: [line for line in s.splitlines() if 'XCTAssert' in line or 'throw NSError' in line]
        self.assertEqual(assertions(current), assertions(old))
        helper = current.split(start, 1)[1].split(end, 1)[0]
        self.assertIn('let snapshot = try candidate.snapshot()', helper)
        self.assertIn('JournalDeleteSnapshotWalk.descendants(', helper)
        self.assertIn('let nested = descendants.filter { $0.identifier == identifier }', helper)
        self.assertNotIn('candidate.descendants(', helper)
        self.assertNotIn('.firstMatch', helper)
        self.assertIn('let action = leaves[0]', helper)
        self.assertIn('XCTAssertTrue(action.isHittable', helper)
        self.assertEqual(current.count('try uniqueDeleteAlertAction('), 8)

    def test_shared_walk_has_no_remote_queries_or_metadata_filters(self):
        source = (ROOT / 'AteUITests/JournalDeleteSnapshotWalk.swift').read_text()
        code = '\n'.join(l for l in source.splitlines() if not l.strip().startswith('///'))
        for token in ['XCUI', '.snapshot(', '.count', '.frame', '.identifier', '.label', '.isEnabled', 'Set(', 'firstMatch', 'sleep', 'try?']:
            self.assertNotIn(token, code)
        for token in ['for child in children(node)', 'if matching(child) { result.append(child) }', 'visit(child)', 'visit(root)']:
            self.assertIn(token, code)
        self.assertNotIn('result.append(root)', code)

    def test_shared_exact_helper_compiles_in_existing_native_unit_target(self):
        path = 'project.yml'; source = (ROOT / path).read_text(); parent = restore(path, source)
        spec = yaml.safe_load(source); old = yaml.safe_load(parent)
        self.assertEqual(spec['targets'].keys(), old['targets'].keys())
        added = 'AteUITests/JournalDeleteSnapshotWalk.swift'
        self.assertEqual(spec['targets']['AteTests']['sources'], old['targets']['AteTests']['sources'] + [added])
        self.assertEqual(spec['targets']['AteUITests'], old['targets']['AteUITests'])

    def test_six_native_adversarial_cases_remain_mandatory(self):
        path = 'scripts/full-unit-required.txt'; source = (ROOT / path).read_text(); parent = restore(path, source)
        required = contract()['required_native']
        self.assertEqual(source, parent + '\n'.join(required) + '\n')
        self.assertEqual(len(source.splitlines()), len(set(source.splitlines())))
        native = (ROOT / 'AteTests/JournalDeleteSnapshotWalkTests.swift').read_text()
        methods = re.findall(r'    func (test\w+)\(', native)
        self.assertEqual(['JournalDeleteSnapshotWalkTests/' + n for n in methods], required)
        self.assertEqual(len(methods), 6)
        for token in ['Same-frame siblings must still fail', 'foreign decision must still fail', 'Invalid metadata must reach the unchanged UI assertions']:
            self.assertIn(token, native)
        self.assertIn('JournalDeleteSnapshotWalk.descendants(', native)
        for required_old in contract()['files'][path]['fragments'][0]['old'].splitlines():
            self.assertIn(required_old, source.splitlines())
