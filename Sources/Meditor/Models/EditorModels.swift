import Foundation
import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case editor
    case split
    case preview

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .editor: "Editor"
        case .split: "Split"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .editor: "text.alignleft"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolved(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .system
    }
}

enum MermaidTheme: String, CaseIterable, Codable, Hashable, Identifiable {
    case `default`
    case neutral
    case dark
    case forest
    case base

    var id: Self { self }
    var mermaidValue: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .default: "Default"
        case .neutral: "Neutral"
        case .dark: "Dark"
        case .forest: "Forest"
        case .base: "Base"
        }
    }
}

struct MermaidRenderError: Equatable {
    let message: String
    let line: Int?
    let column: Int?
}

struct MermaidRenderInfo: Equatable {
    let diagramType: String
    let width: Double
    let height: Double
}

enum ExportScale: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case four = 4

    var id: Int { rawValue }
    var label: String { "\(rawValue)x" }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case svg
    case png
    case pdf

    var id: Self { self }
    var fileExtension: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum ExportThemePreset: String, CaseIterable, Identifiable {
    case current
    case light
    case dark

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .current: "Current"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    func resolved(currentTheme: MermaidTheme) -> MermaidTheme {
        switch self {
        case .current: currentTheme
        case .light: .default
        case .dark: .dark
        }
    }
}

enum ExportBackground: String, CaseIterable, Identifiable {
    case transparent
    case light
    case dark

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .transparent: "Transparent"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static func resolved(_ rawValue: String?, legacyTransparent: Bool) -> Self {
        if let rawValue, let background = Self(rawValue: rawValue) {
            return background
        }
        return legacyTransparent ? .transparent : .light
    }
}

enum RenderPurpose {
    case editor
    case export
    case presentation

    var interactive: Bool {
        self != .export
    }

    var highlightable: Bool {
        self == .presentation
    }

    var clearOnError: Bool {
        self != .editor
    }

    var fitAfterRender: Bool {
        self != .editor
    }
}
