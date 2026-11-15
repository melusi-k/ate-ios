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

    /// Same five-gesture budget, but no blind full-screen flicks. An ingredient
    /// already above the header needs a downward drag, not another upward swipe.
    /// Slow, held drags avoid momentum carrying a short row through the band.
    static func reveal(_ row: XCUIElement, scroll: XCUIElement,
                       header: XCUIElement, footer: XCUIElement) {
        for attempt in 0..<5 {
            if contains(row, scroll: scroll, header: header, footer: footer) { return }
            guard row.exists, scroll.exists, header.exists, footer.exists else { return }
            let viewport = scroll.frame
            let top = max(viewport.minY, header.frame.maxY) + 8
            let bottom = min(viewport.maxY, footer.frame.minY - 8)
            let band = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
            let frame = row.frame
            XCTContext.runActivity(named: "Ingredient geometry before drag \(attempt + 1)") { activity in
                let evidence = XCTAttachment(string: "row=\(frame) viewport=\(viewport) header=\(header.frame) footer=\(footer.frame) band=\(band)")
                evidence.lifetime = .keepAlways
                activity.add(evidence)
            }
            // No vertical gesture can repair an invalid/too-tall/wide AX frame.
            // Leave it for the original strict geometry assertion, never accept it.
            guard band.width > 0, band.height > 0, frame.width > 0, frame.height > 0,
                  frame.height <= band.height, frame.minX >= band.minX, frame.maxX <= band.maxX else { return }
            let delta: CGFloat
            if frame.minY < band.minY {
                delta = min(band.height * 0.6, band.midY - frame.midY)
            } else if frame.maxY > band.maxY {
                delta = max(-band.height * 0.6, band.midY - frame.midY)
            } else {
                // Fully contained but not hittable: scrolling is not the answer.
                return
            }
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: band.midX - viewport.minX,
                                                   dy: band.midY - delta / 2 - viewport.minY))
            let end = origin.withOffset(CGVector(dx: band.midX - viewport.minX,
                                                 dy: band.midY + delta / 2 - viewport.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

}
