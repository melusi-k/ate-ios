import XCTest
import SwiftUI
import UIKit
@testable import Ate

@MainActor
final class RecipeRowMetadataTests: XCTestCase {
    private func size<V: View>(_ view: V, width: CGFloat? = nil) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, .large))
        return host.sizeThatFits(in: CGSize(width: width ?? 1000, height: 1000))
    }

    func testMetadataItemsStaySingleLineAtNarrowWidths() {
        // Includes the owner's 45/115 minute and multiword category/cuisine shapes.
        // Narrow proposals must truncate a single item, never make a letter column.
        let items = [
            RecipeRowMetadataItem(text: "45 min", symbol: "clock"),
            RecipeRowMetadataItem(text: "115 min", symbol: "clock"),
            RecipeRowMetadataItem(text: "6", symbol: "person.2"),
            RecipeRowMetadataItem(text: "side dish"),
            RecipeRowMetadataItem(text: "south african"),
            RecipeRowMetadataItem(text: "an unusually long saved recipe category")
        ]
        for item in items {
            let ideal = size(item)
            XCTAssertGreaterThan(ideal.height, 0)
            for width in [CGFloat(32), 80, 144, 180] {
                let constrained = size(item, width: width)
                XCTAssertGreaterThan(constrained.height, 0)
                XCTAssertLessThanOrEqual(constrained.height, ideal.height + 0.5,
                                         "Metadata must not wrap inside an individual chip")
                XCTAssertLessThanOrEqual(constrained.width, width + 0.5)
            }
        }
    }

    func testLayoutMovesWholeItemsAndCapsOversizedTagsWithoutOverlap() {
        XCTAssertEqual(RecipeRowMetadataLayout.availableWidth(proposed: .infinity, ideal: 200), 200)
        XCTAssertEqual(RecipeRowMetadataLayout.availableWidth(proposed: nil, ideal: 200), 200)
        XCTAssertEqual(RecipeRowMetadataLayout.availableWidth(proposed: 0, ideal: 200), 0)
        let sizes = [CGSize(width: 64, height: 20), CGSize(width: 38, height: 20),
                     CGSize(width: 78, height: 26), CGSize(width: 110, height: 26)]
        let frames = RecipeRowMetadataLayout.frames(sizes: sizes, width: 180, spacing: 8)
        XCTAssertEqual(frames.map(\.width), sizes.map(\.width), "Normal chips retain their whole width")
        XCTAssertEqual(frames.map(\.minY), [0, 0, 28, 62])
        let capped = RecipeRowMetadataLayout.frames(sizes: [CGSize(width: 900, height: 26), sizes[0]],
                                                    width: 144, spacing: 8)
        XCTAssertEqual(capped[0].width, 144)
        XCTAssertEqual(capped[1].minY, 34)
        for width in [CGFloat(144), 180, 216, 258] {
            let result = RecipeRowMetadataLayout.frames(sizes: sizes, width: width, spacing: 8)
            for (index, frame) in result.enumerated() {
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width)
                XCTAssertEqual(frame.height, sizes[index].height)
                for earlier in result.prefix(index) { XCTAssertFalse(frame.intersects(earlier)) }
            }
        }
    }

    func testRenderedOwnerShapedRowsRetainCompactMetadataAndScreenshots() throws {
        for minutes in [45, 115] {
            let recipe = RecipeCard(id: "metadata-\(minutes)", title: minutes == 45 ? "Delicious Creamy Samp Recipe with a long title" : "Jerk BBQ Chicken",
                                    description: minutes == 45 ? "Explore our delicious Creamy Samp recipe." : "Traditional South African-style chicken marinated and grilled.",
                                    servings: minutes == 45 ? 6 : 4, timeMinutes: minutes,
                                    tags: [minutes == 45 ? "side dish" : "main", "south african"])
            for width in [CGFloat(286), 326, 350] {
                // Thumbnail 56 + gap 16 + card insets 32, matching the real shared row.
                let columnWidth = width - 104
                let metadataSize = size(RecipeRowMetadata(recipe: recipe), width: columnWidth)
                let chipHeight = size(RecipeRowMetadataItem(text: "south african")).height
                // At most one intact item per row, never a multi-line text stack in an item.
                XCTAssertLessThanOrEqual(metadataSize.height, 4 * chipHeight + 3 * 8 + 1)
                XCTAssertLessThanOrEqual(metadataSize.width, columnWidth + 0.5)
                let renderer = ImageRenderer(content: RecipeRowView(recipe: recipe)
                    .frame(width: width).environment(\.dynamicTypeSize, .large))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "recipe-row-\(minutes)min-\(Int(width))pt"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
