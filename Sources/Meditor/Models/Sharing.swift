import Foundation
import SwiftUI

/// How long a published diagram stays online. Values mirror the closed list the
/// server accepts (see meditor-cloud API.md).
enum ShareDuration: Int, CaseIterable, Identifiable {
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
struct ShareRequest: Encodable {
    let version = 1
    let code: String
    let ogImage: String
    let ttlSeconds: Int
    let theme: String
}

/// Response from a successful publish (`201`).
struct ShareResponse: Decodable {
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

    var isExpired: Bool { expiresAt <= Date() }
}
