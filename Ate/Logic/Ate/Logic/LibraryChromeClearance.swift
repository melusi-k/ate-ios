import Foundation

/// Global-coordinate overlap between the Library viewport and floating root chrome.
/// Scroll-content measurement would feed its own spacer back into the height, so callers
/// measure only the fixed viewport. Already-inset viewports do not reserve the band twice.
enum LibraryChromeClearance {
    static func reserve(hostBottom: CGFloat?, chromeTop: CGFloat?) -> CGFloat {
        guard let hostBottom, let chromeTop, hostBottom.isFinite, chromeTop.isFinite else { return 96 }
        return max(0, hostBottom - chromeTop) + 16
    }
}
