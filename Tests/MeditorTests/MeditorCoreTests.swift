import AppKit
import XCTest
@testable import Meditor

final class MeditorCoreTests: XCTestCase {
    func testDocumentUTF8RoundTrip() throws {
        let source = "flowchart LR\n    A[Olá] --> B[世界]\n"
        let encoded = try MermaidDocument(text: source).encodedData()
        let decoded = try MermaidDocument(data: encoded)

        XCTAssertEqual(decoded.text, source)
    }

    @MainActor
    func testEveryTemplateHasUniqueIdentifierAndSource() {
        XCTAssertEqual(MermaidTemplate.all.count, 8)
        XCTAssertEqual(Set(MermaidTemplate.all.map(\.id)).count, MermaidTemplate.all.count)
        XCTAssertTrue(MermaidTemplate.all.allSatisfy { !$0.source.isEmpty })
    }

    @MainActor
    func testLineRangeLocatesSyntaxErrorLine() {
        let source = "flowchart LR\n    A --> B\n    B --> C" as NSString
        let range = MermaidSyntaxHighlighter.range(ofLine: 2, in: source)

        XCTAssertEqual(range.map { source.substring(with: $0) }, "    A --> B\n")
    }

    @MainActor
    func testExportCreatesSVGPNGAndPDF() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
          <rect x="5" y="5" width="110" height="70" rx="12" fill="#39d1d8"/>
        </svg>
        """

        let svgData = try ExportService.data(svg: svg, format: .svg, scale: .one)
        let pngData = try ExportService.data(svg: svg, format: .png, scale: .two)
        let opaquePNGData = try ExportService.data(
            svg: svg,
            format: .png,
            scale: .one,
            transparentBackground: false
        )
        let pdfData = try ExportService.data(svg: svg, format: .pdf, scale: .one)

        XCTAssertTrue(String(data: svgData, encoding: .utf8)?.contains("<svg") == true)
        XCTAssertEqual(Array(pngData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(NSBitmapImageRep(data: pngData)?.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(NSBitmapImageRep(data: opaquePNGData)?.colorAt(x: 0, y: 0)?.alphaComponent, 1)
        XCTAssertTrue(String(data: pdfData.prefix(4), encoding: .ascii) == "%PDF")
    }

    @MainActor
    func testStaleRenderResultIsDiscarded() {
        let store = RenderStore()
        store.scheduleRender(code: "flowchart LR\nA-->B", theme: .default)
        store.handle(message: [
            "id": 1,
            "success": true,
            "svg": "<svg id=\"first\"/>",
            "diagramType": "flowchart-v2",
            "width": 100.0,
            "height": 50.0
        ])
        store.scheduleRender(code: "flowchart LR\nA-->C", theme: .default)
        store.handle(message: [
            "id": 1,
            "success": false,
            "message": "stale error"
        ])

        XCTAssertEqual(store.lastSVG, "<svg id=\"first\"/>")
        XCTAssertNil(store.error)
    }

    func testRendererResourcesAreBundledAndOffline() throws {
        let htmlURL = try XCTUnwrap(RendererResources.htmlURL)
        let scriptURL = try XCTUnwrap(RendererResources.mermaidJavaScriptURL)
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("http://"))
        XCTAssertTrue(html.contains("securityLevel: \"strict\""))
    }
}
