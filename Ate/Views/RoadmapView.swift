import SwiftUI

private struct RoadmapPage<Content: View>: View {
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

@MainActor
struct RoadmapView: View {
    private let catalog: RoadmapCatalog?
    @State private var votes: RoadmapVotes

    init(catalog: RoadmapCatalog? = RoadmapCatalog.load()) {
        self.catalog = catalog
        _votes = State(initialValue: RoadmapVotes(cards: catalog?.cards ?? []))
    }

    var body: some View {
        RoadmapPage {
            Text("Help shape Ate").font(AteFont.display(26))
            Text("Save the ideas you would like to see. Your vote is a local preference on this iPhone only. It is not sent to us and is not a community total.")
                .font(AteFont.body(16)).accessibilityIdentifier("roadmap.localOnly")
            Text("Available offline. Ideas and statuses come with this app version; plans may change and no dates are promised.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            if let error = votes.error, catalog != nil {
                Text(error).font(AteFont.body(16)).accessibilityIdentifier("roadmap.localVotesError")
            }
            if let catalog {
                if catalog.cards.isEmpty {
                    Text("There are no roadmap ideas in this app version yet.")
                        .accessibilityIdentifier("roadmap.empty")
                }
                ForEach(catalog.cards) { card in
                    NavigationLink { RoadmapDetailView(card: card, votes: votes) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.title).font(AteFont.display(20))
                            Text(card.statusLabel).font(AteFont.body(13, .semibold))
                            Text(card.summary).font(AteFont.body(16))
                            Text(votes.contains(card.id) ? "Your local vote is saved" : "View idea")
                                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .cardSurface(padding: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(card.title), \(card.statusLabel). \(card.summary)")
                    .accessibilityValue(votes.error != nil ? "Local preference unavailable" : (votes.contains(card.id) ? "Local vote saved on this iPhone" : "No local vote"))
                    .accessibilityHint("Opens idea details and the local vote button")
                    .accessibilityIdentifier("roadmap.card.\(card.id)")
                }
            } else {
                Text("The bundled roadmap could not be read. Voting is unavailable. You can still use the rest of Ate.")
                    .accessibilityIdentifier("roadmap.unavailable")
            }
        }
        .navigationTitle("Roadmap").navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct RoadmapDetailView: View {
    let card: RoadmapCard
    let votes: RoadmapVotes
    var body: some View {
        RoadmapPage {
            Text(card.title).font(AteFont.display(26))
                .accessibilityIdentifier("roadmap.detail.title")
            Text(card.statusLabel).font(AteFont.body(14, .semibold))
            Text(card.detail).font(AteFont.body(16))
            Text("Your vote stays on this iPhone only. It is not submitted to Ate. There are no community vote totals here.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            if let error = votes.error {
                Text(error).font(AteFont.body(16))
                    .accessibilityIdentifier("roadmap.votesUnavailable")
            }
            Button(votes.contains(card.id) ? "Remove local vote" : "Vote on this iPhone") {
                votes.toggle(card.id)
            }
            .buttonStyle(.ate(.primary, height: 48, full: true))
            .disabled(votes.error != nil)
            .accessibilityLabel(votes.contains(card.id) ? "Remove local vote for \(card.title)" : "Save local vote for \(card.title)")
            .accessibilityValue(votes.error != nil ? "Local preference unavailable" : (votes.contains(card.id) ? "Local vote saved" : "No local vote"))
            .accessibilityHint("Changes only your preference on this iPhone; nothing is sent")
            .accessibilityIdentifier("roadmap.vote.\(card.id)")
            if votes.error == nil {
                Text(votes.contains(card.id) ? "Local vote saved on this iPhone." : "No local vote saved for this idea.")
                    .font(AteFont.body(14)).accessibilityIdentifier("roadmap.voteStatus")
            }
        }
        .navigationTitle("Idea details").navigationBarTitleDisplayMode(.inline)
    }
}
