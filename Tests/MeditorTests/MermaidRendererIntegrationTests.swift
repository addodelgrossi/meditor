import AppKit
import WebKit
import XCTest
@testable import Meditor

@MainActor
final class MermaidRendererIntegrationTests: XCTestCase {
    func testAllBundledTemplatesRenderOffline() async throws {
        let (webView, inbox) = try makeRenderer()
        _ = await inbox.nextMessage()

        for (index, template) in MermaidTemplate.all.enumerated() {
            try render(
                template.source,
                id: index + 1,
                in: webView
            )
            let message = await inbox.nextMessage()
            XCTAssertEqual(message["success"] as? Bool, true, "\(template.id): \(message)")
            XCTAssertNotNil(message["svg"] as? String)
        }
    }

    func testInvalidSourceReturnsStructuredError() async throws {
        let (webView, inbox) = try makeRenderer()
        _ = await inbox.nextMessage()

        try render("flowchart LR\nA -->", id: 42, in: webView)
        let message = await inbox.nextMessage()

        XCTAssertEqual(message["id"] as? Int, 42)
        XCTAssertEqual(message["success"] as? Bool, false)
        XCTAssertFalse((message["message"] as? String ?? "").isEmpty)
        XCTAssertNotNil(message["line"] as? Int)
    }

    func testInvalidSourceKeepsLastValidPreview() async throws {
        let (webView, inbox) = try makeRenderer()
        _ = await inbox.nextMessage()

        try render("flowchart LR\nA --> B", id: 1, in: webView)
        let validMessage = await inbox.nextMessage()
        XCTAssertEqual(validMessage["success"] as? Bool, true)
        let validHTML = try await diagramHTML(in: webView)

        try render("flowchart LR\nA -->", id: 2, in: webView)
        let invalidMessage = await inbox.nextMessage()
        XCTAssertEqual(invalidMessage["success"] as? Bool, false)
        let afterErrorHTML = try await diagramHTML(in: webView)

        XCTAssertEqual(afterErrorHTML, validHTML)
    }

    func testLargeDiagramFitsViewportWithoutDoubleScaling() async throws {
        let (webView, inbox) = try makeRenderer()
        _ = await inbox.nextMessage()

        try render(Self.largeFlowchart, id: 7, in: webView)
        let message = await inbox.nextMessage()
        XCTAssertEqual(message["success"] as? Bool, true)

        let metrics = try await rendererMetrics(in: webView)

        XCTAssertGreaterThan(metrics.displayedWidth, metrics.viewportWidth * 0.70)
        XCTAssertLessThanOrEqual(metrics.displayedWidth, metrics.viewportWidth)
        XCTAssertEqual(metrics.displayedWidth, metrics.naturalWidth * metrics.scale, accuracy: 1)

        if let snapshotPath = ProcessInfo.processInfo.environment["MEDITOR_RENDER_SNAPSHOT"] {
            try await snapshotPNGData(of: webView).write(to: URL(fileURLWithPath: snapshotPath))
        }
    }

    private func makeRenderer() throws -> (WKWebView, MessageInbox) {
        let url = try XCTUnwrap(RendererResources.htmlURL)
        let inbox = MessageInbox()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(inbox, name: "meditor")
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return (webView, inbox)
    }

    private func render(_ source: String, id: Int, in webView: WKWebView) throws {
        let payload: [String: Any] = ["id": id, "code": source, "theme": "default"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        webView.evaluateJavaScript("window.Meditor.render(\(json))")
    }

    private func diagramHTML(in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.getElementById('diagram').innerHTML") { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }

    private func rendererMetrics(in webView: WKWebView) async throws -> RendererMetrics {
        let json: String = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("JSON.stringify(window.Meditor.metrics())") { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "{}")
                }
            }
        }
        return try JSONDecoder().decode(RendererMetrics.self, from: Data(json.utf8))
    }

    private func snapshotPNGData(of webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tiff = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    return
                }
                continuation.resume(returning: png)
            }
        }
    }

    private static let largeFlowchart = """
    flowchart TB
      subgraph HAVE["✅ Já entregue (consumível)"]
        RES["CalendarResolver (seam)"]
        BCL["BusinessCalendar.Elapsed/Deadline"]
        ST["SlaTimer (servicedesk) existe, só populado por import"]
      end
      subgraph SLAI["🟡 módulo sla — NÃO existe ainda"]
        ENG["Motor de consumo avança consumed_ms só em horário comercial"]
        SUB["Assinante de ticket.transitioned pausa via Status.pauses_sla"]
        POL["SlaPolicy — matriz de metas por prioridade (deferido)"]
      end
      subgraph MONI["🔴 módulo monitoring — Fase 2"]
        COL["Collector Sophos events+alerts → BigQuery"]
        ALM["Motor de alarmes / Incident"]
        GATE["Portão de cobertura suprime incidente fora da janela"]
        MW["MaintenanceWindow"]
      end
      RES --> ENG
      BCL --> ENG
      ENG --> SUB
      SUB --> ST
      RES --> GATE
      COL --> ALM --> GATE
      GATE --> MW
    """
}

private struct RendererMetrics: Codable, Sendable {
    let scale: Double
    let naturalWidth: Double
    let naturalHeight: Double
    let displayedWidth: Double
    let displayedHeight: Double
    let viewportWidth: Double
    let viewportHeight: Double
}

@MainActor
private final class MessageInbox: NSObject, WKScriptMessageHandler {
    private var queued: [[String: Any]] = []
    private var continuations: [CheckedContinuation<[String: Any], Never>] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any] else { return }
        if continuations.isEmpty {
            queued.append(payload)
        } else {
            continuations.removeFirst().resume(returning: payload)
        }
    }

    func nextMessage() async -> [String: Any] {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
