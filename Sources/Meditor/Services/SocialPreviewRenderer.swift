import AppKit
import WebKit

@MainActor
final class SocialPreviewRenderer {
    private let canvasSize = NSSize(width: 1200, height: 630)

    func render(code: String, theme: MermaidTheme) async throws -> Data {
        guard let rendererURL = RendererResources.htmlURL else {
            throw PublishError.invalidResponse
        }

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
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: rendererURL.deletingLastPathComponent())

        guard try await inbox.nextEvent() == .ready else {
            throw PublishError.invalidResponse
        }

        let payload: [String: Any] = [
            "id": 1,
            "code": code,
            "theme": theme.mermaidValue,
            "interactive": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PublishError.invalidRequest
        }
        try await evaluate("window.Meditor.render(\(json)); true", in: webView)

        switch try await inbox.nextEvent() {
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
        withExtendedLifetime(window) {}
        let png = try normalizedPNG(from: image)
        guard png.count <= ShareLimits.maximumOGImageBytes else {
            throw PublishError.payloadTooLarge
        }
        return png
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
        case rendered
        case failed
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
        } else if payload["success"] as? Bool == true {
            event = .rendered
        } else {
            event = .failed
        }

        if let continuation {
            finish(with: event, continuation: continuation)
        } else {
            queued.append(event)
        }
    }

    func nextEvent() async throws -> Event {
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
