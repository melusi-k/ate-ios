import XCTest

/// AX can report an offscreen ingredient as hittable. Nonintersection with the
/// Cook button also accepts rows BELOW it. Require the entire row in the actual
/// viewport, below the pinned navigation controls and above the opaque footer.
enum RecipeDetailVisibility {
    static func contains(_ row: XCUIElement, scroll: XCUIElement,
                         header: XCUIElement, footer: XCUIElement) -> Bool {
        guard row.exists, scroll.exists, header.exists, footer.exists else { return false }
        let viewport = scroll.frame
        let top = max(viewport.minY, header.frame.maxY) + 8
        let bottom = min(viewport.maxY, footer.frame.minY - 8)
        let band = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
        let frame = row.frame
        return frame.width > 0 && frame.height > 0 && band.contains(frame) && row.isHittable
    }
}
