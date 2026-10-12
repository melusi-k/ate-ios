import Foundation

/// User-facing transparency copy (checklist 8.6 AI transparency, 9.7 beta expectations). Kept in one place so tests can pin it.
enum Transparency {
    static let ai = "AI drafts are made on your iPhone with Apple Intelligence — no recipe content goes to a third-party AI. Drafts can be wrong, so check quantities, times and allergens before cooking."
    static let betaTitle = String(localized: "What to expect in this beta")
    static let beta: [String] = [
        String(localized: "Installed by sideloading with a free Apple ID: the app must be re-signed every 7 days."),
        String(localized: "Shared links open the web page; tapping \"Open in ate\" works where ate is installed. Universal links come later."),
        String(localized: "Instagram/TikTok often hide captions — paste the caption into Prompt if a link doesn't import."),
        String(localized: "Without Apple Intelligence, links with recipe page data still import; other inputs use a simple demo draft."),
        String(localized: "Export your data from Settings › Tools now and then. Report bugs to melusi.l.k@gmail.com."),
        String(localized: "In beta-channel builds, use Settings › Beta testing to see what to try; most items tick themselves as you use the app."),
    ]
}
