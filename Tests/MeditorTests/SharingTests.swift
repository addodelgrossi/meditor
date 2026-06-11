import AppKit
import XCTest
@testable import Meditor

@MainActor
final class SharingTests: XCTestCase {
    private let sampleCode = "flowchart LR\nA --> B"
    private let samplePNG = Data([137, 80, 78, 71, 13, 10, 26, 10])

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testShareDurationMatchesServerAllowedList() {
        XCTAssertEqual(Set(ShareDuration.allCases.map(\.ttlSeconds)), [3600, 86_400, 604_800])
    }

    func testShareRequestEncodesAndDecodesContractKeys() throws {
        let request = ShareRequest(code: sampleCode, ogImage: "AAAA", ttlSeconds: 3600, theme: "forest")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["code"] as? String, sampleCode)
        XCTAssertEqual(json["ttlSeconds"] as? Int, 3600)
        XCTAssertEqual(json["theme"] as? String, "forest")
        XCTAssertEqual(json["ogImage"] as? String, "AAAA")
        XCTAssertEqual(try JSONDecoder().decode(ShareRequest.self, from: data), request)
    }

    func testShareServiceURLValidationAndNormalization() throws {
        XCTAssertEqual(try ShareServiceURL(" https://meditor.dev/ ").string, "https://meditor.dev")
        XCTAssertEqual(try ShareServiceURL("http://localhost:8787/").string, "http://localhost:8787")
        XCTAssertEqual(try ShareServiceURL("http://127.0.0.1:8787").string, "http://127.0.0.1:8787")
        XCTAssertEqual(try ShareServiceURL("http://[::1]:8787").string, "http://[::1]:8787")
        XCTAssertThrowsError(try ShareServiceURL("http://meditor.dev"))
        XCTAssertThrowsError(try ShareServiceURL("ftp://meditor.dev"))
        XCTAssertThrowsError(try ShareServiceURL("https://meditor.dev?token=secret"))

        let previous = AppPreferences.shared.shareBaseURL
        defer { AppPreferences.shared.shareBaseURL = previous }
        AppPreferences.shared.shareBaseURL = "invalid"
        XCTAssertEqual(AppPreferences.shared.shareServiceURL, .defaultService)
    }

    func testPublishedLinkMigrationInfersTTL() throws {
        let oldData = Data(
            """
            [{
              "id": "old",
              "url": "https://meditor.dev/s/old",
              "createdAt": "2026-06-10T12:00:00Z",
              "expiresAt": "2026-06-11T12:00:00Z"
            }]
            """.utf8
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try oldData.write(to: url)

        let store = PublishedLinkStore(fileURL: url, tokenStore: InMemoryDeleteTokenStore())
        XCTAssertEqual(store.links.first?.ttlSeconds, ShareDuration.oneDay.ttlSeconds)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("ttlSeconds"))
    }

    func testPublishedLinkStorePersistsMetadataWithoutTokensAndKeepsExpiredLinks() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let tokens = InMemoryDeleteTokenStore()
        let store = PublishedLinkStore(fileURL: url, tokenStore: tokens)
        let live = makeLink(id: "live", expiresIn: 3600)
        let dead = makeLink(id: "dead", expiresIn: -1)

        store.add(live, deleteToken: "token-live")
        store.add(dead, deleteToken: "token-dead")
        XCTAssertEqual(store.links.count, 2)
        XCTAssertEqual(store.deleteToken(for: "live"), "token-live")

        let persisted = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persisted.contains("token-live"))
        XCTAssertFalse(persisted.contains("token-dead"))
        XCTAssertTrue(persisted.contains("ttlSeconds"))

        let reloaded = PublishedLinkStore(fileURL: url, tokenStore: tokens)
        XCTAssertEqual(Set(reloaded.links.map(\.id)), ["live", "dead"])
        reloaded.clearExpired()
        XCTAssertEqual(reloaded.links.map(\.id), ["live"])
        XCTAssertNil(tokens.deleteToken(for: "dead"))
    }

    func testPublishClientUsesContractAndDecodesResponse() async throws {
        let session = makeMockSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/root/api/v1/share")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 15)
            let body = try self.bodyData(from: request)
            let decoded = try JSONDecoder().decode(ShareRequest.self, from: body)
            XCTAssertEqual(decoded.code, self.sampleCode)
            XCTAssertEqual(decoded.theme, "dark")
            XCTAssertEqual(decoded.ttlSeconds, 3600)
            XCTAssertEqual(Data(base64Encoded: decoded.ogImage), self.samplePNG)
            return self.response(
                for: request,
                status: 201,
                body: """
                {"id":"abc","url":"https://example.com/s/abc","expiresAt":"2026-06-10T18:00:00.000Z","deleteToken":"secret"}
                """
            )
        }

        let client = ShareClient(baseURL: try ShareServiceURL("https://example.com/root"), session: session)
        let result = try await client.publish(
            code: sampleCode,
            theme: .dark,
            ogImage: samplePNG,
            duration: .oneHour
        )
        XCTAssertEqual(result.id, "abc")
        XCTAssertEqual(result.url, "https://example.com/s/abc")
        XCTAssertEqual(result.deleteToken, "secret")
    }

    func testDefaultPublishClientUsesChangedPreferenceBaseURL() async throws {
        let previous = AppPreferences.shared.shareBaseURL
        defer { AppPreferences.shared.shareBaseURL = previous }
        AppPreferences.shared.shareBaseURL = "https://self-hosted.example"
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://self-hosted.example/api/v1/share")
            return self.response(
                for: request,
                status: 201,
                body: """
                {"id":"abc","url":"https://self-hosted.example/s/abc","expiresAt":"2026-06-10T18:00:00Z","deleteToken":"secret"}
                """
            )
        }

        _ = try await ShareClient(session: makeMockSession()).publish(
            code: sampleCode,
            theme: .default,
            ogImage: samplePNG,
            duration: .oneDay
        )
    }

    func testPublishClientMapsStatusCodes() async throws {
        let expected: [(Int, PublishError)] = [
            (400, .invalidRequest),
            (413, .payloadTooLarge),
            (429, .rateLimited),
            (500, .server(status: 500)),
        ]
        for (status, expectedError) in expected {
            MockURLProtocol.handler = { request in self.response(for: request, status: status) }
            let error = await publishError(using: makeMockSession())
            XCTAssertEqual(error, expectedError)
        }
    }

    func testPublishClientMapsOfflineError() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let error = await publishError(using: makeMockSession())
        XCTAssertEqual(error, .offline)
    }

    func testUnpublishUsesBearerTokenAndTreats404AsSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://self-hosted.example/api/v1/share/abc")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer delete-secret")
            return self.response(for: request, status: 404)
        }
        let baseURL = try ShareServiceURL(publishedLink: "https://self-hosted.example/s/abc")
        try await ShareClient(baseURL: baseURL, session: makeMockSession())
            .unpublish(id: "abc", deleteToken: "delete-secret")
    }

    func testPublishClientRejectsOversizedPayloadsBeforeNetwork() async throws {
        MockURLProtocol.handler = { _ in XCTFail("Network should not be called"); throw URLError(.badURL) }
        let client = ShareClient(baseURL: try ShareServiceURL("https://meditor.dev"), session: makeMockSession())

        let codeError = await capturedPublishError {
            _ = try await client.publish(
                code: String(repeating: "a", count: ShareLimits.maximumCodeBytes + 1),
                theme: .default,
                ogImage: self.samplePNG,
                duration: .oneDay
            )
        }
        XCTAssertEqual(codeError, .payloadTooLarge)

        let imageError = await capturedPublishError {
            _ = try await client.publish(
                code: self.sampleCode,
                theme: .default,
                ogImage: Data(count: ShareLimits.maximumOGImageBytes + 1),
                duration: .oneDay
            )
        }
        XCTAssertEqual(imageError, .payloadTooLarge)
    }

    func testSocialPreviewRendererCreatesRepeatedFixedOpaquePNGsWithinLimit() async throws {
        let renderer = SocialPreviewRenderer()
        for theme in [MermaidTheme.forest, .dark, .default] {
            let data = try await renderer.render(code: sampleCode, theme: theme)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 1200)
            XCTAssertEqual(bitmap.pixelsHigh, 630)
            XCTAssertLessThanOrEqual(data.count, ShareLimits.maximumOGImageBytes)
            let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(corner.alphaComponent, 1)
            XCTAssertEqual(corner.redComponent, 1, accuracy: 0.01)
            XCTAssertEqual(corner.greenComponent, 1, accuracy: 0.01)
            XCTAssertEqual(corner.blueComponent, 1, accuracy: 0.01)
        }
    }

    func testSocialPreviewRendererSerializesConcurrentRequests() async throws {
        let renderer = SocialPreviewRenderer()
        let flowchart = sampleCode
        async let first = renderer.render(code: flowchart, theme: .forest)
        async let second = renderer.render(code: "sequenceDiagram\nA->>B: Hello", theme: .dark)
        async let third = renderer.render(code: "classDiagram\nA <|-- B", theme: .default)

        for data in try await [first, second, third] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 1200)
            XCTAssertEqual(bitmap.pixelsHigh, 630)
            XCTAssertLessThanOrEqual(data.count, ShareLimits.maximumOGImageBytes)
        }
    }

    func testRenderStoreOnlyPublishesCurrentSuccessfulRender() {
        let store = RenderStore()
        store.scheduleRender(code: sampleCode, theme: .default)
        XCTAssertFalse(store.canPublish(code: sampleCode, theme: .default))

        store.handle(message: [
            "id": 1,
            "success": true,
            "svg": "<svg/>",
            "diagramType": "flowchart-v2",
            "width": 100.0,
            "height": 50.0,
        ])
        XCTAssertTrue(store.canPublish(code: sampleCode, theme: .default))
        XCTAssertFalse(store.canPublish(code: sampleCode, theme: .dark))

        let invalidCode = "flowchart LR\nA -->"
        store.scheduleRender(code: invalidCode, theme: .default)
        XCTAssertFalse(store.canPublish(code: invalidCode, theme: .default))
        store.handle(message: ["id": 2, "success": false, "message": "invalid"])
        XCTAssertFalse(store.canPublish(code: invalidCode, theme: .default))
    }

    private func makeLink(id: String, expiresIn interval: TimeInterval) -> PublishedLink {
        PublishedLink(
            id: id,
            url: "https://meditor.dev/s/\(id)",
            createdAt: .now,
            expiresAt: .now.addingTimeInterval(interval),
            ttlSeconds: ShareDuration.oneHour.ttlSeconds
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(for request: URLRequest, status: Int, body: String = "") -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            throw CocoaError(.fileReadUnknown)
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            guard count >= 0 else { throw stream.streamError ?? CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func publishError(using session: URLSession) async -> PublishError? {
        await capturedPublishError {
            let client = ShareClient(baseURL: try ShareServiceURL("https://meditor.dev"), session: session)
            _ = try await client.publish(
                code: self.sampleCode,
                theme: .default,
                ogImage: self.samplePNG,
                duration: .oneDay
            )
        }
    }

    private func capturedPublishError(_ operation: () async throws -> Void) async -> PublishError? {
        do {
            try await operation()
            return nil
        } catch let error as PublishError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}

private final class InMemoryDeleteTokenStore: DeleteTokenStoring {
    private var tokens: [String: String] = [:]

    func setDeleteToken(_ token: String, for id: String) {
        tokens[id] = token
    }

    func deleteToken(for id: String) -> String? {
        tokens[id]
    }

    func removeDeleteToken(for id: String) {
        tokens[id] = nil
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
