import Foundation

/// Persists the list of diagrams the user has published. Metadata lives in a
/// JSON file in Application Support; each link's delete token lives in the
/// Keychain ([KeychainStore]).
@MainActor
final class PublishedLinkStore: ObservableObject {
    static let shared = PublishedLinkStore()

    @Published private(set) var links: [PublishedLink] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func add(_ link: PublishedLink, deleteToken: String) {
        KeychainStore.setDeleteToken(deleteToken, for: link.id)
        links.removeAll { $0.id == link.id }
        links.insert(link, at: 0)
        save()
    }

    /// Remove a link from local history and forget its token. Does not call the
    /// server — see [PublishService.unpublish].
    func forget(_ id: String) {
        KeychainStore.removeDeleteToken(for: id)
        links.removeAll { $0.id == id }
        save()
    }

    func deleteToken(for id: String) -> String? {
        KeychainStore.deleteToken(for: id)
    }

    /// Drop entries that have passed their expiry; their server data is already
    /// gone via KV TTL.
    func pruneExpired() {
        let expired = links.filter(\.isExpired)
        guard !expired.isEmpty else { return }
        for link in expired {
            KeychainStore.removeDeleteToken(for: link.id)
        }
        links.removeAll(where: \.isExpired)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? decoder.decode([PublishedLink].self, from: data) else {
            return
        }
        links = stored.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? encoder.encode(links) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Meditor", isDirectory: true)
            .appendingPathComponent("published-links.json")
    }
}
