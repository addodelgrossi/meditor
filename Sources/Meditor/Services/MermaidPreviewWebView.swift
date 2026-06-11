import SwiftUI
import WebKit

struct MermaidPreviewWebView: NSViewRepresentable {
    let code: String
    let theme: MermaidTheme
    let store: RenderStore
    var onInteraction: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, onInteraction: onInteraction)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isTextInteractionEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "meditor")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        store.attach(webView)

        if let url = RendererResources.htmlURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        store.attach(webView)
        store.scheduleRender(code: code, theme: theme)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "meditor")
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var store: RenderStore?
        private let onInteraction: (() -> Void)?

        init(store: RenderStore, onInteraction: (() -> Void)?) {
            self.store = store
            self.onInteraction = onInteraction
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else { return }
            Task { @MainActor [weak self] in
                if payload["event"] as? String == "ready" {
                    self?.store?.webViewDidBecomeReady()
                } else if payload["event"] as? String == "interaction" {
                    self?.onInteraction?()
                } else {
                    self?.store?.handle(message: payload)
                }
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
}
