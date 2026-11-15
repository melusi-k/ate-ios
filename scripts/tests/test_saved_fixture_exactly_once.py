from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
ORDER=['ExploreRetentionQAFixtures', 'CookJournalQARoute', 'IngredientDisplayQAFixtures', 'DogfoodSavedRecipeQAFixtures', 'RecipeSheetQAFixtures', 'FocusedJourneyQAFixtures']

def validate_saved_fixture_once(source):
    assert source.count('DogfoodSavedRecipeQAFixtures.prepare(st)')==1
    positions=[]
    for name in ORDER:
        call=name+'.prepare(st)'
        assert source.count(call)==1, call
        positions.append(source.index(call))
    assert positions==sorted(positions), 'fixture setup order changed'

class SavedFixtureExactlyOnceTests(unittest.TestCase):
    def test_one_setup_at_original_source_sequence_point(self):
        validate_saved_fixture_once((ROOT/'Ate/App/AteApp.swift').read_text())
    def test_duplicate_setup_mutant_is_rejected(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text()
        original='        ExploreRetentionQAFixtures.prepare(st)'
        assert source.count(original)==1
        mutant=source.replace(original,'        DogfoodSavedRecipeQAFixtures.prepare(st)\n'+original,1)
        with self.assertRaises(AssertionError):
            validate_saved_fixture_once(mutant)
    def test_reordered_setup_mutant_is_rejected(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text()
        a,b=[name+'.prepare(st)' for name in ORDER[:2]]
        mutant=source.replace(a,'SWAP_FIXTURE',1).replace(b,a,1).replace('SWAP_FIXTURE',b,1)
        with self.assertRaises(AssertionError):
            validate_saved_fixture_once(mutant)
