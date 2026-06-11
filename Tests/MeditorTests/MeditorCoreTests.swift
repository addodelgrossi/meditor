import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Meditor

final class MeditorCoreTests: XCTestCase {
    func testAppAppearanceColorSchemes() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testInvalidAppAppearanceFallsBackToSystem() {
        XCTAssertEqual(AppAppearance.resolved("invalid"), .system)
    }

    func testDocumentUTF8RoundTrip() throws {
        let source = "flowchart LR\n    A[Olá] --> B[世界]\n"
        let encoded = try MermaidDocument(text: source).encodedData()
        let decoded = try MermaidDocument(data: encoded)

        XCTAssertEqual(decoded.text, source)
    }

    @MainActor
    func testEveryTemplateHasUniqueIdentifierAndSource() {
        XCTAssertEqual(MermaidTemplate.all.count, 9)
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
            background: .light
        )
        let pdfData = try ExportService.data(svg: svg, format: .pdf, scale: .one)

        XCTAssertTrue(String(data: svgData, encoding: .utf8)?.contains("<svg") == true)
        XCTAssertEqual(Array(pngData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(NSBitmapImageRep(data: pngData)?.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(NSBitmapImageRep(data: opaquePNGData)?.colorAt(x: 0, y: 0)?.alphaComponent, 1)
        XCTAssertEqual(NSBitmapImageRep(data: pngData)?.pixelsWide, 240)
        XCTAssertEqual(NSBitmapImageRep(data: pngData)?.pixelsHigh, 160)
        XCTAssertTrue(String(data: pdfData.prefix(4), encoding: .ascii) == "%PDF")
    }

    @MainActor
    func testExportAppliesLightAndDarkBackgroundsToRasterAndSVG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
          <circle cx="10" cy="5" r="2" fill="#39d1d8"/>
        </svg>
        """

        let lightPNG = try ExportService.data(svg: svg, format: .png, scale: .one, background: .light)
        let darkPNG = try ExportService.data(svg: svg, format: .png, scale: .one, background: .dark)
        let lightSVG = try ExportService.data(svg: svg, format: .svg, scale: .one, background: .light)
        let darkSVG = try ExportService.data(svg: svg, format: .svg, scale: .one, background: .dark)

        let lightPixel = try XCTUnwrap(NSBitmapImageRep(data: lightPNG)?.colorAt(x: 0, y: 0))
        XCTAssertEqual(lightPixel.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(lightPixel.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(lightPixel.blueComponent, 1, accuracy: 0.01)
        let darkPixel = try XCTUnwrap(NSBitmapImageRep(data: darkPNG)?.colorAt(x: 0, y: 0))
        XCTAssertEqual(darkPixel.redComponent, 0x11 / 255, accuracy: 0.01)
        XCTAssertEqual(darkPixel.greenComponent, 0x13 / 255, accuracy: 0.01)
        XCTAssertEqual(darkPixel.blueComponent, 0x18 / 255, accuracy: 0.01)
        XCTAssertTrue(String(decoding: lightSVG, as: UTF8.self).contains("fill=\"#FFFFFF\""))
        XCTAssertTrue(String(decoding: darkSVG, as: UTF8.self).contains("fill=\"#111318\""))
    }

    @MainActor
    func testCopyImagePublishesRichImageRepresentationsWithoutText() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
          <rect width="20" height="10" fill="#39d1d8"/>
        </svg>
        """

        try ExportService.copyImage(svg, scale: .two, background: .transparent)

        let types = try XCTUnwrap(NSPasteboard.general.pasteboardItems?.first?.types)
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.tiff))
        XCTAssertTrue(types.contains(.pdf))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType(UTType.svg.identifier)))
        XCTAssertFalse(types.contains(.string))
    }

    func testExportThemePresetsAndLegacyBackgroundMigration() {
        XCTAssertEqual(ExportThemePreset.current.resolved(currentTheme: .forest), .forest)
        XCTAssertEqual(ExportThemePreset.light.resolved(currentTheme: .forest), .default)
        XCTAssertEqual(ExportThemePreset.dark.resolved(currentTheme: .forest), .dark)
        XCTAssertEqual(ExportBackground.resolved(nil, legacyTransparent: true), .transparent)
        XCTAssertEqual(ExportBackground.resolved(nil, legacyTransparent: false), .light)
        XCTAssertEqual(ExportBackground.resolved("dark", legacyTransparent: true), .dark)
    }

    func testPresentationPositionStopsAtDeckBoundaries() {
        var position = PresentationPosition(count: 2)

        position.goPrevious()
        XCTAssertEqual(position.index, 0)
        position.goNext()
        position.goNext()
        XCTAssertEqual(position.index, 1)
        XCTAssertFalse(position.canGoNext)
        XCTAssertTrue(position.canGoPrevious)
    }

    func testPresentationDeckMovesAndRemovesSlides() {
        var deck = PresentationDeck(
            slides: [
                PresentationSlide(title: "A", code: "flowchart LR\nA"),
                PresentationSlide(title: "B", code: "flowchart LR\nB"),
                PresentationSlide(title: "C", code: "flowchart LR\nC"),
            ],
            theme: .dark
        )

        deck.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(deck.slides.map(\.title), ["B", "C", "A"])
        deck.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(deck.slides.map(\.title), ["B", "A"])
    }

    func testPresentationDeckLoaderReadsFilesOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Architecture.mmd")
        try Data("flowchart LR\nA-->B".utf8).write(to: url)

        let slides = try PresentationDeckLoader.slides(from: [url])
        try Data("flowchart LR\nA-->C".utf8).write(to: url)

        XCTAssertEqual(slides.first?.title, "Architecture")
        XCTAssertEqual(slides.first?.code, "flowchart LR\nA-->B")
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
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testDistributionResourcesAreBundled() throws {
        let privacy = Bundle.meditorResources.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")

        XCTAssertNotNil(privacy)
        XCTAssertTrue(LegalResources.licenseText.contains("Copyright (c) 2026 Addo Del Grossi"))
        XCTAssertTrue(LegalResources.licenseText.contains("MIT License"))
    }
}
