"""Static source checks for the #641 Add-recipe entry; never native/device proof."""
from pathlib import Path
import hashlib,json,re,unittest
from suggest_new_recipe_entry_delta import restore
ROOT=Path(__file__).resolve().parents[2]
PATH='Ate/Views/AddRecipeSheet.swift'
REUSED_HEAD_SHAS={
 'Ate/Logic/RecipeDiscovery.swift':'232df0f236e2225c22b47572aa80557fde899db8f222339ac3ea3a60bda8cd4a',
 'Ate/Views/SuggestedNewRecipesView.swift':'fbbf748fb9bb963da0ab27bfd628b7e50296a7070ae12efd11c4d769492256f7',
 'Ate/Services/OnDeviceBackend.swift':'a81f1265e460122fc634baa776fa89e24a4b098a426d626474ea2ff1d2cbe22f'}

class SuggestNewRecipeEntryTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_or_unrelated_mutants_fail_closed(self):
  c=json.loads((ROOT/'scripts/tests/suggest_new_recipe_entry_inverse.json').read_text())[PATH]
  s=(ROOT/PATH).read_text()
  self.assertEqual(hashlib.sha256(restore(PATH,s).encode()).hexdigest(),c['parent_sha'])
  for f in c['fragments']:
   for mutant in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
    with self.assertRaises(AssertionError):restore(PATH,mutant)

 def test_entry_is_always_visible_and_only_presents_the_existing_flow(self):
  s=(ROOT/PATH).read_text()
  self.assertIn('Button { showDiscovery = true }',s)
  self.assertEqual(s.count('showDiscovery = true'),1)
  self.assertIn('Label("Suggest a new recipe", systemImage: "sparkles")',s)
  self.assertIn('.accessibilityIdentifier("suggestNewRecipe")',s)
  self.assertNotIn('.disabled(',s.split('Button { showDiscovery = true }',1)[1].split('if let why',1)[0])
  self.assertIn('.sheet(isPresented: $showDiscovery) {\n            NavigationStack { SuggestedNewRecipesView().environment(store) }\n        }',s)
  # Viewing Add recipe alone starts nothing: the only .task keeps its prior work.
  task=s.split('.task {',1)[1].split('        }',1)[0]
  self.assertNotIn('showDiscovery',task)
  self.assertNotIn('suggestRecipe',task)
  # The state explanation sits beside the entry and stays visible when blocked.
  self.assertIn('if let why = discoveryReadiness.explanation {',s)
  self.assertIn('.accessibilityIdentifier("suggestNewRecipe.unavailable")',s)
  self.assertIn('private var discoveryReadiness: RecipeDiscoveryReadiness {',s)
  for token in ['store.settings.onDeviceOnly','store.backend is OnDeviceBackend','OnDeviceBackend.isModelAvailable','OnDeviceBackend.availabilityNote','store.recipes.count']:
   self.assertIn(token,s)

 def test_readiness_logic_is_presentation_only_and_matches_session_messages(self):
  s=(ROOT/'Ate/Logic/RecipeDiscoveryReadiness.swift').read_text()
  for token in ['case ready','case privateMode','case modelUnavailable(reason: String)','case nonOnDeviceBackend','case emptyLibrary',
                'var canGenerate: Bool','Private mode is on. Turn it off in Settings to use AI suggestions.',
                'Save a recipe first so Ate can suggest something based on your tastes.']:
   self.assertIn(token,s)
  for token in ['LanguageModelSession','SystemLanguageModel','URLSession','http','MockBackend','Demo','store.add(','DraftStore']:
   self.assertNotIn(token,s)
  # Gate order: Private mode, then backend/model, then the saved-recipe minimum.
  init_body=s.split('init(privateMode: Bool',1)[1].split('var canGenerate',1)[0]
  self.assertLess(init_body.index('.privateMode'),init_body.index('.nonOnDeviceBackend'))
  self.assertLess(init_body.index('.nonOnDeviceBackend'),init_body.index('.modelUnavailable'))
  self.assertLess(init_body.index('.modelUnavailable'),init_body.index('.emptyLibrary'))

 def test_existing_generation_flow_is_reused_not_forked(self):
  for path,sha in REUSED_HEAD_SHAS.items():
   self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),sha,path+' changed; reuse the existing flow')
  s=(ROOT/PATH).read_text()
  self.assertNotIn('suggestRecipe(',s)
  self.assertNotIn('RecipeDiscoverySession(',s)

 def test_import_choices_draft_recovery_cancellation_and_account_guards_stay(self):
  s=(ROOT/PATH).read_text()
  for token in ['case link = "Link", image = "Image", prompt = "Prompt"','restoreInterrupted()','DraftStore.shared.begin(mode: mode.rawValue',
                'interactiveDismissDisabled(hasUnsaved)','Discard this recipe?','store.insightLifecycleAccountID','invalidateGeneration()']:
   self.assertIn(token,s)

 def test_native_cases_exist_and_are_registered_exactly_once(self):
  tests=(ROOT/'AteTests/RecipeDiscoveryReadinessTests.swift').read_text()
  ledger=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
  names=re.findall(r'    func (test\w+)\(',tests)
  self.assertGreaterEqual(len(names),6)
  for name in names:
   self.assertEqual(ledger.count('RecipeDiscoveryReadinessTests/'+name),1,name)
