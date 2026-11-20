import XCTest
import SwiftUI
import UIKit
@testable import Ate

@MainActor
final class UnspecifiedServingsRowTests: XCTestCase {
    func testMetadataKeepsTextDespiteInheritedIconOnlyStyle() throws {
        for text in ["Unspecified", "4"] {
            let item = RecipeRowMetadataItem(text: text, symbol: "person.2")
            let normal = UIHostingController(rootView: item)
            let inherited = UIHostingController(rootView: item.labelStyle(.iconOnly))
            let icon = UIHostingController(rootView: Image(systemName: "person.2").font(AteFont.body(12)))
            let proposal = CGSize(width: 300, height: 100)
            let expected = normal.sizeThatFits(in: proposal)
            let actual = inherited.sizeThatFits(in: proposal)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.5)
            XCTAssertGreaterThan(actual.width, icon.sizeThatFits(in: proposal).width + 4,
                                 "Metadata must reserve width for its value, not only the icon")
        }
    }

    func testSavedSourceDraftRowWithUnspecifiedServingsRetainsNativePixels() throws {
        var recipe = RecipeCard(title: "Garlic butter chicken thighs 🍗", servings: 0, source: .imported)
        recipe.sourceDraft = .init(text: "source retained", warnings: [], unknownServings: true)
        for width in [CGFloat(326), 393] {
            let renderer = ImageRenderer(content: Button {} label: { RecipeRowView(recipe: recipe) }
                .buttonStyle(.plain).labelStyle(.iconOnly)
                .frame(width: width).environment(\.dynamicTypeSize, .large))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "saved-caption-unspecified-servings-\(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(recipe.servings, 0)
        XCTAssertTrue(recipe.sourceDraft?.unknownServings == true)
    }
}
