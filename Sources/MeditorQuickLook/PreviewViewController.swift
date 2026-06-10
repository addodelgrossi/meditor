import AppKit
import QuickLookUI
import WebKit

@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let messageHandlerName = "meditor"
    private var requestID = 0
    private var webView: WKWebView?
    private var isRendererReady = false
    private var pendingSource: String?
    private var pendingFileName = ""
    private var completion: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        preferredContentSize = view.frame.size
        showLoadingView()
        loadRenderer()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        pendingFileName = url.lastPathComponent

        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            showSourceFallback(
                source: "",
                title: localized("Unable to read Mermaid document"),
                detail: localized("The file is not valid UTF-8 text.")
            )
            return
        }

        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSourceFallback(
                source: source,
                title: localized("Empty Mermaid document"),
                detail: localized("This document does not contain a diagram yet.")
            )
            return
        }

        requestID += 1
        pendingSource = source
        showLoadingView()
        loadRenderer()

        await withCheckedContinuation { continuation in
            completion = continuation
            scheduleTimeout(source: source, requestID: requestID)
            dispatchRenderIfReady()
        }
    }

    private func loadRenderer() {
        guard webView == nil else { return }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isTextInteractionEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        guard let rendererURL = Bundle(for: Self.self).url(forResource: "renderer", withExtension: "html") else {
            showSourceFallback(
                source: pendingSource ?? "",
                title: localized("Unable to render Mermaid preview"),
                detail: localized("The offline renderer is unavailable. Showing source instead.")
            )
            finishPreparation()
            return
        }

        webView.loadFileURL(rendererURL, allowingReadAccessTo: rendererURL.deletingLastPathComponent())
    }

    private func dispatchRenderIfReady() {
        guard isRendererReady, let source = pendingSource, let webView else { return }

        let payload: [String: Any] = [
            "id": requestID,
            "code": source,
            "theme": mermaidTheme,
            "interactive": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            showSourceFallback(
                source: source,
                title: localized("Unable to render Mermaid preview"),
                detail: localized("The preview request could not be prepared. Showing source instead.")
            )
            finishPreparation()
            return
        }

        showWebView(webView)
        webView.evaluateJavaScript("window.Meditor.render(\(json))")
    }

    private func handleRendererMessage(_ payload: [String: Any]) {
        if payload["event"] as? String == "ready" {
            isRendererReady = true
            dispatchRenderIfReady()
            return
        }

        guard completion != nil, payload["id"] as? Int == requestID else { return }
        if payload["success"] as? Bool == true {
            finishPreparation()
            return
        }

        let message = payload["message"] as? String ?? localized("The diagram contains invalid Mermaid syntax.")
        let detail: String
        if let line = payload["line"] as? Int {
            detail = String(
                format: localized("Line %d: %@ Showing source instead."),
                line,
                message
            )
        } else {
            detail = "\(message) \(localized("Showing source instead."))"
        }
        showSourceFallback(
            source: pendingSource ?? "",
            title: localized("Unable to render Mermaid preview"),
            detail: detail
        )
        finishPreparation()
    }

    private func scheduleTimeout(source: String, requestID: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  let self,
                  self.completion != nil,
                  self.requestID == requestID else { return }
            self.showSourceFallback(
                source: source,
                title: self.localized("Unable to render Mermaid preview"),
                detail: self.localized("Rendering timed out. Showing source instead.")
            )
            self.finishPreparation()
        }
    }

    private func finishPreparation() {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingSource = nil
        completion?.resume()
        completion = nil
    }

    private func showWebView(_ webView: WKWebView) {
        replaceContent(with: webView)
        view.layoutSubtreeIfNeeded()
    }

    private func showLoadingView() {
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .regular
        progress.startAnimation(nil)
        progress.setAccessibilityLabel(localized("Rendering Mermaid preview"))
        replaceContent(with: progress, pinToEdges: false)
    }

    private func showSourceFallback(source: String, title: String, detail: String) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle

        let fileLabel = NSTextField(labelWithString: pendingFileName)
        fileLabel.font = .preferredFont(forTextStyle: .headline)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.maximumNumberOfLines = 1
        fileLabel.lineBreakMode = .byTruncatingMiddle

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabelColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = source
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.setAccessibilityLabel(localized("Mermaid source"))

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        let header = NSStackView(views: [titleLabel, fileLabel, detailLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 5

        let stack = NSStackView(views: [header, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        replaceContent(with: stack, insets: NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24))
    }

    private func replaceContent(
        with content: NSView,
        pinToEdges: Bool = true,
        insets: NSEdgeInsets = .init()
    ) {
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        if pinToEdges {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
                content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
                content.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
                content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
            ])
        } else {
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    private var mermaidTheme: String {
        let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? "dark" : "default"
    }

    private func localized(_ key: String) -> String {
        Bundle(for: Self.self).localizedString(forKey: key, value: key, table: nil)
    }
}

extension PreviewViewController: WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in
            self?.handleRendererMessage(payload)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType != .linkActivated,
              let scheme = navigationAction.request.url?.scheme,
              scheme == "file" || scheme == "about" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
