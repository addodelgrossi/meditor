import SwiftUI

struct WorkspaceActions {
    let setMode: (WorkspaceMode) -> Void
    let fitPreview: () -> Void
    let exportSVG: () -> Void
    let publish: () -> Void
    let canPublish: Bool
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Publish…") {
                actions?.publish()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(actions?.canPublish != true)

            Button("Published Links…") {
                openWindow(id: "published-links")
            }

            Divider()
        }

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

        }
    }
}
