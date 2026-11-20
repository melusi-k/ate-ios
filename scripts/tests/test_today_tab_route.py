"""Static source checks for the #642 Today tab slice; never native/device proof."""
from pathlib import Path
import hashlib,json,re,unittest
from today_tab_route_delta import restore
ROOT=Path(__file__).resolve().parents[2]
PATH='Ate/Models/Models.swift'
REUSED_HEAD_SHAS={
 'Ate/Logic/RecipeDiscovery.swift':'232df0f236e2225c22b47572aa80557fde899db8f222339ac3ea3a60bda8cd4a',
 'Ate/Views/SuggestedNewRecipesView.swift':'747f223ce47b18ac9d7dec344ac2e58b2253d26606e8004d382670aad3385f52',
 'Ate/Services/OnDeviceBackend.swift':'a81f1265e460122fc634baa776fa89e24a4b098a426d626474ea2ff1d2cbe22f',
 'Ate/Logic/RecipeDiscoveryReadiness.swift':'372eabddc8edc5758ee4e0b0e457fd3d5a18d512e2c5f5d52199deb47983cbb4'}

class TodayTabRouteTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_or_unrelated_mutants_fail_closed(self):
  c=json.loads((ROOT/'scripts/tests/today_tab_route_inverse.json').read_text())[PATH]
  s=(ROOT/PATH).read_text()
  self.assertEqual(hashlib.sha256(restore(PATH,s).encode()).hexdigest(),c['parent_sha'])
  for f in c['fragments']:
   for mutant in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
    with self.assertRaises(AssertionError):restore(PATH,mutant)

 def test_route_case_and_mapping_keep_collection_on_the_home_stack(self):
  model=(ROOT/PATH).read_text()
  self.assertIn('    /// The full saved-recipe collection pushed inside the Today stack (#642).\n    case library\n',model)
  app=(ROOT/'Ate/App/AteApp.swift').read_text()
  self.assertIn('case .library: LibraryView(searchPlacement: TabChrome.usesAccessory ? .none : .drawer)',app)
  store=(ROOT/'Ate/Store/AppStore.swift').read_text()
  self.assertIn('if t == .library { tab = t }',store)
  self.assertIn('case .library: filter.collection = nil; tab = t',store)
  self.assertIn('case .collection(let c): filter.collection = c; tab = t; openCollection()',store)
  self.assertIn('case .library: filter.collection = nil; tab = t; openCollection()',store)
  self.assertIn('func openCollection()',store)
  self.assertIn('path = TodayHome.canonicalCollectionPath()',store)
  self.assertNotIn('path.append(.library)',store)
  self.assertIn('var isAtCollectionRoot: Bool',store)
  self.assertIn('TodayHome.isCollectionRoot(isHomeTab: isHomeTab, path: path)',store)
  self.assertIn('var homeSheetOwner: HomeSheetOwner',store)
  self.assertIn('TodayHome.sheetOwner(isHomeTab: isHomeTab, path: path)',store)
  # The system search intent lands on the collection, which adopts the query; it
  # can no longer clear the stack underneath Today.
  search=store.split('    func search(_ term: String) {',1)[1].split('    }',1)[0]
  self.assertIn('select(.library)',search)
  self.assertNotIn('path = []',search)

 def test_today_is_the_home_root_and_collection_keeps_its_accessory(self):
  app=(ROOT/'Ate/App/AteApp.swift').read_text()
  self.assertEqual(app.count('TodayView().offlineStrip()'),3)
  self.assertNotIn('LibraryView().offlineStrip()',app)
  self.assertNotIn('LibraryView(searchPlacement: .none).offlineStrip()',app)
  self.assertIn('let showBottomAccessory = store.cookTarget == nil && (store.isAtTabRoot || store.isAtCollectionRoot)',app)
  self.assertIn('!(TabChrome.usesAccessory && (store.isAtTabRoot || store.isAtCollectionRoot))',app)
  # The store-wide add/import sheets have exactly one owner on each side.
  today=(ROOT/'Ate/Views/TodayView.swift').read_text()
  self.assertEqual(today.count('store.homeSheetOwner == .today ?'),2)
  self.assertNotIn('store.path.isEmpty ? store.quickAdd',today)
  self.assertNotIn('store.path.isEmpty ? store.pendingImport',today)
  library=(ROOT/'Ate/Views/LibraryView.swift').read_text()
  self.assertEqual(library.count('global && store.homeSheetOwner == .collection ?'),2)

 def test_today_view_is_presentation_only_and_reuses_the_existing_flow(self):
  s=(ROOT/'Ate/Views/TodayView.swift').read_text()
  for path,sha in REUSED_HEAD_SHAS.items():
   self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),sha,path+' changed; reuse the existing flow')
  for token in ['.accessibilityIdentifier("today.recipes")','.accessibilityIdentifier("today.browseRecipes")',
                '.accessibilityIdentifier("today.suggestNewRecipe")','.accessibilityIdentifier("today.suggestNewRecipe.unavailable")',
                'store.openCollection()','TodayHome.preview(store.recipes)','SuggestedNewRecipesView().environment(store)',
                'private var discoveryReadiness: RecipeDiscoveryReadiness {']:
   self.assertIn(token,s)
  # Presenting only: no generation, demo content, or second pipeline starts here.
  for token in ['suggestRecipe(','RecipeDiscoverySession(','LanguageModelSession','MockBackend','Continue cooking','On the menu','After cooking','Shopping list']:
   self.assertNotIn(token,s)
  self.assertEqual(s.count('showDiscovery = true'),1)

 def test_native_cases_exist_and_are_registered_exactly_once(self):
  ledger=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
  total=0
  for suite in ['TodayHomeTests','TodayNavigationTests']:
   tests=(ROOT/f'AteTests/{suite}.swift').read_text()
   names=re.findall(r'    func (test\w+)\(',tests)
   self.assertGreaterEqual(len(names),3,suite)
   total+=len(names)
   for name in names:
    self.assertEqual(ledger.count(suite+'/'+name),1,suite+'/'+name)
  self.assertGreaterEqual(total,7)
