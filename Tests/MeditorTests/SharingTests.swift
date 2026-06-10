import AppKit
import XCTest
@testable import Meditor

final class SharingTests: XCTestCase {
    private let sampleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
      <rect x="5" y="5" width="110" height="70" rx="12" fill="#39d1d8"/>
    </svg>
    """

    @MainActor
    func testSocialPreviewPNGIsFixed1200x630OpaqueCanvas() throws {
        let data = try ExportService.socialPreviewPNG(svg: sampleSVG)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 1200)
        XCTAssertEqual(bitmap.pixelsHigh, 630)
        // Corner is padding: opaque white background.
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(corner.alphaComponent, 1)
        XCTAssertEqual(corner.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(corner.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(corner.blueComponent, 1, accuracy: 0.01)
    }

    func testShareDurationMatchesServerAllowedList() {
        XCTAssertEqual(Set(ShareDuration.allCases.map(\.ttlSeconds)), [3600, 86_400, 604_800])
    }

    func testShareRequestEncodesContractKeys() throws {
        let request = ShareRequest(code: "flowchart TD\n A-->B", ogImage: "AAAA", ttlSeconds: 3600, theme: "forest")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertEqual(json?["ttlSeconds"] as? Int, 3600)
        XCTAssertEqual(json?["theme"] as? String, "forest")
        XCTAssertEqual(json?["ogImage"] as? String, "AAAA")
    }

    func testPublishedLinkExpiry() {
        let past = PublishedLink(id: "a", url: "u", createdAt: .now, expiresAt: .now.addingTimeInterval(-1))
        let future = PublishedLink(id: "b", url: "u", createdAt: .now, expiresAt: .now.addingTimeInterval(3600))
        XCTAssertTrue(past.isExpired)
        XCTAssertFalse(future.isExpired)
    }

    @MainActor
    func testPublishedLinkStorePersistsAddsAndPrunes() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PublishedLinkStore(fileURL: url)
        let live = PublishedLink(id: "live", url: "https://meditor.dev/s/live", createdAt: .now, expiresAt: .now.addingTimeInterval(3600))
        let dead = PublishedLink(id: "dead", url: "https://meditor.dev/s/dead", createdAt: .now, expiresAt: .now.addingTimeInterval(-1))
        store.add(live, deleteToken: "token-live")
        store.add(dead, deleteToken: "token-dead")
        XCTAssertEqual(store.links.count, 2)

        store.pruneExpired()
        XCTAssertEqual(store.links.map(\.id), ["live"])

        // Persistence: a fresh store over the same file sees the surviving link.
        let reloaded = PublishedLinkStore(fileURL: url)
        XCTAssertEqual(reloaded.links.map(\.id), ["live"])

        store.forget("live")
        XCTAssertTrue(store.links.isEmpty)
    }

    func testPublishErrorMessagesAreUserFacing() {
        XCTAssertNotNil(PublishError.offline.errorDescription)
        XCTAssertNotNil(PublishError.rateLimited.errorDescription)
        XCTAssertNotNil(PublishError.payloadTooLarge.errorDescription)
        XCTAssertNotNil(PublishError.server(status: 500).errorDescription)
    }
}
