import SwiftUI

extension View {
    /// Match Library's search chrome (keeps content visible while searching; soft top edge).
    /// Added after rotation stalls with a plain always-drawer searchable (#364 diagnostics).
    @ViewBuilder func journalSearchChrome() -> some View {
        if #available(iOS 26, *) {
            searchPresentationToolbarBehavior(.avoidHidingContent).softTopEdge()
        } else {
            self
        }
    }
}
