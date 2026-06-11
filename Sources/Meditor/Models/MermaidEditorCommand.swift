import Foundation

struct MermaidEditorCommand: Identifiable, Equatable {
    let id = UUID()
    let replacementText: String
    let actionName: String
}

