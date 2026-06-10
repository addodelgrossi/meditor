import Foundation

enum PublishError: LocalizedError, Equatable {
    case offline
    case rateLimited
    case payloadTooLarge
    case invalidResponse
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .offline:
            String(localized: "No internet connection. Connect and try again.")
        case .rateLimited:
            String(localized: "You're publishing too often. Wait a few minutes and try again.")
        case .payloadTooLarge:
            String(localized: "This diagram is too large to publish.")
        case .invalidResponse:
            String(localized: "The server returned an unexpected response.")
        case let .server(status):
            String(localized: "Publishing failed (error \(status)). Please try again.")
        }
    }
}

/// Talks to the meditor-cloud share API. The diagram source never leaves the
/// device except through an explicit publish.
@MainActor
struct PublishService {
    var baseURL: String = AppPreferences.shared.shareBaseURL
    var session: URLSession = .shared

    func publish(code: String, theme: MermaidTheme, svg: String, duration: ShareDuration) async throws -> ShareResponse {
        let png = try ExportService.socialPreviewPNG(svg: svg)
        let body = ShareRequest(
            code: code,
            ogImage: png.base64EncodedString(),
            ttlSeconds: duration.ttlSeconds,
            theme: theme.mermaidValue
        )

        var request = try makeRequest(path: "/api/v1/share", method: "POST")
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
        case 413:
            throw PublishError.payloadTooLarge
        case 429:
            throw PublishError.rateLimited
        default:
            throw PublishError.server(status: response.statusCode)
        }
    }

    func unpublish(id: String, deleteToken: String) async throws {
        var request = try makeRequest(path: "/api/v1/share/\(id)", method: "DELETE")
        request.setValue("Bearer \(deleteToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 204, 404:
            return // deleted, or already gone
        default:
            throw PublishError.server(status: response.statusCode)
        }
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw PublishError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
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
            || error.code == .timedOut {
            throw PublishError.offline
        }
    }

    private static let decoder: JSONDecoder = {
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
    private static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
