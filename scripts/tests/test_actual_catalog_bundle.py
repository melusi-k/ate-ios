"""Packaging source contracts plus built-directory verifier tests, not native build evidence."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import tempfile,unittest,yaml
ROOT=Path(__file__).resolve().parents[2]

def require_contract(spec):
    target=spec['targets']['Ate'];sources=target['sources']
    folders=[s for s in sources if isinstance(s,dict) and s.get('path')=='Ate/Resources/ProductUpdates']
    assert len(folders)==1
    assert folders[0].get('type')=='folder'
    assert folders[0].get('buildPhase')=='resources'
    roots=[s for s in sources if isinstance(s,dict) and s.get('path')=='Ate']
    assert len(roots)==1 and 'Resources/ProductUpdates' in roots[0].get('excludes',[])
    assert not any((s.get('path') if isinstance(s,dict) else s)=='Ate/Resources/ProductUpdates' for s in target.get('resources',[]))

class ActualCatalogBundleContracts(unittest.TestCase):
    def test_source_spec_and_strict_loaders_match(self):
        require_contract(yaml.safe_load((ROOT/'project.yml').read_text()))
        for path in ['Ate/Logic/Roadmap.swift','Ate/Logic/ProductUpdates.swift']:
            self.assertIn('subdirectory: "ProductUpdates"',(ROOT/path).read_text())
        workflow=(ROOT/'.github/workflows/roadmap-local-qualification.yml').read_text()
        self.assertIn('verify-product-catalog-bundle.py',workflow)
        self.assertIn('-only-testing:AteTests/ProductUpdatesTests',workflow)
        self.assertIn('testActualBundledReleaseCatalogLoadsFromRequiredSubdirectory',(ROOT/'AteTests/ProductUpdatesTests.swift').read_text())
    def test_seven_packaging_mutants_are_rejected(self):
        spec=yaml.safe_load((ROOT/'project.yml').read_text())
        for mutation in ['namespace','exclusion','relative','type','phase','duplicate','flatten']:
            changed=deepcopy(spec);target=changed['targets']['Ate'];sources=target['sources']
            folder=next(s for s in sources if s.get('path')=='Ate/Resources/ProductUpdates')
            root=next(s for s in sources if s.get('path')=='Ate')
            if mutation=='namespace':sources.remove(folder);target['resources'].append(folder)
            if mutation=='exclusion':root.pop('excludes')
            if mutation=='relative':root['excludes']=['Ate/Resources/ProductUpdates']
            if mutation=='type':folder['type']='group'
            if mutation=='phase':folder['buildPhase']='none'
            if mutation=='duplicate':sources.append(deepcopy(folder))
            if mutation=='flatten':sources.remove(folder)
            with self.subTest(mutation=mutation),self.assertRaises(AssertionError):require_contract(changed)
    def test_verifier_accepts_only_exact_built_subdirectory_and_rejects_flat_missing_changed(self):
        module_spec=importlib.util.spec_from_file_location('catalog_verify',ROOT/'scripts/verify-product-catalog-bundle.py')
        module=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);app=root/'build/Ate.app';packaged=app/'ProductUpdates';packaged.mkdir(parents=True)
            source=root/'Ate/Resources/ProductUpdates';source.mkdir(parents=True)
            for name in ['roadmap.json','catalog.json']:
                (source/name).write_text('{}');(packaged/name).write_text('{}')
            settings='Build settings for action build and target Ate:\n    TARGET_BUILD_DIR = '+str(app.parent)+'\n    WRAPPER_NAME = Ate.app\n'
            self.assertEqual(len(module.verify(settings,root)['files']),2)
            (app/'roadmap.json').write_text('{}')
            with self.assertRaises(ValueError):module.verify(settings,root)
            (app/'roadmap.json').unlink();(packaged/'catalog.json').write_text('{"changed":true}')
            with self.assertRaises(ValueError):module.verify(settings,root)
            (packaged/'catalog.json').unlink()
            with self.assertRaises(ValueError):module.verify(settings,root)
