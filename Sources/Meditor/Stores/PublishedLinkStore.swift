import Foundation

/// Persists the list of diagrams the user has published. Metadata lives in a
/// JSON file in Application Support; each link's delete token lives in the
/// Keychain ([KeychainStore]).
@MainActor
final class PublishedLinkStore: ObservableObject {
    static let shared = PublishedLinkStore()

    @Published private(set) var links: [PublishedLink] = []

    private let fileURL: URL
    private let tokenStore: any DeleteTokenStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, tokenStore: any DeleteTokenStoring = KeychainStore()) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.tokenStore = tokenStore
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func add(_ link: PublishedLink, deleteToken: String) {
        tokenStore.setDeleteToken(deleteToken, for: link.id)
        links.removeAll { $0.id == link.id }
        links.insert(link, at: 0)
        save()
    }

    /// Remove a link from local history and forget its token. Does not call the
    /// server — see [ShareClient.unpublish].
    func forget(_ id: String) {
        tokenStore.removeDeleteToken(for: id)
        links.removeAll { $0.id == id }
        save()
    }

    func deleteToken(for id: String) -> String? {
        tokenStore.deleteToken(for: id)
    }

    /// Drop entries that have passed their expiry after an explicit user action.
    func clearExpired() {
        let expired = links.filter(\.isExpired)
        guard !expired.isEmpty else { return }
        for link in expired {
            tokenStore.removeDeleteToken(for: link.id)
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
        if data.range(of: Data("\"ttlSeconds\"".utf8)) == nil {
            save()
        }
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
