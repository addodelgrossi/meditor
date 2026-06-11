import Combine
import Foundation
import WebKit

@MainActor
final class RenderStore: ObservableObject {
    @Published private(set) var isRendering = false
    @Published private(set) var error: MermaidRenderError?
    @Published private(set) var info: MermaidRenderInfo?
    @Published private(set) var lastSVG: String?
    @Published private(set) var successfulSignature: String?

    private weak var webView: WKWebView?
    private var isReady = false
    private var pendingTask: Task<Void, Never>?
    private var requestID = 0
    private var lastSignature = ""
    private var pendingCode = ""
    private var pendingTheme = MermaidTheme.default
    private let purpose: RenderPurpose

    init(purpose: RenderPurpose = .editor) {
        self.purpose = purpose
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func webViewDidBecomeReady() {
        isReady = true
        if pendingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearCanvas()
        } else {
            dispatchPendingRender()
        }
    }

    func scheduleRender(code: String, theme: MermaidTheme) {
        let signature = Self.signature(code: code, theme: theme)
        guard signature != lastSignature else { return }
        lastSignature = signature
        pendingCode = code
        pendingTheme = theme
        requestID += 1
        let currentID = requestID

        pendingTask?.cancel()
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRendering = false
            error = nil
            info = nil
            lastSVG = nil
            successfulSignature = nil
            clearCanvas()
            return
        }

        isRendering = true
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, currentID == self.requestID else { return }
            self.dispatchPendingRender()
        }
    }

    func handle(message: [String: Any]) {
        guard let id = message["id"] as? Int, id == requestID else { return }
        isRendering = false

        if message["success"] as? Bool == true {
            guard let svg = message["svg"] as? String else { return }
            lastSVG = svg
            successfulSignature = Self.signature(code: pendingCode, theme: pendingTheme)
            error = nil
            info = MermaidRenderInfo(
                diagramType: message["diagramType"] as? String ?? "diagram",
                width: message["width"] as? Double ?? 0,
                height: message["height"] as? Double ?? 0
            )
        } else {
            error = MermaidRenderError(
                message: message["message"] as? String ?? String(localized: "Unable to render diagram"),
                line: message["line"] as? Int,
                column: message["column"] as? Int
            )
        }
    }

    func zoomIn() {
        evaluate("window.Meditor?.zoomBy(1.15)")
    }

    func zoomOut() {
        evaluate("window.Meditor?.zoomBy(0.87)")
    }

    func fit() {
        evaluate("window.Meditor?.fit()")
    }

    func canPublish(code: String, theme: MermaidTheme) -> Bool {
        hasCurrentRender(code: code, theme: theme)
    }

    func hasCurrentRender(code: String, theme: MermaidTheme) -> Bool {
        !isRendering
            && error == nil
            && lastSVG != nil
            && successfulSignature == Self.signature(code: code, theme: theme)
    }

    private func dispatchPendingRender() {
        guard isReady,
              !pendingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let webView else { return }
        let payload: [String: Any] = [
            "id": requestID,
            "code": pendingCode,
            "theme": pendingTheme.mermaidValue,
            "interactive": purpose.interactive,
            "highlightable": purpose.highlightable,
            "clearOnError": purpose.clearOnError,
            "fitAfterRender": purpose.fitAfterRender,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.Meditor.render(\(json))")
    }

    private func clearCanvas() {
        evaluate("window.Meditor?.clear()")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private static func signature(code: String, theme: MermaidTheme) -> String {
        "\(theme.rawValue)\u{0}\(code)"
    }
}
