import Foundation

enum RendererResources {
    static var htmlURL: URL? {
        Bundle.module.url(forResource: "renderer", withExtension: "html")
    }

    static var mermaidJavaScriptURL: URL? {
        Bundle.module.url(forResource: "mermaid", withExtension: "min.js")
    }
}
