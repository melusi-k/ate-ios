import SwiftUI

struct ProductRoadmapView: View {
    private let catalog = ProductRoadmapCatalog.load()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Help shape Ate").font(AteFont.display(26))
                Text("Read the ideas we're considering and the work in progress. Plans can change; these aren't release dates.")
                    .font(AteFont.body(16))
                Text(ProductRoadmapVoting.explanation).font(AteFont.body(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("roadmap.votingUnavailable")
                if let catalog {
                    if catalog.features.isEmpty {
                        Text("No roadmap features have been published yet.")
                            .font(AteFont.body(16)).accessibilityIdentifier("roadmap.empty")
                    }
                    ForEach(catalog.features) { feature in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(feature.status.title).font(AteFont.body(13, .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                                .accessibilityIdentifier("roadmap.status.\(feature.id)")
                            Text(feature.title).font(AteFont.display(20))
                            Text(feature.benefit).font(AteFont.body(16))
                            Button("Upvote") {}
                                .buttonStyle(.ate(.secondary, height: 44))
                                .disabled(!ProductRoadmapVoting.available)
                                .accessibilityHint(ProductRoadmapVoting.explanation)
                                .accessibilityIdentifier("roadmap.vote.\(feature.id)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(padding: 16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("roadmap.feature.\(feature.id)")
                    }
                } else {
                    Text("The roadmap couldn't be read. You can still use the rest of Ate.")
                        .font(AteFont.body(16)).accessibilityIdentifier("roadmap.unavailable")
                }
                Text(ProductRoadmapVoting.limits).font(AteFont.body(13))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(16).padding(.bottom, 96).pageWidth()
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground).tint(Theme.primary)
        .navigationTitle("Roadmap").navigationBarTitleDisplayMode(.inline)
    }
}
