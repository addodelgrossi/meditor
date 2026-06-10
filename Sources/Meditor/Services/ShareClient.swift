import Foundation

enum PublishError: LocalizedError, Equatable {
    case offline
    case invalidBaseURL
    case invalidRequest
    case unauthorized
    case rateLimited
    case payloadTooLarge
    case invalidResponse
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .offline:
            String(localized: "No internet connection. Connect and try again.")
        case .invalidBaseURL:
            String(localized: "Enter a valid HTTPS service URL.")
        case .invalidRequest:
            String(localized: "The diagram could not be published. Check it and try again.")
        case .unauthorized:
            String(localized: "This link could not be unpublished.")
        case .rateLimited:
            String(localized: "Too many publishes, try again in a few minutes.")
        case .payloadTooLarge:
            String(localized: "The diagram or preview image is too large to publish.")
        case .invalidResponse:
            String(localized: "The server returned an unexpected response.")
        case .server:
            String(localized: "The publish service is unavailable. Please try again.")
        }
    }
}

/// Talks to the meditor-cloud share API. The diagram source never leaves the
/// device except through an explicit publish.
@MainActor
struct ShareClient {
    let baseURL: ShareServiceURL
    var session: URLSession

    init(
        baseURL: ShareServiceURL? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? AppPreferences.shared.shareServiceURL
        self.session = session
    }

    func publish(code: String, theme: MermaidTheme, ogImage: Data, duration: ShareDuration) async throws -> ShareResponse {
        guard !code.isEmpty else {
            throw PublishError.invalidRequest
        }
        guard code.utf8.count <= ShareLimits.maximumCodeBytes else {
            throw PublishError.payloadTooLarge
        }
        guard ogImage.count <= ShareLimits.maximumOGImageBytes else {
            throw PublishError.payloadTooLarge
        }
        let body = ShareRequest(
            code: code,
            ogImage: ogImage.base64EncodedString(),
            ttlSeconds: duration.ttlSeconds,
            theme: theme.mermaidValue
        )

        var request = makeRequest(path: "api/v1/share", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 201:
            do {
                return try Self.decoder.decode(ShareResponse.self, from: data)
            } catch {
                throw PublishError.invalidResponse
            }
        case 400:
            throw PublishError.invalidRequest
        case 413:
            throw PublishError.payloadTooLarge
        case 429:
            throw PublishError.rateLimited
        default:
            throw PublishError.server(status: response.statusCode)
        }
    }

    func unpublish(id: String, deleteToken: String) async throws {
        var request = makeRequest(path: "api/v1/share/\(id)", method: "DELETE")
        request.setValue("Bearer \(deleteToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 204, 404:
            return // deleted, or already gone
        case 401, 403:
            throw PublishError.unauthorized
        default:
            throw PublishError.server(status: response.statusCode)
        }
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 15)
        request.httpMethod = method
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PublishError.invalidResponse
            }
            return (data, http)
        } catch let error as PublishError {
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .cannotConnectToHost
            || error.code == .cannotFindHost
            || error.code == .dnsLookupFailed
            || error.code == .timedOut {
            throw PublishError.offline
        } catch {
            throw PublishError.invalidResponse
        }
    }

    nonisolated private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseISO8601(string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(string)")
            )
        }
        return decoder
    }()

    /// Parse an ISO-8601 timestamp, with or without fractional seconds (the
    /// server emits milliseconds). Formatters are created locally because
    /// ISO8601DateFormatter is not Sendable.
    nonisolated private static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
