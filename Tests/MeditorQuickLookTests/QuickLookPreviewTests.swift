import AppKit
import WebKit
import XCTest

@MainActor
final class QuickLookPreviewTests: XCTestCase {
    func testValidUnicodeSourceRendersOffline() async throws {
        let source = "flowchart LR\n    A[Olá] --> B[世界]\n"
        let controller = PreviewViewController()

        try await controller.preparePreviewOfFile(at: temporaryFile(source: source, extension: "mermaid"))

        let webView = try XCTUnwrap(firstSubview(of: WKWebView.self, in: controller.view))
        let html = try await evaluate("document.getElementById('diagram').innerHTML", in: webView)
        let interactive = try await evaluate("String(window.Meditor.metrics().interactive)", in: webView)
        XCTAssertTrue(html.contains("<svg"))
        XCTAssertEqual(interactive, "false")
    }

    func testInvalidSourceFallsBackToSourceCode() async throws {
        let source = "flowchart LR\n    A -->\n"
        let controller = PreviewViewController()

        try await controller.preparePreviewOfFile(at: temporaryFile(source: source))

        let textView = try XCTUnwrap(firstSubview(of: NSTextView.self, in: controller.view))
        XCTAssertEqual(textView.string, source)
    }

    func testEmptySourceFallsBackImmediately() async throws {
        let controller = PreviewViewController()

        try await controller.preparePreviewOfFile(at: temporaryFile(source: ""))

        let textView = try XCTUnwrap(firstSubview(of: NSTextView.self, in: controller.view))
        XCTAssertEqual(textView.string, "")
    }

    func testLargeSourceFitsQuickLookViewport() async throws {
        let edges = (0..<80).map { "    N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
        let controller = PreviewViewController()

        try await controller.preparePreviewOfFile(
            at: temporaryFile(source: "flowchart LR\n\(edges)\n")
        )

        let webView = try XCTUnwrap(firstSubview(of: WKWebView.self, in: controller.view))
        let metrics = try await evaluate("JSON.stringify(window.Meditor.metrics())", in: webView)
        let fits = try await evaluate(
            """
            String((() => {
              const m = window.Meditor.metrics();
              return m.displayedWidth <= m.viewportWidth && m.displayedHeight <= m.viewportHeight;
            })())
            """,
            in: webView
        )
        XCTAssertEqual(fits, "true", metrics)
    }

    func testQuickLookRendererResourcesAreOffline() throws {
        let bundle = Bundle(for: PreviewViewController.self)
        let htmlURL = try XCTUnwrap(bundle.url(forResource: "renderer", withExtension: "html"))
        let scriptURL = try XCTUnwrap(bundle.url(forResource: "mermaid", withExtension: "min.js"))
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("http://"))
    }

    private func temporaryFile(source: String, extension fileExtension: String = "mmd") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try Data(source.utf8).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        return view.subviews.lazy.compactMap { self.firstSubview(of: type, in: $0) }.first
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }
}
