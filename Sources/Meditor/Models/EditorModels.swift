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

enum MermaidTheme: String, CaseIterable, Identifiable {
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
