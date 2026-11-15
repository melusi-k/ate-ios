import Foundation

struct ProductUpdatesCatalog: Decodable {
    let schemaVersion: Int
    let releases: [ProductRelease]

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1,
              Set(value.releases.map(\.id)).count == value.releases.count,
              value.releases.allSatisfy({ release in
                  !release.id.isEmpty && !release.title.isEmpty && !release.version.isEmpty && !release.summary.isEmpty &&
                  (release.buildNumber == nil || release.buildNumber == release.minimumBuild) &&
                  release.minimumBuild >= 0 && ["all", "beta", "release"].contains(release.channel) &&
                  release.slides.count <= 5 && Set(release.slides.map(\.id)).count == release.slides.count &&
                  release.changes.allSatisfy({ !$0.text.isEmpty }) &&
                  release.slides.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.body.isEmpty && !$0.imageAlt.isEmpty })
              }) else { throw CatalogError.invalid }
        return value
    }

    enum CatalogError: Error { case invalid }
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ProductUpdates"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
    func publishedBuildReleases(build: Int, channel: String) -> [ProductRelease] {
        visibleReleases(build: build, channel: channel).filter { $0.buildNumber != nil }
    }
    func visibleReleases(build: Int, channel: String) -> [ProductRelease] {
        releases.filter { $0.minimumBuild <= build && ($0.channel == "all" || $0.channel == channel) }
            .sorted { $0.minimumBuild == $1.minimumBuild ? $0.id > $1.id : $0.minimumBuild > $1.minimumBuild }
    }
}
struct ProductRelease: Decodable, Identifiable {
    struct Change: Decodable {
        enum Kind: String, Decodable, Hashable { case added, improved, fixed }
        let kind: Kind
        let text: String
    }
    struct Slide: Decodable, Identifiable {
        let id: String
        let imageAsset: String
        let imageAlt: String
        let title: String
        let body: String
        let placeholder: Bool
    }
    let id: String
    let title: String
    let version: String
    let buildNumber: Int?
    let minimumBuild: Int
    let channel: String
    let summary: String
    let changes: [Change]
    let slides: [Slide]
}
