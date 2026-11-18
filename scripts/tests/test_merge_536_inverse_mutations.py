"""Mutations must fail through the original guard methods, after approved inverses."""
from pathlib import Path
import importlib,json,unittest
from unittest.mock import patch
from approved_merge_composed import normalize
ROOT=Path(__file__).resolve().parents[2]

class Merge536InverseMutationTests(unittest.TestCase):
    def run_guard(self,module,cls,method,path,mutate):
        target=ROOT/path
        read_text,read_bytes=Path.read_text,Path.read_bytes
        original=read_text(target)
        changed=mutate(original)
        self.assertNotEqual(changed,original)
        def text(p,*a,**kw):
            return changed if p==target else read_text(p,*a,**kw)
        def binary(p,*a,**kw):
            return changed.encode() if p==target else read_bytes(p,*a,**kw)
        case=getattr(importlib.import_module(module),cls)(method)
        with patch.object(Path,'read_text',text),patch.object(Path,'read_bytes',binary):
            with self.assertRaises(AssertionError):
                getattr(case,method)()

    def test_original_assertion_swipe_allowance_operation_input_selection_mutations_fail(self):
        coverage=('test_settings_clear_band','SettingsClearBandTests','test_entire_ui_file_reconstructs_exact_d994_original','AteUITests/CoverageUITests.swift')
        account=('test_add_title_query_diagnostic','AddTitleQueryDiagnosticTests','test_all_original_tests_and_helpers_preserved','AteUITests/AteUITests.swift')
        workflow=('test_search_receipt_diagnostic','SearchReceiptTests','test_exact_original_library_and_workflow_reconstruct','.github/workflows/compile-check.yml')
        ocr=('test_ocr_cpu_capture','OCRCPUCaptureContracts','test_only_observation_changes','Ate/Services/OnDeviceBackend.swift')
        cases=[(coverage,'XCTAssertTrue(', 'XCTAssertFalse('),
               (coverage,'.swipeUp()', '.swipeDown()'),
               (coverage,'timeout:', 'changedTimeout:'),
               (account,'.tap()', '.doubleTap()'),
               (account,'.typeText(', '.changedTypeText('),
               (workflow,'-only-testing:AteTests', '-only-testing:MissingTests'),
               (ocr,'req.recognitionLevel = .accurate','req.recognitionLevel = .fast'),
               (ocr,'try handler.perform([req])','try handler.perform([])')]
        for guard,old,new in cases:
            with self.subTest(guard=guard[0],mutation=old):
                self.assertIn(old,(ROOT/guard[3]).read_text())
                self.run_guard(*guard,lambda s,o=old,n=new:s.replace(o,n,1))

    def test_removal_of_original_assertion_fails(self):
        self.run_guard('test_settings_clear_band','SettingsClearBandTests',
                       'test_entire_ui_file_reconstructs_exact_d994_original',
                       'AteUITests/CoverageUITests.swift',
                       lambda s:'\n'.join(l for i,l in enumerate(s.split('\n')) if i!=next(j for j,x in enumerate(s.split('\n')) if 'XCTAssertTrue(' in x)))

    def test_each_inverse_requires_exact_fragment_count_and_order(self):
        contracts=json.loads((ROOT/'scripts/tests/approved_merge_composed_inverses.json').read_text())['contracts']
        for key,contract in contracts.items():
            if key.startswith('account-restored:'):
                continue
            raw=(ROOT/contract['path']).read_text()
            for fragment in contract['inverse_fragments']:
                old=fragment['merged_fragment']
                with self.subTest(contract=key,fragment=old[:60]):
                    with self.assertRaises(AssertionError):
                        normalize(key,raw.replace(old,old+'// changed approved delta\n',1).replace(old,'',1))
                    with self.assertRaises(AssertionError):
                        normalize(key,raw+old)
