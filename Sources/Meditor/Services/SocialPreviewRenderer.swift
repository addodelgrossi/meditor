import AppKit
import WebKit

@MainActor
final class SocialPreviewRenderer {
    // WebKit may still own autoreleased objects after a snapshot completes.
    // Keep one engine alive instead of tearing down its window for every share.
    private static let engine = SocialPreviewRenderEngine()

    func render(code: String, theme: MermaidTheme) async throws -> Data {
        try await Self.engine.render(code: code, theme: theme)
    }
}

@MainActor
private final class SocialPreviewRenderEngine {
    private let canvasSize = NSSize(width: 1200, height: 630)
    private let inbox: SocialPreviewMessageInbox
    private let webView: WKWebView
    private let window: NSWindow
    private var isReady = false
    private var requestID = 0
    private var isRendering = false
    private var renderWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let inbox = SocialPreviewMessageInbox()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(inbox, name: "meditor")

        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: canvasSize),
            configuration: configuration
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))

        webView.setValue(false, forKey: "drawsBackground")

        self.inbox = inbox
        self.webView = webView
        self.window = window
    }

    func render(code: String, theme: MermaidTheme) async throws -> Data {
        await acquireRenderSlot()
        defer {
            window.orderOut(nil)
            releaseRenderSlot()
        }

        window.orderFront(nil)
        try await prepareIfNeeded()
        requestID += 1
        let currentRequestID = requestID

        let payload: [String: Any] = [
            "id": currentRequestID,
            "code": code,
            "theme": theme.mermaidValue,
            "interactive": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PublishError.invalidRequest
        }
        try await evaluate("window.Meditor.render(\(json)); true", in: webView)

        switch try await inbox.nextEvent(for: currentRequestID) {
        case .rendered:
            break
        case .ready:
            throw PublishError.invalidResponse
        case .failed:
            throw PublishError.invalidRequest
        }

        try await evaluate(
            """
            (() => {
            document.documentElement.style.colorScheme = "light";
            document.documentElement.style.background = "white";
            document.body.style.background = "white";
            window.Meditor.fit();
            return true;
            })()
            """,
            in: webView
        )
        webView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        let image = try await snapshot(webView)
        let png = try normalizedPNG(from: image)
        guard png.count <= ShareLimits.maximumOGImageBytes else {
            throw PublishError.payloadTooLarge
        }
        return png
    }

    private func prepareIfNeeded() async throws {
        guard !isReady else { return }
        guard let rendererURL = RendererResources.htmlURL else {
            throw PublishError.invalidResponse
        }
        webView.loadFileURL(rendererURL, allowingReadAccessTo: rendererURL.deletingLastPathComponent())
        guard try await inbox.nextEvent(for: nil) == .ready else {
            throw PublishError.invalidResponse
        }
        isReady = true
    }

    private func acquireRenderSlot() async {
        guard isRendering else {
            isRendering = true
            return
        }
        await withCheckedContinuation { continuation in
            renderWaiters.append(continuation)
        }
    }

    private func releaseRenderSlot() {
        guard !renderWaiters.isEmpty else {
            isRendering = false
            return
        }
        renderWaiters.removeFirst().resume()
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(script)
    }

    private func snapshot(_ webView: WKWebView) async throws -> NSImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(origin: .zero, size: canvasSize)
        return try await webView.takeSnapshot(configuration: configuration)
    }

    private func normalizedPNG(from image: NSImage) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw PublishError.invalidResponse
        }
        bitmap.size = canvasSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.draw(
            in: NSRect(origin: .zero, size: canvasSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PublishError.invalidResponse
        }
        return png
    }
}

@MainActor
private final class SocialPreviewMessageInbox: NSObject, WKScriptMessageHandler {
    enum Event: Equatable {
        case ready
        case rendered(Int)
        case failed(Int)
    }

    private var queued: [Event] = []
    private var continuation: CheckedContinuation<Event, Error>?
    private var timeoutTask: Task<Void, Never>?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any] else { return }
        let event: Event
        if payload["event"] as? String == "ready" {
            event = .ready
        } else if let id = payload["id"] as? Int, payload["success"] as? Bool == true {
            event = .rendered(id)
        } else if let id = payload["id"] as? Int {
            event = .failed(id)
        } else {
            return
        }

        if let continuation {
            finish(with: event, continuation: continuation)
        } else {
            queued.append(event)
        }
    }

    func nextEvent(for requestID: Int?) async throws -> Event {
        while true {
            let event = try await nextEvent()
            switch (requestID, event) {
            case (nil, .ready):
                return event
            case let (id?, .rendered(eventID)) where id == eventID:
                return event
            case let (id?, .failed(eventID)) where id == eventID:
                return event
            default:
                continue
            }
        }
    }

    private func nextEvent() async throws -> Event {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let continuation = self.continuation else { return }
                self.continuation = nil
                continuation.resume(throwing: PublishError.invalidResponse)
            }
        }
    }

    private func finish(with event: Event, continuation: CheckedContinuation<Event, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        self.continuation = nil
        continuation.resume(returning: event)
    }
}
