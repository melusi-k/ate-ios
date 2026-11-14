from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class RecipeGenerationToolContracts(unittest.TestCase):
    def test_default_off_scoped_gate_and_request_isolation(self):
        logic = (ROOT / 'Ate/Logic/RecipeStructureValidation.swift').read_text()
        gate = logic.split('enum RecipeGenerationToolGate', 1)[1].split('/// Deterministic', 1)[0]
        self.assertIn('#if DEBUG', gate)
        self.assertIn('#else\n        false', gate)
        self.assertIn('input == .prompt || input == .social', gate)
        backend = (ROOT / 'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertIn('if !structureEnabled, reuseSession', backend)
        self.assertIn('else if !structureEnabled, input == .prompt', backend)
        self.assertIn('if !structureEnabled { sessions[card.id] = session }', backend)
        self.assertIn('if emitPreview { partialSink?(RecipeStreamPreview(snap.content)) }', backend)
        self.assertLess(backend.index('let res = try await stream.collect()'), backend.index('try await structureReceipt.require(signature)'))
        self.assertIn('RecipeGenerationTool.validate(ingredients: res.content.ingredients, steps: res.content.steps)', backend)
        generate = backend.split('static func generate(', 1)[1]
        self.assertLess(generate.index('try await structureReceipt.require(signature)'), generate.index('let card = res.content.card'))

    def test_tool_is_typed_validated_and_no_side_effects(self):
        source = (ROOT / 'Ate/Services/RecipeGenerationTool.swift').read_text()
        for expected in ['struct RecipeGenerationTool: Tool', '@Generable', 'var ingredients: [GenIngredient]',
                         'var steps: [GenStep]', 'func call(arguments: Arguments) async throws -> String',
                         '(1...720).contains(step.minutes!)', '(50...300).contains(step.temperatureC!)',
                         'RecipeStructureValidation.validate', 'await receipt.reject()']:
            self.assertIn(expected, source)
        for forbidden in ['UserDefaults', 'URLSession', 'store.add', 'partialSink', 'aiConfidence =']:
            self.assertNotIn(forbidden, source)
        eval_doc = (ROOT / 'docs/ai-eval.md').read_text()
        self.assertIn('| F13 |', eval_doc)
        self.assertIn('One paired BEFORE/AFTER device run for F13', eval_doc)
        self.assertIn('NOT RUN', eval_doc)

    def test_preparation_only_identity_rejected_with_measurement_unit(self):
        validation = (ROOT / 'Ate/Logic/RecipeStructureValidation.swift').read_text()
        normalization = (ROOT / 'Ate/Logic/IngredientFieldNormalization.swift').read_text()
        native = (ROOT / 'AteTests/RecipeGenerationToolTests.swift').read_text()
        self.assertIn('!IngredientFieldNormalization.isPreparationOnly(name)', validation)
        self.assertIn('!nameWords.isEmpty && nameWords.isSubset(of: preparationWords)', normalization)
        self.assertIn('testKnownPreparationOnlyNamesAreRejectedWithoutGuessingFood', native)
        self.assertIn('testTypedToolRejectsPrepOnlyNameAndPoisonsPriorReceipt', native)
        self.assertIn('for name in ["diced", "finely chopped"]', native)
        self.assertIn('try await receipt.require(accepted); XCTFail("Prep-only call must poison', native)
