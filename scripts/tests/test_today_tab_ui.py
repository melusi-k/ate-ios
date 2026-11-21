"""Exact inverse contract for the #642 Today-tab UI route updates."""
from pathlib import Path
import hashlib,json,unittest
from nutrition_log_route_delta import restore as restore_nutrition_route
from today_tab_ui_delta import restore
ROOT=Path(__file__).resolve().parents[2]

class TodayTabUIDeltaTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_or_unrelated_mutants_fail_closed(self):
  contracts=json.loads((ROOT/'scripts/tests/today_tab_ui_inverse.json').read_text())
  for path,c in contracts.items():
   s=restore_nutrition_route(path,(ROOT/path).read_text())
   self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'],path)
   # Each fragment is mutant-tested at the stage where it is live: fragments
   # carried from an earlier layer step exist only after newer fragments are
   # reversed, so mutating the raw head text would be a no-op for them.
   stage=s
   for f in c['fragments']:
    for mutant in [stage.replace(f['new'],'',1),stage+f['new'],stage+'// unrelated\n']:
     with self.assertRaises(AssertionError,msg=path):restore(path,mutant)
    stage=stage.replace(f['new'],f['old']) if f.get('all') else stage.replace(f['new'],f['old'],1)
   self.assertEqual(hashlib.sha256(stage.encode()).hexdigest(),c['parent_sha'],path)

 def test_route_helpers_keep_bounded_waits_and_existing_destinations(self):
  for path in ['AteUITests/AteUITests.swift','AteUITests/CoverageUITests.swift']:
   s=(ROOT/path).read_text()
   self.assertIn('func openLibraryCollection()',s)
   helper=s.split('func openLibraryCollection()',1)[1].split('    }\n',1)[0]
   self.assertIn('tab("Library")',helper)
   self.assertIn('app.buttons["today.recipes"]',helper)
   self.assertNotIn('sleep(',helper)
  s=(ROOT/'AteUITests/ExploreUITests.swift').read_text()
  self.assertIn('app.navigationBars["Favourites"].waitForExistence(timeout: 10)',s)
  s=(ROOT/'AteUITests/InsightsPresentationUITests.swift').read_text()
  self.assertIn('app.navigationBars["Your Kitchen"], 10',s)

 def test_every_library_content_setup_enters_the_canonical_collection(self):
  # The full launch/setup audit (#642 v3): every UI test class whose launch or
  # setup needs Library content enters the pushed collection through the real
  # Today route ('today.recipes'). No production or QA launch bypasses Today.
  for path in ['AteUITests/ExploreUITests.swift','AteUITests/AccessibilityAuditUITests.swift',
               'AteUITests/CookPlanUITests.swift','AteUITests/CookingTrackerEntryUITests.swift',
               'AteUITests/JournalOpenStateUITests.swift','AteUITests/LibraryProteinGroupingUITests.swift',
               'AteUITests/NutritionDiaryUITests.swift']:
   s=(ROOT/path).read_text()
   self.assertIn('app.buttons["today.recipes"]',s,path)
   self.assertIn('Today routes to the saved-recipe collection',s,path)
  explore=(ROOT/'AteUITests/ExploreUITests.swift').read_text()
  setup=explore.split('override func setUp()',1)[1].split('override func tearDown()',1)[0]
  self.assertLess(setup.index('openLibraryCollection()'),setup.index('library.explore'),'Explore setUp enters the collection before asserting library content')
  a11y=(ROOT/'AteUITests/AccessibilityAuditUITests.swift').read_text()
  self.assertEqual(a11y.count('openLibraryCollection()'),8,'one helper plus the seven launch sites')
  ate=(ROOT/'AteUITests/AteUITests.swift').read_text()
  self.assertEqual(ate.count('openLibraryCollection()'),24,'one helper plus every routed site')
  coverage=(ROOT/'AteUITests/CoverageUITests.swift').read_text()
  self.assertEqual(coverage.count('openLibraryCollection()'),10,'one helper plus every routed site')
