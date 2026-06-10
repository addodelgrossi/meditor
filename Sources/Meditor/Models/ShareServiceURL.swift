import Foundation

struct ShareServiceURL: Equatable, Sendable {
    static let defaultValue = "https://meditor.dev"
    static let defaultService = ShareServiceURL(url: URL(string: defaultValue)!)

    let url: URL

    private init(url: URL) {
        self.url = url
    }

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw PublishError.invalidBaseURL
        }

        let localHosts = ["localhost", "127.0.0.1", "::1", "[::1]"]
        guard scheme == "https" || (scheme == "http" && localHosts.contains(host)) else {
            throw PublishError.invalidBaseURL
        }

        components.scheme = scheme
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        guard let normalized = components.url else {
            throw PublishError.invalidBaseURL
        }
        url = normalized
    }

    init(publishedLink: String) throws {
        guard let publishedURL = URL(string: publishedLink),
              var components = URLComponents(url: publishedURL, resolvingAgainstBaseURL: false) else {
            throw PublishError.invalidBaseURL
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        try self.init(components.string ?? "")
    }

    var string: String { url.absoluteString }

    func appending(path: String) -> URL {
        url.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
