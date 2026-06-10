import Foundation

extension Bundle {
    static var meditorResources: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

enum RendererResources {
    static var htmlURL: URL? {
        Bundle.meditorResources.url(forResource: "renderer", withExtension: "html")
    }

    static var mermaidJavaScriptURL: URL? {
        Bundle.meditorResources.url(forResource: "mermaid", withExtension: "min.js")
    }
}

enum LegalResources {
    static var licenseText: String {
        [
            textResource(named: "LICENSE-Meditor"),
            textResource(named: "LICENSE-mermaid")
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n" + String(repeating: "=", count: 72) + "\n\n")
    }

    private static func textResource(named name: String) -> String? {
        guard let url = Bundle.meditorResources.url(forResource: name, withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
