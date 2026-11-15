"""Packaging regression only. Generated app-bundle and native UI proof still required.

XcodeGen source folders preserve resource paths:
https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html#sources
"""
from copy import deepcopy
from pathlib import Path
import hashlib,unittest,yaml
ROOT=Path(__file__).resolve().parents[2]
BASELINE={'Ate/Logic/ProductUpdates.swift': '181fbb33d0fb54cefe70653a41fadebf071a98792cbc8a9d14f9a95f29c455ea', 'Ate/Logic/ProductUpdatesSeenStore.swift': '36c1abc34364defd64c671bd68fd7ada0705b4ab8136f8c6e4d273b90e2d048e', 'Ate/Views/ProductUpdatesLaunchHost.swift': 'e168cdd19ad7220cdea0632123e26bfd60ef613166cc9394a1307d11b1fefd43', 'Ate/Views/ProductUpdatesViews.swift': 'b839618892148326636471c779c51e2ed138b2ec0a48124540665465fa0771b1', 'Ate/Resources/ProductUpdates/catalog.json': '7c08b52b7e01545855aac627ceea92ac2f9a70627e1c1167e4667cd792811bc3', 'AteTests/ProductUpdatesTests.swift': '539e94b030a97c60ad098f26850ede3c773e05e588078215634d9aa47494c238', 'AteTests/ProductUpdatesLaunchTests.swift': '812678fb8fe09b737aac16f301d44863a0d1bb183d4e8704d07ce4d170cefa7f', 'AteUITests/ProductUpdatesLaunchUITests.swift': '99a2e9e25725c0e4b21e8ae7935f8da93424a807e1a85b1c0d15153f51122df6', 'AteUITests/InsightsPresentationUITests.swift': '39fef63cb82833ced08f422a2723df719a254c6c053a0249587091a8fedb9400', '.github/workflows/product-updates-ui.yml': '01ff69cc19c7a5f0455970b768b5606bd8396108cb5bbbfa158b8588a2abc635'}

def require_catalog_folder(spec):
    target=spec['targets']['Ate']
    sources=target['sources']
    entries=[item for item in sources if isinstance(item,dict)]
    folder=[item for item in entries if item.get('path')=='Ate/Resources/ProductUpdates']
    assert len(folder)==1, 'exactly one catalog source required'
    assert folder[0].get('type')=='folder', 'catalog must preserve its subdirectory'
    assert folder[0].get('buildPhase')=='resources', 'catalog must enter Copy Bundle Resources'
    root=[item for item in entries if item.get('path')=='Ate']
    assert len(root)==1
    assert 'Resources/ProductUpdates' in root[0].get('excludes',[]), 'exclude recursive flattened duplicate'
    for item in target.get('resources',[]):
        path=item.get('path','') if isinstance(item,dict) else item
        assert path!='Ate/Resources/ProductUpdates', 'folder must be in sources, not unknown target resources key'
    return folder[0]

class ProductUpdatesResourcePackaging(unittest.TestCase):
    def test_parsed_target_source_matches_exact_loader_subdirectory(self):
        spec=yaml.safe_load((ROOT/'project.yml').read_text())
        folder=require_catalog_folder(spec)
        self.assertTrue((ROOT/folder['path']/'catalog.json').is_file())
        loader=(ROOT/'Ate/Logic/ProductUpdates.swift').read_text()
        self.assertIn('forResource: "catalog", withExtension: "json", subdirectory: "ProductUpdates"',loader)
    def test_wrong_namespace_missing_exclusion_type_phase_and_duplicate_mutants_rejected(self):
        spec=yaml.safe_load((ROOT/'project.yml').read_text())
        for mutation in ['namespace','exclusion','relative-exclusion','type','phase','duplicate','flatten']:
            with self.subTest(mutation=mutation):
                changed=deepcopy(spec);target=changed['targets']['Ate'];entries=target['sources']
                folder=next(item for item in entries if item.get('path')=='Ate/Resources/ProductUpdates')
                root=next(item for item in entries if item.get('path')=='Ate')
                if mutation=='namespace':entries.remove(folder);target['resources'].append(folder)
                elif mutation=='exclusion':root.pop('excludes')
                elif mutation=='relative-exclusion':root['excludes']=['Ate/Resources/ProductUpdates']
                elif mutation=='type':folder['type']='group'
                elif mutation=='phase':folder['buildPhase']='none'
                elif mutation=='duplicate':entries.append(deepcopy(folder))
                elif mutation=='flatten':entries.remove(folder)
                with self.assertRaises(AssertionError):require_catalog_folder(changed)
    def test_runtime_catalog_all_native_assertions_and_lane_budgets_unchanged_from_9098bb2d(self):
        for file,digest in BASELINE.items():
            self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),digest,file)
