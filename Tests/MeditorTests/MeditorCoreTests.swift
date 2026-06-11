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

    func testWelcomeRecentDocumentsFiltersMissingDuplicatesAndLimitsResults() {
        let urls = (1...7).map {
            URL(fileURLWithPath: "/tmp/diagram-\($0).mmd")
        }
        let results = WelcomeDocumentLibrary.recentDocuments(
            from: [urls[0], urls[1], urls[0], urls[2], urls[3], urls[4], urls[5], urls[6]],
            fileExists: { $0 != urls[2].path }
        )

        XCTAssertEqual(results, [urls[0], urls[1], urls[3], urls[4], urls[5]])
    }

    @MainActor
    func testLineRangeLocatesSyntaxErrorLine() {
        let source = "flowchart LR\n    A --> B\n    B --> C" as NSString
        let range = MermaidSyntaxHighlighter.range(ofLine: 2, in: source)

        XCTAssertEqual(range.map { source.substring(with: $0) }, "    A --> B\n")
    }

    @MainActor
    func testEditorEnablesNativeFindBarAndIncrementalSearch() {
        let textView = NSTextView()

        MermaidTextEditor.configureFind(in: textView)

        XCTAssertTrue(textView.usesFindBar)
        XCTAssertTrue(textView.isIncrementalSearchingEnabled)
    }

    @MainActor
    func testEditorCommandAppliesAsOneUndoOperation() {
        let textView = NSTextView()
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [], backing: .buffered, defer: false)
        window.contentView = textView
        textView.allowsUndo = true
        textView.string = "flowchart LR\nA --> B"

        MermaidTextEditor.apply(
            MermaidEditorCommand(
                replacementText: "flowchart LR\nStart --> B",
                actionName: "Rename Diagram Identifier"
            ),
            to: textView
        )
        textView.undoManager?.undo()

        XCTAssertEqual(textView.string, "flowchart LR\nA --> B")
    }

    func testMarkdownBlockUsesFenceLongerThanSourceBackticks() {
        let source = "flowchart LR\nA[```code```] --> B"
        let block = DiagramSourceTools.markdownBlock(for: source)

        XCTAssertTrue(block.hasPrefix("````mermaid\n"))
        XCTAssertTrue(block.hasSuffix("\n````"))
        XCTAssertTrue(block.contains(source))
    }

    func testAnalysisCodableRoundTrip() throws {
        let analysis = DiagramAnalysis(
            diagramType: "flowchart-v2",
            elementCount: 2,
            connectionCount: 1,
            outline: [
                DiagramOutlineItem(
                    id: "node:A",
                    identifier: "A",
                    title: "Alpha",
                    kind: .node,
                    children: [],
                    line: 2
                )
            ],
            connections: [
                DiagramConnection(id: "edge:0", from: "A", to: "B", label: nil)
            ],
            issues: []
        )

        let decoded = try JSONDecoder().decode(
            DiagramAnalysis.self,
            from: JSONEncoder().encode(analysis)
        )

        XCTAssertEqual(decoded, analysis)
    }

    func testFlowchartAnalysisFindsDeclarationsAndWarningsWithoutCountingReferences() {
        let source = """
        flowchart LR
          A[First] --> B[Second]
          A --> B
          A[Duplicate]
          C[Alone]
        """
        let analysis = DiagramSourceTools.enrich(
            DiagramAnalysis(
                diagramType: "flowchart-v2",
                elementCount: 3,
                connectionCount: 2,
                outline: [
                    outlineItem("A", kind: .node),
                    outlineItem("B", kind: .node),
                    outlineItem("C", kind: .node),
                ],
                connections: [
                    DiagramConnection(id: "1", from: "A", to: "B", label: nil),
                    DiagramConnection(id: "2", from: "A", to: "B", label: nil),
                ],
                issues: []
            ),
            source: source
        )

        XCTAssertNil(analysis.item(id: "node:A")?.line)
        XCTAssertEqual(analysis.item(id: "node:B")?.line, 2)
        XCTAssertEqual(analysis.item(id: "node:C")?.line, 5)
        XCTAssertEqual(analysis.issues.filter { $0.kind == .duplicateIdentifier }.map(\.id), ["duplicate:A"])
        XCTAssertEqual(analysis.issues.filter { $0.kind == .disconnectedElement }.map(\.id), ["disconnected:C"])
    }

    func testSequenceWarningsIgnoreRepeatedMessageReferences() {
        let source = """
        sequenceDiagram
          participant A
          participant B
          participant C
          A->>B: A asks B
          B-->>A: B answers A
        """
        let analysis = DiagramSourceTools.enrich(
            DiagramAnalysis(
                diagramType: "sequence",
                elementCount: 3,
                connectionCount: 2,
                outline: [
                    outlineItem("A", kind: .participant),
                    outlineItem("B", kind: .participant),
                    outlineItem("C", kind: .participant),
                ],
                connections: [
                    DiagramConnection(id: "1", from: "A", to: "B", label: "A asks B"),
                    DiagramConnection(id: "2", from: "B", to: "A", label: "B answers A"),
                ],
                issues: []
            ),
            source: source
        )

        XCTAssertTrue(analysis.issues.filter { $0.kind == .duplicateIdentifier }.isEmpty)
        XCTAssertEqual(analysis.issues.filter { $0.kind == .disconnectedElement }.map(\.id), ["disconnected:C"])
    }

    func testSequenceCreateParticipantIsNavigableDeclaration() {
        let source = """
        sequenceDiagram
          participant A
          create participant B
          A->>B: Start
        """
        let analysis = DiagramSourceTools.enrich(
            DiagramAnalysis(
                diagramType: "sequence",
                elementCount: 2,
                connectionCount: 1,
                outline: [
                    outlineItem("A", kind: .participant),
                    outlineItem("B", kind: .participant),
                ],
                connections: [
                    DiagramConnection(id: "1", from: "A", to: "B", label: "Start")
                ],
                issues: []
            ),
            source: source
        )

        XCTAssertEqual(analysis.item(id: "participant:B")?.line, 3)
    }

    func testRenamePreservesLabelsCommentsAndSequenceMessageText() throws {
        let flowchart = """
        flowchart LR
          A[Label A] --> B
          %% A remains in a comment
          B --> A
        """
        let flowPlan = try DiagramSourceTools.renamePlan(
            source: flowchart,
            diagramType: "flowchart-v2",
            item: outlineItem("A", kind: .node),
            newIdentifier: "Start"
        )
        XCTAssertTrue(flowPlan.source.contains("Start[Label A] --> B"))
        XCTAssertTrue(flowPlan.source.contains("B --> Start"))
        XCTAssertTrue(flowPlan.source.contains("%% A remains in a comment"))
        XCTAssertEqual(flowPlan.replacementCount, 2)

        let sequence = """
        sequenceDiagram
          participant A as Alice
          participant B
          A->>B: A stays in message text
        """
        let sequencePlan = try DiagramSourceTools.renamePlan(
            source: sequence,
            diagramType: "sequence",
            item: outlineItem("A", kind: .participant),
            newIdentifier: "Client"
        )
        XCTAssertTrue(sequencePlan.source.contains("participant Client as Alice"))
        XCTAssertTrue(sequencePlan.source.contains("Client->>B: A stays in message text"))
        XCTAssertEqual(sequencePlan.replacementCount, 2)
    }

    func testRenameRejectsExistingIdentifier() {
        XCTAssertThrowsError(
            try DiagramSourceTools.renamePlan(
                source: "flowchart LR\nA --> B",
                diagramType: "flowchart-v2",
                item: outlineItem("A", kind: .node),
                newIdentifier: "B"
            )
        ) { error in
            XCTAssertEqual(error as? DiagramSourceTools.RenameError, .identifierAlreadyExists)
        }
    }

    func testHyphenatedIdentifiersAreNotConfusedWithArrowEndpoints() throws {
        let source = "flowchart LR\nA-B[Compound] --> B[Simple]"
        let analysis = DiagramSourceTools.enrich(
            DiagramAnalysis(
                diagramType: "flowchart-v2",
                elementCount: 2,
                connectionCount: 1,
                outline: [
                    outlineItem("A-B", kind: .node),
                    outlineItem("B", kind: .node),
                ],
                connections: [
                    DiagramConnection(id: "1", from: "A-B", to: "B", label: nil)
                ],
                issues: []
            ),
            source: source
        )

        XCTAssertEqual(analysis.item(id: "node:B")?.line, 2)
        XCTAssertTrue(analysis.issues.filter { $0.kind == .duplicateIdentifier }.isEmpty)

        let plan = try DiagramSourceTools.renamePlan(
            source: source,
            diagramType: "flowchart-v2",
            item: outlineItem("B", kind: .node),
            newIdentifier: "End"
        )
        XCTAssertEqual(plan.source, "flowchart LR\nA-B[Compound] --> End[Simple]")
        XCTAssertEqual(plan.replacementCount, 1)
    }

    @MainActor
    func testBatchExportCreatesAndReplacesFiveThemeFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinations = ExportService.batchURLs(
            directory: directory,
            suggestedName: "Diagram/Test",
            format: .svg
        )
        XCTAssertEqual(destinations.count, 5)
        XCTAssertEqual(
            destinations.map(\.url.lastPathComponent),
            ["Diagram-Test-default.svg", "Diagram-Test-neutral.svg", "Diagram-Test-dark.svg", "Diagram-Test-forest.svg", "Diagram-Test-base.svg"]
        )

        try ExportService.writeBatch(destinations.map { ($0.url, Data($0.theme.rawValue.utf8)) })
        try ExportService.writeBatch(destinations.map { ($0.url, Data("updated-\($0.theme.rawValue)".utf8)) })

        for destination in destinations {
            XCTAssertEqual(
                try String(contentsOf: destination.url, encoding: .utf8),
                "updated-\(destination.theme.rawValue)"
            )
        }
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

    @MainActor
    func testQuickCopyUsesTwoTimesOpaqueBackgroundAndRichRepresentations() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
          <circle cx="10" cy="5" r="2" fill="#39d1d8"/>
        </svg>
        """

        try ExportService.copyImageForSharing(svg, theme: .default)

        let item = try XCTUnwrap(NSPasteboard.general.pasteboardItems?.first)
        let png = try XCTUnwrap(item.data(forType: .png))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let background = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertEqual(bitmap.pixelsWide, 40)
        XCTAssertEqual(bitmap.pixelsHigh, 20)
        XCTAssertEqual(background.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(background.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(background.blueComponent, 1, accuracy: 0.01)
        XCTAssertTrue(item.types.contains(.tiff))
        XCTAssertTrue(item.types.contains(.pdf))
        XCTAssertTrue(item.types.contains(NSPasteboard.PasteboardType(UTType.svg.identifier)))
        XCTAssertFalse(item.types.contains(.string))
    }

    @MainActor
    func testQuickCopyBackgroundTracksVisibleTheme() {
        XCTAssertEqual(ExportService.sharingBackground(for: .dark), .dark)
        XCTAssertEqual(ExportService.sharingBackground(for: .default), .light)
        XCTAssertEqual(ExportService.sharingBackground(for: .forest), .light)
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

    @MainActor
    func testRenderStoreKeepsLastSuccessfulThemeAfterInvalidSource() {
        let store = RenderStore()
        store.scheduleRender(code: "flowchart LR\nA-->B", theme: .dark)
        store.handle(message: [
            "id": 1,
            "success": true,
            "svg": "<svg id=\"valid\"/>",
            "diagramType": "flowchart-v2",
            "width": 100.0,
            "height": 50.0
        ])
        store.scheduleRender(code: "flowchart LR\nA-->", theme: .forest)
        store.handle(message: [
            "id": 2,
            "success": false,
            "message": "invalid"
        ])

        XCTAssertEqual(store.lastSVG, "<svg id=\"valid\"/>")
        XCTAssertEqual(store.lastSuccessfulTheme, .dark)
    }

    @MainActor
    func testRenderStoreClearsAnalysisAsSoonAsSourceChanges() {
        let store = RenderStore()
        store.scheduleRender(code: "flowchart LR\nA-->B", theme: .default)
        store.handle(message: [
            "id": 1,
            "success": true,
            "svg": "<svg/>",
            "diagramType": "flowchart-v2",
            "width": 100.0,
            "height": 50.0,
            "analysis": [
                "diagramType": "flowchart-v2",
                "elementCount": 2,
                "connectionCount": 1,
                "outline": [],
                "connections": [],
                "issues": [],
            ],
        ])
        XCTAssertNotNil(store.analysis)

        store.scheduleRender(code: "flowchart LR\nA-->", theme: .default)

        XCTAssertNil(store.analysis)
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

    private func outlineItem(_ identifier: String, kind: DiagramOutlineKind) -> DiagramOutlineItem {
        DiagramOutlineItem(
            id: "\(kind.rawValue):\(identifier)",
            identifier: identifier,
            title: identifier,
            kind: kind,
            children: [],
            line: nil
        )
    }
}
