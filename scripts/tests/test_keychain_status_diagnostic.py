"""Real Security operations remain in place; static checks do not prove runtime status."""
import hashlib,json,unittest
from pathlib import Path
from keychain_status_delta import restore,FIXTURE,DIGEST,is_added,ADDITIONS,ADDITIONS_DIGEST
ROOT=Path(__file__).resolve().parents[2]

class KeychainStatusContracts(unittest.TestCase):
    def test_exact_source_inverse_and_addition_identity(self):
        self.assertEqual(hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),DIGEST)
        for key,spec in json.loads(FIXTURE.read_bytes()).items():
            source=(ROOT/key.split(':',1)[1]).read_text()
            self.assertEqual(hashlib.sha256(restore(key,source).encode()).hexdigest(),spec['base'])
            for mutated in (source+'// mutation\n',source.replace('KeychainStatusDiagnostic','Changed',1)):
                with self.assertRaises(AssertionError):restore(key,mutated)
        self.assertEqual(hashlib.sha256(ADDITIONS.read_bytes()).hexdigest(),ADDITIONS_DIGEST)
        for path in json.loads(ADDITIONS.read_bytes()):
            self.assertTrue(is_added(path,(ROOT/path).read_bytes()))
            with self.assertRaises(AssertionError):is_added(path,(ROOT/path).read_bytes()+b'// mutation')

    def test_real_call_once_and_unchanged_fail_closed_branches(self):
        source=(ROOT/'Ate/Services/Auth.swift').read_text()
        for operation,call in [('update','SecItemUpdate(query as CFDictionary, values as CFDictionary)'),
                               ('add','SecItemAdd(query as CFDictionary, nil)'),
                               ('delete','SecItemDelete(query as CFDictionary)'),
                               ('read','SecItemCopyMatching(q as CFDictionary, &out)')]:
            self.assertEqual(source.count('capture(.'+operation+') { '+call+' }'),1)
        diagnostic=(ROOT/'Ate/Services/KeychainStatusDiagnostic.swift').read_text()
        self.assertEqual(diagnostic.count('let status = work()'),1)
        self.assertIn('return status',diagnostic)
        self.assertIn('static let maximumEntries = 24',diagnostic)
        for forbidden in ['UserDefaults','URLSession','accessToken','email','kSecValueData','SecItem','Task','retry']:
            self.assertNotIn(forbidden,diagnostic)
        sheet=(ROOT/'Ate/Views/AuthSheet.swift').read_text()
        self.assertIn('error == AppStore.sessionWriteFailureMessage',sheet)
        tests=(ROOT/'AteTests/KeychainStatusDiagnosticTests.swift').read_text()
        self.assertIn('errSecMissingEntitlement',tests)
        self.assertIn('testKeepsOperationSequenceBoundedAndProcessLocal',tests)
