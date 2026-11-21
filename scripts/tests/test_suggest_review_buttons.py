from suggest_review_buttons_delta import restore
from recipe_streaming_delta import restore as next_layer
"""Exact #646 suggested-review button-styling inverse and style contract. Not native proof."""
from pathlib import Path
import hashlib,json,unittest
ROOT=Path(__file__).resolve().parents[2]
PATH='Ate/Views/SuggestedNewRecipesView.swift'

class SuggestReviewButtonsTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_or_unrelated_mutants_fail_closed(self):
  c=json.loads((ROOT/'scripts/tests/suggest_review_buttons_inverse.json').read_text())[PATH]
  s=(ROOT/PATH).read_text()
  self.assertEqual(hashlib.sha256(restore(PATH,s).encode()).hexdigest(),c['parent_sha'])
  # The delta is marker-guarded so older historical states pass through, so the
  # missing-fragment mutant is caught by the next layer down, not by this one.
  chained=lambda t: next_layer(PATH,restore(PATH,t))
  for f in c['fragments']:
   for mutant in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
    with self.assertRaises(AssertionError):chained(mutant)

 def test_actions_match_the_reference_review_sheet_styles(self):
  s=(ROOT/PATH).read_text()
  ref=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
  # The reference import review sheet styles the same three actions this way.
  for token in ['.ate(.primary, full: true)','.ate(.secondary)','.ate(.ghost)']:
   self.assertIn(token,ref)
  # One aligned row: Save primary full width, Edit secondary, Rerun ghost, in
  # the reference order; Rerun is aligned with the other two, not off to the side.
  row=s.split('HStack(spacing: 8) {',1)[1].split('                        }',1)[0]
  self.assertLess(row.index('Button(session.savedIDs.contains(card.id) ? "Saved" : "Save")'),row.index('Button(editing ? "Preview" : "Edit")'))
  self.assertLess(row.index('Button(editing ? "Preview" : "Edit")'),row.index('Button("Rerun")'))
  self.assertIn('.buttonStyle(.ate(.primary, full: true))',row)
  self.assertIn('.buttonStyle(.ate(.secondary))',row)
  self.assertIn('.buttonStyle(.ate(.ghost))',row)
  # Behaviour unchanged: same actions, labels, disabled logic and identifiers,
  # and the validation messages are untouched.
  for token in ['save(review ?? card)','rerun(review ?? card)','editing.toggle()',
                '.disabled(session.loading || session.savedIDs.contains(card.id))',
                '.accessibilityIdentifier("discovery.rerun")',
                'Check this draft and fill in anything missing before saving.']:
   self.assertIn(token,s)
  self.assertNotIn('Button(editing ? "Preview" : "Edit") { editing.toggle() }.disabled(session.loading)\n',s)
