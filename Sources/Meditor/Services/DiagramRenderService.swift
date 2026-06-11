import AppKit
import WebKit

@MainActor
final class DiagramRenderService {
    static let shared = DiagramRenderService()

    private let inbox: DiagramRenderMessageInbox
    private let webView: WKWebView
    private let window: NSWindow
    private var isReady = false
    private var requestID = 0
    private var isRendering = false
    private var renderWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        let inbox = DiagramRenderMessageInbox()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(inbox, name: "meditor")

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            configuration: configuration
        )
        let window = NSWindow(
            contentRect: webView.frame,
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

    func render(code: String, theme: MermaidTheme) async throws -> DiagramRenderResult {
        await acquireRenderSlot()
        defer {
            window.orderOut(nil)
            releaseRenderSlot()
        }

        window.orderFront(nil)
        try await prepareIfNeeded()
        requestID += 1
        let currentID = requestID
        let payload: [String: Any] = [
            "id": currentID,
            "code": code,
            "theme": theme.mermaidValue,
            "interactive": false,
            "clearOnError": true,
            "fitAfterRender": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DiagramRenderServiceError.invalidRequest
        }
        try await webView.evaluateJavaScript("window.Meditor.render(\(json)); true")
        let message = try await inbox.nextMessage(for: currentID)

        guard message["success"] as? Bool == true, let svg = message["svg"] as? String else {
            throw DiagramRenderServiceError.renderFailed(
                message["message"] as? String ?? String(localized: "Unable to render diagram")
            )
        }
        return DiagramRenderResult(svg: svg, analysis: Self.decodeAnalysis(message["analysis"]))
    }

    static func decodeAnalysis(_ value: Any?) -> DiagramAnalysis? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(DiagramAnalysis.self, from: data)
    }

    private func prepareIfNeeded() async throws {
        guard !isReady else { return }
        guard let rendererURL = RendererResources.htmlURL else {
            throw DiagramRenderServiceError.rendererUnavailable
        }
        webView.loadFileURL(rendererURL, allowingReadAccessTo: rendererURL.deletingLastPathComponent())
        try await inbox.waitUntilReady()
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
}

enum DiagramRenderServiceError: LocalizedError {
    case invalidRequest
    case rendererUnavailable
    case renderFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            String(localized: "The render request could not be prepared.")
        case .rendererUnavailable:
            String(localized: "The offline renderer is unavailable.")
        case let .renderFailed(message):
            message
        case .timedOut:
            String(localized: "Rendering timed out.")
        }
    }
}

@MainActor
private final class DiagramRenderMessageInbox: NSObject, WKScriptMessageHandler {
    private var isReady = false
    private var messages: [[String: Any]] = []
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var messageContinuation: CheckedContinuation<[String: Any], Error>?
    private var timeoutTask: Task<Void, Never>?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any] else { return }
        if payload["event"] as? String == "ready" {
            isReady = true
            readyContinuation?.resume()
            readyContinuation = nil
            timeoutTask?.cancel()
            return
        }
        if let continuation = messageContinuation {
            messageContinuation = nil
            timeoutTask?.cancel()
            continuation.resume(returning: payload)
        } else {
            messages.append(payload)
        }
    }

    func waitUntilReady() async throws {
        guard !isReady else { return }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            scheduleTimeout {
                guard let continuation = self.readyContinuation else { return }
                self.readyContinuation = nil
                continuation.resume(throwing: DiagramRenderServiceError.timedOut)
            }
        }
    }

    func nextMessage(for requestID: Int) async throws -> [String: Any] {
        while true {
            let message = try await nextMessage()
            if message["id"] as? Int == requestID {
                return message
            }
        }
    }

    private func nextMessage() async throws -> [String: Any] {
        if !messages.isEmpty {
            return messages.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            messageContinuation = continuation
            scheduleTimeout {
                guard let continuation = self.messageContinuation else { return }
                self.messageContinuation = nil
                continuation.resume(throwing: DiagramRenderServiceError.timedOut)
            }
        }
    }

    private func scheduleTimeout(_ action: @escaping @MainActor () -> Void) {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
