import SwiftUI

struct WorkspaceActions {
    let setMode: (WorkspaceMode) -> Void
    let fitPreview: () -> Void
    let exportSVG: () -> Void
    let showPublishedLinks: () -> Void
}

private struct WorkspaceActionsKey: FocusedValueKey {
    typealias Value = WorkspaceActions
}

extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

struct MeditorCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions

    var body: some Commands {
        CommandMenu("Diagram") {
            Button("Editor") {
                actions?.setMode(.editor)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("Split") {
                actions?.setMode(.split)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button("Preview") {
                actions?.setMode(.preview)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button("Fit diagram") {
                actions?.fitPreview()
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button("Export SVG") {
                actions?.exportSVG()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Published Links…") {
                actions?.showPublishedLinks()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
