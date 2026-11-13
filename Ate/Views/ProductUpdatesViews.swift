import SwiftUI

private struct ProductPage<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16, content: content)
                .padding(16).padding(.bottom, 96).pageWidth()
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground).tint(Theme.primary)
    }
}

struct ProductReleaseNotesView: View {
    private let catalog = ProductUpdatesCatalog.load()
    var body: some View {
        ProductPage {
            if let catalog {
                let releases = catalog.visibleReleases(build: Int(AppConfig.buildNumber) ?? 0,
                                                        channel: AppConfig.isBetaBuild ? "beta" : "release")
                if releases.isEmpty { Text("Release notes are not available for this build yet.") }
                ForEach(releases) { release in
                    NavigationLink { ProductReleaseDetailView(release: release) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(release.title).font(AteFont.display(20))
                            Text("Version \(release.version)" + (release.channel == "beta" ? " · Beta" : ""))
                                .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                            Text(release.summary).font(AteFont.body(16))
                        }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 16)
                    }.buttonStyle(.plain).accessibilityIdentifier("release.\(release.id)")
                }
            } else {
                Text("Release notes could not be read. You can still use the rest of Ate.")
                    .accessibilityIdentifier("releases.unavailable")
            }
        }.navigationTitle("Release Notes").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProductReleaseDetailView: View {
    let release: ProductRelease
    @State private var showingSlides = false
    var body: some View {
        ProductPage {
            Text(release.title).font(AteFont.display(26))
            Text("Version \(release.version)" + (release.channel == "beta" ? " · Beta" : "")).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            Text(release.summary).font(AteFont.body(16))
            ForEach([ProductRelease.Change.Kind.added, .improved, .fixed], id: \.rawValue) { kind in
                let changes = release.changes.filter { $0.kind == kind }
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(kind.rawValue.capitalized).font(AteFont.display(20))
                        ForEach(changes.indices, id: \.self) { index in
                            Text(changes[index].text).font(AteFont.body(16))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 16)
                }
            }
            if !release.slides.isEmpty {
                Button("View What's New") { showingSlides = true }
                    .buttonStyle(.ate(.primary, height: 48))
                    .accessibilityIdentifier("release.whatsNew")
            }
        }.navigationTitle("Release details").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSlides) { ProductWhatsNewView(release: release) }
    }
}

struct ProductWhatsNewView: View {
    let release: ProductRelease
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if release.slides.isEmpty {
                    Text("There is no tour for this release.")
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(release.slides.enumerated()), id: \.element.id) { index, slide in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    if let image = UIImage(named: slide.imageAsset) {
                                        Image(uiImage: image).resizable().scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                                            .accessibilityLabel(slide.imageAlt)
                                    } else {
                                        Label("Image unavailable", systemImage: "photo")
                                            .foregroundStyle(Theme.mutedForeground)
                                    }
                                    if slide.placeholder {
                                        Text("Placeholder illustration, not an app screenshot")
                                            .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                                            .accessibilityIdentifier("whatsNew.placeholder")
                                    }
                                    Text(slide.title).font(AteFont.display(24))
                                    Text(slide.body).font(AteFont.body(16))
                                }.padding(16)
                            }.tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                    HStack {
                        Button("Back") { page = max(0, page - 1) }
                            .frame(minWidth: 44, minHeight: 44).disabled(page == 0)
                        Spacer()
                        Text("\(page + 1) of \(release.slides.count)").font(AteFont.body(13))
                            .accessibilityIdentifier("whatsNew.page")
                        Spacer()
                        Button(page == release.slides.count - 1 ? "Done" : "Next") {
                            if page == release.slides.count - 1 { dismiss() } else { page += 1 }
                        }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("whatsNew.next")
                    }.padding(16)
                }
            }.background(Theme.background.ignoresSafeArea()).foregroundStyle(Theme.foreground)
                .tint(Theme.primary).navigationTitle("What's New").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("whatsNew.close")
                } }
        }
    }
}
