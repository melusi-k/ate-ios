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

    var initialMode: WidgetLinks.AddMode?

    init(initial: SharedInbox.Item? = nil, initialMode: WidgetLinks.AddMode? = nil, onSave: @escaping (RecipeCard) -> Void) {
        self.initial = initial; self.initialMode = initialMode; self.onSave = onSave
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
    @State private var coverItem: PhotosPickerItem?
    @State private var showCoverCamera = false
    @State private var confirmDiscard = false
    @State private var saving = false
    @State private var live: RecipeStreamPreview?
    @State private var confirmedDraft = false
    /// Name the user confirmed in "What dish is this?" (C-AI-01); the regenerated card is not asked about again.
    @State private var confirmedDish: String?
    @Environment(\.dismiss) private var dismiss
    private var hasUnsaved: Bool {
        (draft != nil && !saving) || !link.trimmingCharacters(in: .whitespaces).isEmpty || !prompt.trimmingCharacters(in: .whitespaces).isEmpty || imageData != nil
    }

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
        // Unsaved input can't be swiped away by accident; the drag asks first. Input and drafts survive offline / model-unavailable errors.
        .interactiveDismissDisabled(hasUnsaved)
        // Proper nav bar: Cancel sits in a solid bar instead of floating over the cover while scrolling.
        .navigationTitle(draft == nil ? "Add recipe" : "Review your card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if hasUnsaved { confirmDiscard = true } else { dismiss() } }.accessibilityIdentifier("addCancel")
                    .confirmationDialog("Discard this recipe?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { DraftStore.shared.clear(); dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    }
            }
        }
        .onDisappear { if !loading && !hasUnsaved { DraftStore.shared.clear() } }
        .task {
            OnDeviceBackend.prewarm()
            if let m = initialMode, draft == nil {
                mode = m == .photo ? .image : m == .prompt ? .prompt : .link
            }
            if initial == nil, draft == nil, !loading { restoreInterrupted() }
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
        .fullScreenCover(isPresented: $showCoverCamera) {
            CameraPicker { img in setUserCover(img) }.ignoresSafeArea()
        }
        .onChange(of: coverItem) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { setUserCover(img) } }
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
                    Image(systemName: "photo.badge.plus").font(.title).foregroundStyle(Theme.primary)
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
            .sheetCard(Theme.secondary)
        } else if let q = dishQuestion {
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
            .sheetCard(Theme.secondary)
        } else if let error {
            ErrorRetryCard(message: error, retryID: "generateRetry") { Task { await generate() } }
        }

        if loading, let p = live { StreamPreviewCard(preview: p) }

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
            Label("AI confidence \(Int((conf * 100).rounded()))%" + (conf < RecipeQuality.threshold ? " — check this is the right dish" : ""),
                  systemImage: conf < RecipeQuality.threshold ? "exclamationmark.triangle" : "checkmark.seal")
                .font(AteFont.body(13)).foregroundStyle(conf < RecipeQuality.threshold ? Theme.destructive : Theme.mutedForeground)
                .accessibilityIdentifier("aiConfidence")
        }
        if let d = draft, RecipeQuality.needsInput(d), !didEdit, !confirmedDraft {
            VStack(alignment: .leading, spacing: 6) {
                Label("Draft, needs your input", systemImage: "exclamationmark.bubble").font(AteFont.body(14, .semibold))
                if (d.aiConfidence ?? 1) < RecipeQuality.threshold {
                    Text("Ate is only \(d.aiConfidence ?? 0, format: .percent.precision(.fractionLength(0))) sure this is \(d.title).").font(AteFont.body(13))
                }
                ForEach(RecipeQuality.issues(d), id: \.self) { Text("• " + $0).font(AteFont.body(13)) }
                Text("Edit the card, or confirm it's right, before saving.").font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                Button("It's right, let me save") { confirmedDraft = true }.buttonStyle(.ate(.secondary, height: 36))
                    .accessibilityIdentifier("confirmDraft")
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard(Theme.warm.opacity(0.5))
            .accessibilityIdentifier("draftNeedsInput")
        }
        if let n = draft?.aiNote { Text(n).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("aiNote") }
        Text("Fix anything the AI got wrong, then save it to your library.")
            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        if let d = draft { coverEditor(d) }
        if editing, draft != nil {
            RecipeEditor(recipe: Binding(get: { draft ?? RecipeCard() }, set: { draft = $0 })).cardSurface(padding: 20)
        } else if let d = draft {
            RecipeCardView(recipe: d, units: store.settings.units)
        }
        HStack(spacing: 8) {
            Button(saving ? "Saving…" : "Save recipe") {
                guard !saving, let d = draft else { return }
                saving = true                       // P0: one save per draft; double taps are ignored
                DraftStore.shared.clear()           // the stored draft must not be restored (and saved again) later
                DiagnosticHistory.shared.record(.recipeSaved)
                BetaQA.shared.pass("A-EDIT-01", note: (didEdit ? "Edited and saved" : "Reviewed and saved") + " “\(d.title)”")
                onSave(RecipeLogic.normalize(d))
            }
                .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("saveRecipe")
                .disabled(saving || (draft.map { RecipeQuality.needsInput($0) } ?? false) && !didEdit && !confirmedDraft)
            Button(editing ? "Preview" : "Edit") { editing.toggle(); didEdit = true }.buttonStyle(.ate(.secondary))
            Button { Task { await generate() } } label: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(loading ? 360 : 0))
                    .animation(loading ? Motion.anim(.linear(duration: 1).repeatForever(autoreverses: false)) : Motion.anim(), value: loading)
            }
            .buttonStyle(.ate(.ghost)).disabled(loading).accessibilityLabel("Regenerate")
        }
    }

    @ViewBuilder private func coverEditor(_ d: RecipeCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeHero(recipe: d, autoBackfill: false)
            HStack(spacing: 8) {
                Menu {
                    PhotosPicker(selection: $coverItem, matching: .images) { Label("Choose photo", systemImage: "photo.on.rectangle") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCoverCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    }
                } label: { Label("Change photo", systemImage: "photo") }
                    .buttonStyle(.ate(.secondary, height: 36)).accessibilityIdentifier("changeCover")
                if AppConfig.isUITesting {
                    Button("Sample cover") { if let d = Self.sampleFoodPhoto(), let img = UIImage(data: d) { setUserCover(img) } }
                        .buttonStyle(.ate(.secondary, height: 36)).accessibilityIdentifier("sampleCover")
                }
                if CoverStore.playgroundAvailable && !ProcessInfo.processInfo.arguments.contains("-qaNoPlayground") {
                    Button {
                        Task {
                            guard let cur = draft, let name = await CoverStore.shared.generate(for: cur) else {
                                store.show("Couldn't generate an image right now.", error: true); return
                            }
                            draft?.coverImage = name
                        }
                    } label: { Label("Generate cover", systemImage: "wand.and.sparkles") }
                        .buttonStyle(.ate(.secondary, height: 36)).accessibilityIdentifier("generateCover")
                        .disabled(CoverStore.shared.isLoading(d.id))
                }
                if d.coverImage != nil && d.coverImage != CoverStore.removed {
                    Button { CoverStore.shared.removeFiles(recipeID: d.id); draft?.coverImage = CoverStore.removed } label: {
                        Label("Remove", systemImage: "xmark")
                    }.buttonStyle(.ate(.ghost, height: 36)).accessibilityIdentifier("removeCover")
                }
            }
            .font(AteFont.body(13))
        }
    }

    private func setUserCover(_ img: UIImage) {
        guard let id = draft?.id, let name = CoverStore.shared.save(img, recipeID: id, source: .userPhoto) else { return }
        draft?.coverImage = name
    }

    /// Picks the initial cover for a fresh draft (async; saving never waits for it).
    private func chooseInitialCover(for card: RecipeCard) {
        if mode == .image, let d = imageData, let img = UIImage(data: d) {
            draft?.coverImage = CoverStore.shared.save(img, recipeID: card.id, source: .userPhoto)
            return
        }
        Task {
            guard let res = await CoverStore.shared.resolve(card) else { return }
            if draft?.id == card.id, draft?.coverImage == nil {
                draft?.coverImage = res.file
                if let u = res.imageURL { draft?.imageURL = u }
            } else if store.recipe(card.id)?.coverImage == nil {
                store.setCover(card.id, file: res.file, imageURL: res.imageURL)   // already saved
            }
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

    /// A-CREATE-05: the app was closed mid-generation (or with an unsaved card) last time.
    private func restoreInterrupted() {
        if let c = DraftStore.shared.draft, store.recipe(c.id) != nil {
            DraftStore.shared.clear()   // P0: this draft was already saved; restoring it made duplicate copies
        } else if let c = DraftStore.shared.draft {
            draft = c; store.show("Restored your unsaved card")
            BetaQA.shared.pass("A-CREATE-05", note: "Restored unsaved draft “\(c.title)” after relaunch")
        } else if let p = DraftStore.shared.pending {
            if let m = Mode(rawValue: p.mode) { mode = m }
            switch mode {
            case .link: link = p.text
            case .prompt: prompt = p.text
            case .image:
                if let data = p.imageData { imageData = data }
                else { error = "Your previous photo could not be restored. Select the photo again, then generate your recipe." }
            }
            if error == nil { error = Self.interruptedMessage }
            // Keep the pending request until retry succeeds or the user discards it.
            // Clearing it here loses the only recoverable input if the app closes before Retry.
            BetaQA.shared.pass("A-CREATE-05", note: "Interrupted \(p.mode) generation offered a retry after relaunch")
        }
    }
    static let interruptedMessage = "Your last recipe was interrupted when ate closed. Tap Try again to retry."

    /// Keep recoverable image input small enough for DraftStore/UserDefaults while retaining useful visual detail.
    private static func recoverableJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        // Try progressively smaller, lower-quality encodings to stay below DraftStore's 1.5 MB safety limit.
        for maxDimension in [CGFloat(1280), CGFloat(1024), CGFloat(768), CGFloat(640)] {
            let scale = min(1, maxDimension / max(longest, 1))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let renderer = UIGraphicsImageRenderer(size: size)
            for quality in [CGFloat(0.72), CGFloat(0.55), CGFloat(0.4)] {
                let encoded = renderer.jpegData(withCompressionQuality: quality) { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                if encoded.count <= 1_500_000 { return encoded }
            }
        }
        return nil
    }

    private func generate() async {
        // The UI disables generation while loading, but keep the lifecycle safe against rapid or programmatic duplicate taps.
        guard !loading else { return }
        if store.settings.onDeviceOnly {
            store.show("Private mode is on — turn it off in Settings to use AI.", error: true); return
        }
        var req: ParseRequest
        switch mode {
        case _ where mode != .image && dishQuestion != nil && !dishAnswer.trimmingCharacters(in: .whitespaces).isEmpty:
            // Low-confidence card: regenerate conditioned on the confirmed name (+ glossary via RecipePrompt.prompt).
            let name = dishAnswer.trimmingCharacters(in: .whitespaces)
            confirmedDish = name
            let ctx = (mode == .link ? link : prompt).trimmingCharacters(in: .whitespacesAndNewlines)
            req = ParseRequest(mode: .prompt, text: ctx.isEmpty ? name : "\(name). Context: \(ctx.prefix(400))")
        case .link:
            guard !link.trimmingCharacters(in: .whitespaces).isEmpty else { store.show("Paste a recipe link first.", error: true); return }
            req = ParseRequest(mode: .url, text: link)
        case .prompt:
            guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { store.show("Describe the dish first.", error: true); return }
            req = ParseRequest(mode: .prompt, text: prompt)
        case .image:
            guard let d = imageData else { store.show("Upload a screenshot first.", error: true); return }
            let jpeg = Self.recoverableJPEG(from: d) ?? d
            imageData = jpeg
            var dishes = spreadPicks.sorted()
            for d in dishAnswer.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !d.isEmpty && !dishes.contains(d) { dishes.append(d) }
            if dishQuestion != nil, let f = dishes.first { confirmedDish = f }
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
        live = nil
        OnDeviceBackend.partialSink = { p in live = p }
        DraftStore.shared.begin(mode: mode.rawValue, text: mode == .link ? link : (mode == .prompt ? prompt : ""),
                                imageData: mode == .image ? imageData : nil)
        // Keep pending input on failure or while asking the user to identify an uncertain dish.
        // DraftStore.saveDraft clears it on success; Cancel/Discard clears it explicitly.
        defer { loading = false; OnDeviceBackend.partialSink = nil; live = nil }
        do {
            let started = Date()
            var card = try await store.backend.parseRecipe(req)
            card.origin = mode == .link ? .link : (mode == .image ? .photo : .prompt)
            if mode == .link, let u = URL(string: link.trimmingCharacters(in: .whitespaces)) { card.sourceURL = SocialLinks.clean(u).absoluteString }
            GenerationLog.last = GenerationLog(source: card.source, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                                               mode: mode.rawValue, date: Date())
            let normalized = RecipeLogic.normalize(card)
            // C-AI-01: under 80% confidence the card is NOT presented as a recipe; ask "What dish is this?" with the
            // model's own guesses pre-filled. ≥ 80% skips the question entirely.
            if RecipeQuality.shouldAskDish(normalized, alreadyConfirmed: confirmedDish != nil) {
                let g = RecipeQuality.guesses(normalized)
                dishQuestion = PhotoNeedsDishError(suggestions: g, spread: false)
                dishAnswer = g.first ?? ""; spreadPicks = []
                Haptics.warning()
                return
            }
            draft = normalized
            confirmedDraft = false
            if let d = draft { chooseInitialCover(for: d); DraftStore.shared.saveDraft(d) }
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
        } catch is CancellationError {
            // Cancellation is a terminal attempt outcome, not a model failure. Keep the
            // persisted request so the user can retry without re-entering their input.
            self.error = Self.interruptedMessage
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

/// The card as it streams in (title → ingredients → steps), rendered from the structured partial output.
struct StreamPreviewCard: View {
    let preview: RecipeStreamPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title ?? "Identifying the dish…").font(AteFont.display(20)).redacted(reason: preview.title == nil ? .placeholder : [])
            if let c = preview.cuisine, !c.isEmpty { Text(c.uppercased()).overline() }
            ForEach(Array(preview.ingredients.enumerated()), id: \.offset) { Text("• " + $0.element).font(AteFont.body(14)) }
            ForEach(Array(preview.steps.enumerated()), id: \.offset) { Text("\($0.offset + 1). " + $0.element).font(AteFont.body(14)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 16)
        .animation(Motion.anim(), value: preview)
        .accessibilityIdentifier("streamPreview")
    }
}

extension View {
    /// Cards inside sheets: concentric with the sheet's corners on iOS 26 (C-TAB-06), rounded rect before.
    @ViewBuilder func sheetCard(_ fill: Color) -> some View {
        if #available(iOS 26, *) { background(fill, in: ConcentricRectangle()) }
        else { background(fill, in: RoundedRectangle(cornerRadius: 14)) }
    }
}