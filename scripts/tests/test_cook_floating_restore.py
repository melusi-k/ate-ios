"""Source contracts only. Device pixels at each detent remain the acceptance gate."""
from pathlib import Path
import hashlib,subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]

def validate_float(source):
    footer=source.split('.accessibilityIdentifier("recipe.detail.scroll")',1)[1].split('RecipeNotFoundView',1)[0]
    assert '.overlay(alignment: .bottom)' in footer
    assert '.background(' not in footer
    assert '.safeAreaInset(edge: .bottom' not in source
    assert '.padding(.bottom, editing ? 16 : 16 + 72 + footerChromeReserve)' in source
    assert '.padding(.bottom, footerChromeReserve)' in footer
    assert 'if !editing, store.recipe(recipeID) != nil' in footer

class CookFloatingRestoreTests(unittest.TestCase):
    def test_shared_detail_float_clearance_and_editing_gate(self):
        validate_float((ROOT/'Ate/Views/RecipeDetailView.swift').read_text())

    def test_opaque_inset_missing_clearance_and_timer_reserve_mutants_rejected(self):
        source=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        for old,new in [('.overlay(alignment: .bottom)', '.safeAreaInset(edge: .bottom, spacing: 0)'),
                        ('.frame(maxWidth: .infinity)\n                    }', '.frame(maxWidth: .infinity)\n                            .background(Theme.background)\n                    }'),
                        ('editing ? 16 : 16 + 72 + footerChromeReserve', '16'),
                        ('.padding(.bottom, footerChromeReserve)', '.padding(.bottom, 0)')]:
            self.assertIn(old,source)
            with self.assertRaises(AssertionError):validate_float(source.replace(old,new,1))

    def test_cook_action_and_native_acceptance_unchanged(self):
        s=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        self.assertEqual(s.count('store.beginCookSession(recipeID: recipeID, factor: factor)'),1)
        self.assertEqual(s.count('store.cookTarget = CookTarget(id: recipeID)'),1)
        self.assertIn('.buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.vertical, 8)',s)
        for path,expected in NATIVE_HASHES.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),expected)

NATIVE_HASHES={'AteUITests/KeyFlowsQATests.swift': 'c07bdfa3a5a831f9fac67e546a6ab6607e73f141f7f6793cd8d1d6c6bb69d629', 'AteUITests/CoverageUITests.swift': '4aa3c2cc1c494994b13e3f3e8bb36a1067b744847c0b694034425b0f0b179cf8'}
