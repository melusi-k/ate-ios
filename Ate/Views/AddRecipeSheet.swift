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
    /// Starting text for the prompt mode (for example a search with no results becomes the new idea).
    var initialPrompt: String?

    init(initial: SharedInbox.Item? = nil, initialMode: WidgetLinks.AddMode? = nil, initialPrompt: String? = nil, onSave: @escaping (RecipeCard) -> Void) {
        self.initial = initial; self.initialMode = initialMode; self.initialPrompt = initialPrompt; self.onSave = onSave
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
    @State private var repairError: String?
    @State private var repairResult: String?
    @State private var repairStatusRevision = 0
    @State private var repairAttempt = DraftRepairAttempt()
    @State private var generationAttempt = DraftGenerationAttempt()
    @State private var photoInputAttempt = DraftInputAttempt()
    @State private var coverInputAttempt = DraftInputAttempt()
    /// Name the user confirmed in "What dish is this?" (C-AI-01); the regenerated card is not asked about again.
    @State private var confirmedDish: String?
    @Environment(\.dismiss) private var dismiss
    private var hasUnsaved: Bool {
        (draft != nil && !saving) || !link.trimmingCharacters(in: .whitespaces).isEmpty || !prompt.trimmingCharacters(in: .whitespaces).isEmpty || imageData != nil
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if draft == nil { inputState } else { reviewState }
            }
            .foregroundStyle(Theme.foreground)
            .padding(20)
        }
        .onChange(of: repairStatusRevision) { _, _ in
            withAnimation(Motion.anim()) { reader.scrollTo("repairStatusAnchor", anchor: .center) }
        }
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
                        Button("Discard", role: .destructive) {
                            invalidateRepair()
                            invalidateGeneration()
                            invalidateInputLoads()
                            DraftStore.shared.clear()
                            dismiss()
                        }
                        Button("Keep editing", role: .cancel) {}
                    }
            }
        }
        .onDisappear {
            invalidateRepair()
            invalidateGeneration()
            invalidateInputLoads()
            if !loading && !hasUnsaved { DraftStore.shared.clear() }
        }
        .task {
            OnDeviceBackend.prewarm()
            if let m = initialMode, draft == nil {
                mode = m == .photo ? .image : m == .prompt ? .prompt : .link
            }
            if let initialPrompt, draft == nil, prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                mode = .prompt
                prompt = initialPrompt
            }
            if initial == nil, draft == nil, !loading { restoreInterrupted() }
            // Arrived from the "Save to ate" share extension: prefill and start right away.
            guard let it = initial, draft == nil, !loading else { return }
            if let d = SharedInbox.imageData(it) { mode = .image; imageData = d }
            else if let u = it.url { mode = .link; link = u }
            else if let t = it.text { mode = .prompt; prompt = t }
            startGeneration()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                photoInputAttempt.invalidate()
                imageData = img.jpegData(compressionQuality: 0.85)
            }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCoverCamera) {
            CameraPicker { img in setUserCover(img) }.ignoresSafeArea()
        }
        .onChange(of: coverItem) { _, item in
            let recipeID = draft?.id
            coverInputAttempt.start(load: { try? await item?.loadTransferable(type: Data.self) }) { data in
                guard let recipeID, draft?.id == recipeID, !saving,
                      let data, let image = UIImage(data: data) else { return }
                setUserCover(image)
            }
        }
        .onChange(of: photoItem) { _, item in
            photoInputAttempt.start(load: { try? await item?.loadTransferable(type: Data.self) }) { data in
                guard !saving else { return }
                imageData = data
            }
        }
    }

    @ViewBuilder private var inputState: some View {
        Text("Add a recipe").font(AteFont.display(24))
        Text("Import an existing recipe from a link or screenshot. Describe an idea to generate a new recipe.")
            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        Picker("Source", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
        }.pickerStyle(.segmented)

        switch mode {
        case .link:
            Text("Import an existing recipe. We'll read the source, not invent a new dish.").font(AteFont.body(14))
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
                    Text("Recipe screenshots use detected text, not an AI rewrite. Check OCR wording against the original. Clear Ingredients and numbered Method sections are required. A dish photo gets a guessed recipe you can edit.")
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
            Text("Generate a new recipe from your idea. Review and edit the result before saving.").font(AteFont.body(14))
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
                TextField(q.spread ? "e.g. mogodu, ujeqe, morogo" : (mode == .image ? "e.g. fish with butter sauce and fennel salad" : "e.g. mogodu"), text: $dishAnswer)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("photoDishField")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(q.spread || mode != .image ? q.suggestions : PhotoGuess.questionSuggestions(q.suggestions), id: \.self) { s in
                            let on = spreadPicks.contains(s)
                            Button(s) {
                                if q.spread { if on { spreadPicks.remove(s) } else { spreadPicks.insert(s) } } else { dishAnswer = s }
                            }
                            .font(AteFont.body(13)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Theme.primary.opacity(0.2) : Theme.card, in: Capsule())
                        }
                    }
                }
                if !q.spread && mode == .image {
                    Text("These are choices, not confirmed identifications. You can name the dish and any sauce, garnish or side you want included.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
                if q.spread {
                    Text("Pick one dish, or several to make a card for each (the first opens for review, the rest are saved).")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard(Theme.secondary)
        } else if let error {
            ErrorRetryCard(message: error, retryID: "generateRetry") { startGeneration() }
        }

        if loading, let p = live { StreamPreviewCard(preview: p) }

        Button { startGeneration() } label: {
            HStack { if loading { ProgressView().tint(Theme.primaryForeground); Text("Cooking up your card…") }
                     else { Image(systemName: "sparkles"); Text(mode == .link ? "Import recipe" : mode == .image ? "Read image" : "Generate recipe") } }
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
                // An identifier on the enclosing VStack propagates to its Buttons
                // on iOS 27, hiding their distinct repair/confirm identifiers.
                Label("Draft, needs your input", systemImage: "exclamationmark.bubble").font(AteFont.body(14, .semibold))
                    .accessibilityIdentifier("draftNeedsInput")
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
        }
        if let d = draft, RecipeQuality.isGenerated(d) {
            VStack(alignment: .leading, spacing: 8) {
                if !RecipeQuality.shortfall(d).isEmpty {
                    Button(loading ? "Repairing draft…" : "Repair these gaps") { repairDraft() }
                        .buttonStyle(.ate(.secondary, height: 44))
                        .disabled(loading || saving)
                        .accessibilityIdentifier("repairDraftQuality")
                    Text("Repairs this draft using the listed gaps. It does not choose a different dish.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
                if let repairResult {
                    Text(repairResult).font(AteFont.body(13))
                        .accessibilityIdentifier("repairDraftResult")
                }
                if let repairError {
                    Text(repairError).font(AteFont.body(13)).foregroundStyle(Theme.destructive)
                        .accessibilityIdentifier("repairDraftError")
                }
                Text(RepairFeedback.confidenceExplanation).font(AteFont.body(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("repairConfidenceExplanation")
            }
            .id("repairStatusAnchor")
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
                invalidateInputLoads()
                saving = true                       // P0: one save per draft; double taps are ignored
                DraftStore.shared.clear()           // the stored draft must not be restored (and saved again) later
                BetaQA.shared.pass("A-EDIT-01", note: (didEdit ? "Edited and saved" : "Reviewed and saved") + " “\(d.title)”")
                onSave(RecipeLogic.normalize(d))
                // Record only after handing the normalized recipe to the owning save flow.
                DiagnosticHistory.shared.record(.recipeSaved)
            }
                .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("saveRecipe")
                .disabled(saving || loading || (draft.map { RecipeQuality.needsInput($0) } ?? false) && !didEdit && !confirmedDraft)
            Button(editing ? "Preview" : "Edit") { editing.toggle(); didEdit = true }.buttonStyle(.ate(.secondary))
            Button { startGeneration() } label: {
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
                    Button { coverInputAttempt.invalidate(); CoverStore.shared.removeFiles(recipeID: d.id); draft?.coverImage = CoverStore.removed } label: {
                        Label("Remove", systemImage: "xmark")
                    }.buttonStyle(.ate(.ghost, height: 36)).accessibilityIdentifier("removeCover")
                }
            }
            .font(AteFont.body(13))
        }
    }

    private func setUserCover(_ img: UIImage) {
        coverInputAttempt.invalidate()
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

    /// A high-contrast, multi-line recipe screenshot so UI automation exercises Vision OCR
    /// with a stable fixture instead of a tiny, borderline-text image.
    static func sampleImage() -> Data? {
        let size = CGSize(width: 800, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 48),
                .foregroundColor: UIColor.black
            ]
            let body: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            ("Pancakes" as NSString).draw(at: CGPoint(x: 56, y: 36), withAttributes: title)
            ("Serves: 2" as NSString).draw(at: CGPoint(x: 56, y: 100), withAttributes: body)
            ("Ingredients" as NSString).draw(at: CGPoint(x: 56, y: 160), withAttributes: body)
            ("200 g flour" as NSString).draw(at: CGPoint(x: 56, y: 245), withAttributes: body)
            ("2 eggs" as NSString).draw(at: CGPoint(x: 56, y: 350), withAttributes: body)
            ("Method" as NSString).draw(at: CGPoint(x: 56, y: 440), withAttributes: body)
            ("1. Cook for 2 minutes." as NSString).draw(at: CGPoint(x: 56, y: 510), withAttributes: body)
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

    struct PreparedImage {
        let previewAndCover: Data
        let requestAndRecovery: Data
    }

    static func prepareImage(_ original: Data) -> PreparedImage {
        PreparedImage(previewAndCover: original,
                      requestAndRecovery: recoverableJPEG(from: original) ?? original)
    }

    /// Keep recoverable image input small enough for DraftStore/UserDefaults while retaining useful visual detail.
    static func recoverableJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        // Try progressively smaller, lower-quality encodings to stay below DraftStore's 1.5 MB safety limit.
        // Preserve small text in tall recipe screenshots at the first tier. The byte
        // limit still bounds draft storage, with smaller tiers as fallbacks.
        for maxDimension in [CGFloat(2048), CGFloat(1600), CGFloat(1280), CGFloat(1024), CGFloat(768), CGFloat(640)] {
            let scale = min(1, maxDimension / max(longest, 1))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            // Dimensions above are pixel bounds, not points. The default renderer uses
            // the device scale (3x), silently expanding an 800px fixture to 2400px for OCR.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            for quality in [CGFloat(0.72), CGFloat(0.55), CGFloat(0.4)] {
                let encoded = renderer.jpegData(withCompressionQuality: quality) { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                if encoded.count <= 1_500_000 { return encoded }
            }
        }
        return nil
    }

    private func invalidateRepair() {
        guard repairAttempt.isRunning else { return }
        repairAttempt.invalidate()
        loading = false
    }

    private func repairDraft() {
        guard !loading, !saving, let original = draft else { return }
        if store.settings.onDeviceOnly {
            store.show("Private mode is on - turn it off in Settings to use AI.", error: true)
            return
        }
        loading = true
        repairError = nil
        repairResult = nil
        let request = ParseRequest(mode: .rewrite, text: mode == .prompt ? prompt : nil,
            currentRecipe: original, repairQuality: true)
        repairAttempt.start(operation: {
            try await store.backend.parseRecipe(request)
        }, apply: { result in
            // Admission has already been rechecked after await. Also refuse
            // edits made during repair before any state or DraftStore write.
            guard draft == original else {
                throw BackendError(message: "Your draft changed during repair. The repair was not applied.")
            }
            let repaired = try RecipeDraftRepair.accept(result, replacing: original)
            repairResult = RepairFeedback.accepted(original: original, repaired: repaired)
            draft = repaired
            repairStatusRevision += 1
            didEdit = false
            confirmedDraft = false
            DraftStore.shared.saveDraft(repaired)
        }, failed: { error in
            repairError = error is CancellationError
                ? "Repair was cancelled. Your draft is unchanged. Try again."
                : error.localizedDescription
            repairStatusRevision += 1
        }, finished: {
            loading = false
        })
    }

    private func invalidateGeneration() {
        generationAttempt.invalidate()
        OnDeviceBackend.partialSink = nil
        live = nil
        loading = false
    }

    private func invalidateInputLoads() {
        photoInputAttempt.invalidate()
        coverInputAttempt.invalidate()
    }

    private func startGeneration() {
        guard !loading, !saving else { return }
        invalidateInputLoads()
        generationAttempt.start(timedOut: {
            loading = false
            OnDeviceBackend.partialSink = nil
            live = nil
            error = "Generation took too long. Your input and draft are unchanged. Try again."
            if draft != nil {
                repairError = error
                repairResult = nil
                repairStatusRevision += 1
            }
        }) { token in await generate(token: token) }
    }

    private func generate(token: UUID) async {
        // The UI disables generation while loading, but keep the lifecycle safe against rapid or programmatic duplicate taps.
        guard !loading else { return }
        if store.settings.onDeviceOnly {
            store.show("Private mode is on — turn it off in Settings to use AI.", error: true); return
        }
        let mode = self.mode
        let link = self.link
        let diagnostic = mode == .image ? PhotoImportDiagnostics.begin() : nil
        diagnostic?.mark(.generationStarted)
        var req: ParseRequest
        var recoveryImageData: Data?
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
            diagnostic?.mark(.imagePreparationStarted)
            let prepared = Self.prepareImage(d)
            // Preview and chooseInitialCover keep the original bytes. Only the request
            // and persisted recovery input use the bounded image.
            imageData = prepared.previewAndCover
            let jpeg = prepared.requestAndRecovery
            recoveryImageData = jpeg
            diagnostic?.mark(.imagePreparationCompleted)
            var dishes = spreadPicks.sorted()
            for d in dishAnswer.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !d.isEmpty && !dishes.contains(d) { dishes.append(d) }
            if dishQuestion != nil, let f = dishes.first { confirmedDish = f }
            req = ParseRequest(mode: .image, text: dishes.first, imageDataUrl: "data:image/jpeg;base64," + jpeg.base64EncodedString())
            if dishes.count > 1 {
                let rest = Array(dishes.dropFirst())
                let base = req
                generationAttempt.startChild(token) {
                    var saved = 0
                    for d in rest {
                        guard generationAttempt.isCurrent(token) else { return }
                        var r = base; r.text = d
                        if var c = try? await store.backend.parseRecipe(r) {
                            guard generationAttempt.isCurrent(token) else { return }
                            c.origin = .photo
                            store.add(RecipeLogic.normalize(c))
                            saved += 1
                        }
                    }
                    generationAttempt.publish(token) {
                        if saved > 0 { store.show("Saved \(saved) more card\(saved == 1 ? "" : "s") from the spread") }
                    }
                }
            }
        }
        diagnostic?.mark(.generationLoading)
        loading = true
        error = nil; socialError = nil; socialReason = nil
        live = nil
        OnDeviceBackend.partialSink = { p in _ = generationAttempt.publish(token) { live = p } }
        DraftStore.shared.begin(mode: mode.rawValue, text: mode == .link ? link : (mode == .prompt ? prompt : ""),
                                imageData: recoveryImageData)
        // Keep pending input on failure or while asking the user to identify an uncertain dish.
        // DraftStore.saveDraft clears it on success; Cancel/Discard clears it explicitly.
        defer {
            generationAttempt.publish(token) {
                loading = false; OnDeviceBackend.partialSink = nil; live = nil
                diagnostic?.mark(.generationFinished)
            }
        }
        do {
            let started = Date()
            var card = try await store.backend.parseRecipe(req)
            guard generationAttempt.isCurrent(token) else { return }
            diagnostic?.mark(.backendReturned)
            card.origin = mode == .link ? .link : (mode == .image ? .photo : .prompt)
            if mode == .link, let u = URL(string: link.trimmingCharacters(in: .whitespaces)) { card.sourceURL = SocialLinks.clean(u).absoluteString }
            GenerationLog.last = GenerationLog(source: card.source, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                                               mode: mode.rawValue, date: Date())
            let normalized = RecipeLogic.normalize(card)
            // C-AI-01: under 80% confidence the card is NOT presented as a recipe; ask "What dish is this?" with the
            // model's own guesses pre-filled. ≥ 80% skips the question entirely.
            if RecipeQuality.shouldAskDish(normalized, alreadyConfirmed: confirmedDish != nil) {
                diagnostic?.mark(.dishQuestion)
                let g = RecipeQuality.guesses(normalized)
                dishQuestion = PhotoNeedsDishError(suggestions: g, spread: false)
                dishAnswer = g.first ?? ""; spreadPicks = []
                Haptics.warning()
                return
            }
            draft = normalized
            diagnostic?.mark(.draftAssigned)
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
            guard generationAttempt.isCurrent(token) else { return }
            diagnostic?.mark(.generationFailed)
            socialError = e.platform
            socialReason = e.reason
            BetaQA.shared.pass("A-CREATE-02", note: "No caption on \(e.platform): friendly Prompt offer shown")
            Haptics.warning()
        } catch let e as PhotoNeedsDishError {
            guard generationAttempt.isCurrent(token) else { return }
            diagnostic?.mark(.dishQuestion)
            dishQuestion = e
            Haptics.warning()
        } catch is CancellationError {
            guard generationAttempt.isCurrent(token) else { return }
            diagnostic?.mark(.generationFailed)
            // Cancellation is a terminal attempt outcome, not a model failure. Keep the
            // persisted request so the user can retry without re-entering their input.
            self.error = Self.interruptedMessage
        } catch let e {
            guard generationAttempt.isCurrent(token) else { return }
            diagnostic?.mark(.generationFailed)
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
