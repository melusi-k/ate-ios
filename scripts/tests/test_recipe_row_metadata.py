"""Source preflight only. SwiftUI geometry and screenshots require native XCTest."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
NATIVE_TESTS = [
    'testMetadataItemsStaySingleLineAtNarrowWidths',
    'testLayoutMovesWholeItemsAndCapsOversizedTagsWithoutOverlap',
    'testRenderedOwnerShapedRowsRetainCompactMetadataAndScreenshots',
]


class RecipeRowMetadataSourceTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'Ate/Views/Components.swift').read_text()

    def test_shared_row_uses_whole_item_layout_and_two_line_title(self):
        row = self.source.split('struct RecipeRowView: View {', 1)[1].split('struct PressScale:', 1)[0]
        self.assertIn('RecipeRowMetadata(recipe: recipe)', row)
        self.assertNotIn('HStack(spacing: 10)', row)
        self.assertIn('Text(recipe.title).font(AteFont.body(18, .semibold)).lineLimit(2)', row)
        self.assertIn('.frame(maxWidth: .infinity, alignment: .leading)', row)
        explore = (ROOT / 'Ate/Views/ExploreView.swift').read_text()
        self.assertIn('RecipeRowView(recipe: recipe)', explore)

    def test_metadata_item_has_a_single_line_contract_without_horizontal_fixed_size(self):
        item = self.source.split('struct RecipeRowMetadataItem: View {', 1)[1].split('struct RecipeRowMetadata:', 1)[0]
        for fragment in ['Label(text, systemImage: symbol)', 'TagBadge(text: text)', '.lineLimit(1)',
                         '.truncationMode(.tail)', '.fixedSize(horizontal: false, vertical: true)']:
            self.assertIn(fragment, item)
        self.assertNotIn('horizontal: true', item)
        self.assertNotIn('minimumScaleFactor', item)

    def test_layout_caps_proposals_and_uses_same_frames_for_measurement_and_placement(self):
        layout = self.source.split('struct RecipeRowMetadataLayout: Layout {', 1)[1].split('struct RecipeRowMetadataItem:', 1)[0]
        for fragment in ['proposed.isFinite', 'Self.availableWidth(proposed: proposal.width, ideal: ideal)', 'min(ideal.width, width)', 'if x > 0, x + itemWidth > width',
                         'y += rowHeight + spacing', 'height: size.height',
                         'frames(width: width, subviews: subviews)',
                         'frames(width: bounds.width, subviews: subviews)',
                         'anchor: .topLeading, proposal: ProposedViewSize(frame.size)']:
            self.assertIn(fragment, layout)

    def test_native_geometry_cases_are_required_and_keep_visual_evidence(self):
        native = (ROOT / 'AteTests/RecipeRowMetadataTests.swift').read_text()
        required = (ROOT / 'scripts/full-unit-required.txt').read_text().splitlines()
        for name in NATIVE_TESTS:
            self.assertIn('func ' + name + '(', native)
            self.assertIn('RecipeRowMetadataTests/' + name, required)
        for fragment in ['"45 min"', '"115 min"', '"side dish"', '"south african"',
                         'UIHostingController', 'constrained.height, ideal.height + 0.5',
                         'frame.intersects(earlier)', 'ImageRenderer(content: RecipeRowView(recipe: recipe)',
                         'attachment.lifetime = .keepAlways']:
            self.assertIn(fragment, native)
