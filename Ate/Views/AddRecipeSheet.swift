import SwiftUI
import PhotosUI

struct AddRecipeSheet: View {
    enum Mode: String, CaseIterable { case link = "Link", image = "Image", prompt = "Prompt"
        var symbol: String {
            switch self {
            case .link: return "link"
            case .image: return "photo.badge.plus"
            case .prompt: return "pencil.line"
            }
        }
    }
    @Environment(AppStore.self) private var store
    var initial: SharedInbox.Item? = nil
    let onSave: (RecipeCard) -> Void

    init(initial: SharedInbox.Item? = nil, onSave: @escaping (RecipeCard) -> Void) {
        self.initial = initial; self.onSave = onSave
    }

    @State private var mode: Mode = .link
    @State private var link = ""
    @State private var prompt = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var loading = false
    @State private var draft: RecipeCard?
    @State private var didEdit = false
    @State private var editing = false
    @State private var showCamera = false
    @State private var error: String?
    @State private var socialError: SocialLinks.Platform?
    @State private var socialReason: String?
    @State private var dishQuestion: PhotoNeedsDishError?
    @State private var dishAnswer = ""
    @State private var spreadPicks: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if draft == nil { inputState } else { reviewState }
            }
            .foregroundStyle(Theme.foreground)
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { if let t = store.toast { ToastView(toast: t).padding(.top, 8) } }
        .task {
            // Arrived from the "Save to ate" share extension: prefill and start right away.
            guard let it = initial, draft == nil, !loading else { return }
            if let d = SharedInbox.imageData(it) { mode = .image; imageData = d }
            else if let u = it.url { mode = .link; link = u }
            else if let t = it.text { mode = .prompt; prompt = t }
            await generate()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in imageData = img.jpegData(compressionQuality: 0.85) }.ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            Task { imageData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    @ViewBuilder private var inputState: some View {
        Text("Add a recipe").font(AteFont.display(24))
        Text("ate turns a link, a screenshot or an idea into a clean recipe card.")
            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        Picker("Source", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
        }.pickerStyle(.segmented)

        switch mode {
        case .link:
            HStack {
                TextField("https://tiktok.com/...", text: $link).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("linkField")
                Button("Paste") { if let s = UIPasteboard.general.string { link = s } }.font(AteFont.body(13, .semibold))
            }.ateField()
        case .image:
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(Theme.primary)
                    Text(imageData == nil ? "Upload a screenshot or a food photo" : "Image ready — tap to replace")
                        .font(AteFont.body(14, .medium))
                    Text("Screenshots of a recipe are read word for word. A photo of a dish gets a guessed recipe you can edit.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(32)
                .background(Theme.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(Theme.border))
            }
            if CameraPicker.isAvailable || AppConfig.isUITesting {
                Button {
                    if CameraPicker.isAvailable { showCamera = true }
                    else { imageData = Self.sampleImage(); store.show("No camera here — used a sample photo") }
                } label: { Label("Take a photo", systemImage: "camera") }
                    .buttonStyle(.ate(.secondary, height: 44, full: true)).accessibilityIdentifier("takePhoto")
            }
            if AppConfig.isUITesting {
                Button("Use sample screenshot") { imageData = Self.sampleImage() }
                    .buttonStyle(.ate(.secondary, height: 40)).accessibilityIdentifier("sampleImage")
                Button("Use sample food photo") { imageData = Self.sampleFoodPhoto() }
                    .buttonStyle(.ate(.secondary, height: 40)).accessibilityIdentifier("sampleFoodPhoto")
            }
            if let d = imageData, let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: 192)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .prompt:
            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt).accessibilityIdentifier("promptEditor").frame(height: 84).scrollContentBackground(.hidden).padding(6)
                if prompt.isEmpty {
                    Text("A quick weeknight miso salmon for two").foregroundStyle(Theme.mutedForeground).padding(12).allowsHitTesting(false)
                }
            }
            .font(AteFont.body(15))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.input))
        }

        Text(OnDeviceBackend.availabilityDescription).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)

        if let p = socialError {
            VStack(alignment: .leading, spacing: 10) {
                Label(socialReason ?? SocialLinks.noCaptionMessage(p), systemImage: "text.bubble")
                    .font(AteFont.body(14)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("socialNoCaption")
                Text("In \(p.rawValue), tap ⋯ › Copy caption (or select the description), then paste it here.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                Button {
                    if let u = URL(string: link) { prompt = "Recipe from \(SocialLinks.clean(u).absoluteString)\n\n" }
                    mode = .prompt; socialError = nil; error = nil
                } label: { Label("Paste caption in Prompt", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.ate(.primary, height: 40)).accessibilityIdentifier("switchToPrompt")
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 14))
        } else if let q = dishQuestion, mode == .image {
            VStack(alignment: .leading, spacing: 10) {
                Label(q.errorDescription ?? "", systemImage: "questionmark.circle").font(AteFont.body(14))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("photoDishQuestion")
                Text("What dish is this?").font(AteFont.body(14, .semibold))
                TextField(q.spread ? "e.g. mogodu, ujeqe, morogo" : "e.g. mogodu", text: $dishAnswer)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("photoDishField")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(q.suggestions, id: \.self) { s in
                            let on = spreadPicks.contains(s)
                            Button(s) {
                                if q.spread { if on { spreadPicks.remove(s) } else { spreadPicks.insert(s) } } else { dishAnswer = s }
                            }
                            .font(AteFont.body(13)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Theme.primary.opacity(0.2) : Theme.card, in: Capsule())
                        }
                    }
                }
                if q.spread {
                    Text("Pick one dish, or several to make a card for each (the first opens for review, the rest are saved).")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 14))
        } else if let error {
            ErrorRetryCard(message: error, retryID: "generateRetry") { Task { await generate() } }
        }

        Button { Task { await generate() } } label: {
            HStack { if loading { ProgressView().tint(Theme.primaryForeground); Text("Cooking up your card…") }
                     else { Image(systemName: "sparkles"); Text("Generate recipe card") } }
        }
        .buttonStyle(.ate(.primary, height: 52, full: true)).disabled(loading).accessibilityIdentifier("generateButton")
    }

    @ViewBuilder private var reviewState: some View {
        Text("Review your card").font(AteFont.display(24))
        if let d = draft { SourceBadge(source: d.source) }
        if let d = draft, let conf = d.aiConfidence {
            Label("AI confidence \(Int((conf * 100).rounded()))%" + (conf < 0.5 ? " — check this is the right dish" : ""),
                  systemImage: conf < 0.5 ? "exclamationmark.triangle" : "checkmark.seal")
                .font(AteFont.body(13)).foregroundStyle(conf < 0.5 ? Theme.destructive : Theme.mutedForeground)
                .accessibilityIdentifier("aiConfidence")
        }
        if let n = draft?.aiNote { Text(n).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("aiNote") }
        Text("Fix anything the AI got wrong, then save it to your library.")
            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        if editing, draft != nil {
            RecipeEditor(recipe: Binding(get: { draft ?? RecipeCard() }, set: { draft = $0 })).cardSurface(padding: 20)
        } else if let d = draft {
            RecipeCardView(recipe: d, units: store.settings.units)
        }
        HStack(spacing: 8) {
            Button("Save recipe") {
                if let d = draft {
                    BetaQA.shared.pass("A-EDIT-01", note: (didEdit ? "Edited and saved" : "Reviewed and saved") + " “\(d.title)”")
                    onSave(RecipeLogic.normalize(d))
                }
            }
                .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("saveRecipe")
            Button(editing ? "Preview" : "Edit") { editing.toggle(); didEdit = true }.buttonStyle(.ate(.secondary))
            Button { Task { await generate() } } label: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(loading ? 360 : 0))
                    .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
            }
            .buttonStyle(.ate(.ghost)).disabled(loading).accessibilityLabel("Regenerate")
        }
    }

    /// A text-free "photo" (a round dish of colour blobs) to exercise the food-photo path.
    static func sampleFoodPhoto() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { ctx in
            UIColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            UIColor(white: 0.96, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 60, y: 20, width: 280, height: 260))
            UIColor(red: 0.85, green: 0.25, blue: 0.1, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 100, y: 60, width: 200, height: 180))
            UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1).setFill()
            for (x, y) in [(150, 100), (220, 120), (180, 170), (240, 180)] { ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 34, height: 30)) }
        }.jpegData(compressionQuality: 0.9)
    }

    static func sampleImage() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            ("Pancakes\n200 g flour\n2 eggs\nCook 2 minutes" as NSString)
                .draw(at: CGPoint(x: 16, y: 16), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
        }.pngData()
    }

    private func generate() async {
        if store.settings.onDeviceOnly {
            store.show("Private mode is on — turn it off in Settings to use AI.", error: true); return
        }
        var req: ParseRequest
        switch mode {
        case .link:
            guard !link.trimmingCharacters(in: .whitespaces).isEmpty else { store.show("Paste a recipe link first.", error: true); return }
            req = ParseRequest(mode: .url, text: link)
        case .prompt:
            guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { store.show("Describe the dish first.", error: true); return }
            req = ParseRequest(mode: .prompt, text: prompt)
        case .image:
            guard let d = imageData else { store.show("Upload a screenshot first.", error: true); return }
            let jpeg = UIImage(data: d)?.jpegData(compressionQuality: 0.8) ?? d
            var dishes = spreadPicks.sorted()
            for d in dishAnswer.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !d.isEmpty && !dishes.contains(d) { dishes.append(d) }
            req = ParseRequest(mode: .image, text: dishes.first, imageDataUrl: "data:image/jpeg;base64," + jpeg.base64EncodedString())
            if dishes.count > 1 {
                let rest = Array(dishes.dropFirst())
                let base = req
                Task {
                    for d in rest {
                        var r = base; r.text = d
                        if var c = try? await store.backend.parseRecipe(r) { c.origin = .photo; store.add(RecipeLogic.normalize(c)) }
                    }
                    if !rest.isEmpty { store.show("Saved \(rest.count) more card\(rest.count == 1 ? "" : "s") from the spread") }
                }
            }
        }
        loading = true
        error = nil; socialError = nil; socialReason = nil
        defer { loading = false }
        do {
            let started = Date()
            var card = try await store.backend.parseRecipe(req)
            card.origin = mode == .link ? .link : (mode == .image ? .photo : .prompt)
            if mode == .link, let u = URL(string: link.trimmingCharacters(in: .whitespaces)) { card.sourceURL = SocialLinks.clean(u).absoluteString }
            GenerationLog.last = GenerationLog(source: card.source, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                                               mode: mode.rawValue, date: Date())
            draft = RecipeLogic.normalize(card)
            editing = false
            dishQuestion = nil; dishAnswer = ""; spreadPicks = []
            let src = "source \(card.source) in \(Int(Date().timeIntervalSince(started) * 1000)) ms"
            switch mode {
            case .link:
                let host = URL(string: link.trimmingCharacters(in: .whitespaces))?.host ?? ""
                let social = ["instagram", "tiktok", "youtube", "youtu.be"].contains { host.contains($0) }
                BetaQA.shared.pass(social ? "A-CREATE-02" : "A-CREATE-01", note: "Imported from \(host), \(src)")
            case .image: BetaQA.shared.pass("A-CREATE-03", note: "Photo → card, \(src)")
            case .prompt: BetaQA.shared.pass("A-CREATE-04", note: "Prompt → card, \(src)")
            }
        } catch let e as SocialCaptionError {
            socialError = e.platform
            socialReason = e.reason
            BetaQA.shared.pass("A-CREATE-02", note: "No caption on \(e.platform): friendly Prompt offer shown")
            Haptics.warning()
        } catch let e as PhotoNeedsDishError {
            dishQuestion = e
            Haptics.warning()
        } catch let e {
            let msg = (e is URLError) ? Net.friendly(e) : e.localizedDescription
            self.error = msg
            store.show(msg, error: true)
            let id = mode == .link ? "A-CREATE-01" : (mode == .image ? "A-CREATE-03" : "A-CREATE-04")
            if let u = e as? URLError, [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(u.code) {
                BetaQA.shared.pass("A-CREATE-06", note: "Offline \(mode.rawValue) attempt showed: \(msg)")
                BetaQA.shared.markNetworkLoss()
            } else {
                BetaQA.shared.fail(id, error: msg)
            }
            Haptics.error()
        }
    }
}
