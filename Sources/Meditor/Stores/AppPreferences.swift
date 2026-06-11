import AppKit
import SwiftUI

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @AppStorage("appAppearance") var appAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage("defaultTheme") var defaultThemeRaw = MermaidTheme.default.rawValue
    @AppStorage("editorFontName") var editorFontName = "SF Mono"
    @AppStorage("editorFontSize") var editorFontSize = 14.0
    @AppStorage("wrapLines") var wrapLines = false
    @AppStorage("defaultExportScale") var defaultExportScale = ExportScale.two.rawValue
    @AppStorage("transparentExport") var transparentExport = true
    @AppStorage("defaultExportBackground") var defaultExportBackgroundRaw = ""
    // Base URL of the share backend. Configurable so anyone forking the app can
    // point at their own meditor-cloud instance.
    @AppStorage("shareBaseURL") var shareBaseURL = "https://meditor.dev"

    var appAppearance: AppAppearance {
        get { AppAppearance.resolved(appAppearanceRaw) }
        set { appAppearanceRaw = newValue.rawValue }
    }

    var defaultTheme: MermaidTheme {
        get { MermaidTheme(rawValue: defaultThemeRaw) ?? .default }
        set { defaultThemeRaw = newValue.rawValue }
    }

    var exportScale: ExportScale {
        get { ExportScale(rawValue: defaultExportScale) ?? .two }
        set { defaultExportScale = newValue.rawValue }
    }

    var exportBackground: ExportBackground {
        get { ExportBackground.resolved(defaultExportBackgroundRaw, legacyTransparent: transparentExport) }
        set { defaultExportBackgroundRaw = newValue.rawValue }
    }

    var shareServiceURL: ShareServiceURL {
        (try? ShareServiceURL(shareBaseURL)) ?? .defaultService
    }

    private init() {}
}
