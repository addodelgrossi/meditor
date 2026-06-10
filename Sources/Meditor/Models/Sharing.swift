import Foundation
import SwiftUI

enum ShareLimits {
    static let maximumCodeBytes = 50 * 1024
    static let maximumOGImageBytes = 500 * 1024
}

/// How long a published diagram stays online. Values mirror the closed list the
/// server accepts (see meditor-cloud API.md).
enum ShareDuration: Int, CaseIterable, Codable, Identifiable {
    case oneHour = 3600
    case oneDay = 86_400
    case oneWeek = 604_800

    var id: Int { rawValue }
    var ttlSeconds: Int { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .oneHour: "1 hour"
        case .oneDay: "24 hours"
        case .oneWeek: "7 days"
        }
    }
}

/// Request body for `POST /api/v1/share`. Encoded keys match the API contract.
struct ShareRequest: Codable, Equatable {
    let version = 1
    let code: String
    let ogImage: String
    let ttlSeconds: Int
    let theme: String

    enum CodingKeys: String, CodingKey {
        case version
        case code
        case ogImage
        case ttlSeconds
        case theme
    }
}

/// Response from a successful publish (`201`).
struct ShareResponse: Codable, Equatable {
    let id: String
    let url: String
    let expiresAt: Date
    let deleteToken: String
}

/// A diagram the user has published, persisted locally so they can revisit or
/// unpublish it. The delete token is kept in the Keychain, not here.
struct PublishedLink: Codable, Identifiable, Equatable {
    let id: String
    let url: String
    let createdAt: Date
    let expiresAt: Date
    let ttlSeconds: Int

    var isExpired: Bool { expiresAt <= Date() }

    init(id: String, url: String, createdAt: Date, expiresAt: Date, ttlSeconds: Int) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.ttlSeconds = ttlSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case createdAt
        case expiresAt
        case ttlSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        ttlSeconds = try container.decodeIfPresent(Int.self, forKey: .ttlSeconds)
            ?? Self.inferredTTL(createdAt: createdAt, expiresAt: expiresAt)
    }

    private static func inferredTTL(createdAt: Date, expiresAt: Date) -> Int {
        let interval = Int(expiresAt.timeIntervalSince(createdAt).rounded())
        return ShareDuration.allCases.min {
            abs($0.ttlSeconds - interval) < abs($1.ttlSeconds - interval)
        }?.ttlSeconds ?? ShareDuration.oneDay.ttlSeconds
    }
}
