import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Save to ate": takes a link, text or image from any app and queues it for the app to turn into a recipe card.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model, done: { [weak self] in self?.finish() },
                                                           open: { [weak self] in self?.openApp() }))
        addChild(host); view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        Task { await model.load(extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }

    private func finish() { extensionContext?.completeRequest(returningItems: nil) }

    /// Share extensions can't call `open(_:)` directly; walk the responder chain to the host application.
    private func openApp() {
        let url = URL(string: "ate://import")!
        var r: UIResponder? = self
        while let cur = r {
            if let app = cur as? UIApplication { app.open(url); break }
            r = cur.next
        }
        finish()
    }
}

@MainActor final class ShareModel: ObservableObject {
    enum State: Equatable { case loading, saved(String), copied(String), failed(String) }
    @Published var state: State = .loading

    func load(_ items: [NSExtensionItem]) async {
        let boundary = SharedWriterBoundary.current // retained before ANY provider await
        let inboxDirectory = SharedInbox.folder
        var imageData: Data?
        let providers = items.flatMap { $0.attachments ?? [] }
        var item = SharedInbox.Item()
        for p in providers {
            if item.url == nil, p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                item.url = u.absoluteString
            } else if item.text == nil, p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                item.text = t
                if item.url == nil { item.url = SharedInbox.firstURL(in: t) }
            } else if imageData == nil, p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                imageData = await loadImageData(p)
            }
        }
        guard item.url != nil || item.text != nil || imageData != nil else {
            state = .failed("Nothing ate can read here. Try sharing a link or a photo."); return
        }
        let what = imageData != nil ? "Photo" : (item.url.flatMap { URL(string: $0)?.host } ?? "Text")
        if SharedContainer.isAvailable {
            let queued: Bool
            if let imageData {
                queued = SharedInbox.pushImage(imageData, item: item, directory: inboxDirectory, boundary: boundary)
            } else { queued = SharedInbox.push(item, boundary: boundary) }
            if queued {
                state = .saved(what)
            } else {
                // The writer boundary refused: nothing was queued, so never claim a save.
                state = .failed("ate couldn't queue this just now. Please try again.")
            }
        } else {
            // No App Group (free-account sideload): only text/link can use clipboard.
            guard item.url != nil || item.text != nil else {
                state = .failed("Nothing ate can read here. Try sharing a link or a photo."); return
            }
            UIPasteboard.general.string = item.url ?? item.text
            state = .copied(what)
        }
    }

    private func loadImageData(_ p: NSItemProvider) async -> Data? {
        let raw = try? await p.loadItem(forTypeIdentifier: UTType.image.identifier)
        var data: Data?
        if let u = raw as? URL { data = try? Data(contentsOf: u) }
        else if let img = raw as? UIImage { data = img.jpegData(compressionQuality: 0.85) }
        else if let d = raw as? Data { data = d }
        return data
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void
    let open: () -> Void
    private let orange = Color(red: 0.725, green: 0.282, blue: 0.122)

    var body: some View {
        VStack(spacing: 16) {
            Image("AteLogo").resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
            switch model.state {
            case .loading:
                ProgressView("Saving to ate…")
            case .saved(let what):
                Text("Saved to ate").font(.title2.bold())
                Text("\(what) is waiting in ate. Open the app and it'll turn into a recipe card.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(action: open) { Text("Open ate").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(orange)
                Button("Done", action: done)
            case .copied(let what):
                Text("Link copied").font(.title2.bold())
                Text("\(what) was copied. Open ate and paste it on the Link tab.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(action: open) { Text("Open ate").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(orange)
                Button("Done", action: done)
            case .failed(let why):
                Text("Couldn't save").font(.title2.bold())
                Text(why).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Close", action: done)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
