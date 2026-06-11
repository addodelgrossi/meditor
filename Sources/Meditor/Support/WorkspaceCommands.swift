import AppKit
import SwiftUI

struct WorkspaceActions {
    let setMode: (WorkspaceMode) -> Void
    let fitPreview: () -> Void
    let export: () -> Void
    let startPresentation: () -> Void
    let publish: () -> Void
    let copyMarkdown: () -> Void
    let toggleInspector: () -> Void
    let isInspectorShown: Bool
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
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue

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

            Button("Copy as Markdown Mermaid Block") {
                actions?.copyMarkdown()
            }

            Button(actions?.isInspectorShown == true ? "Hide Inspector" : "Show Inspector") {
                actions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button("Fit diagram") {
                actions?.fitPreview()
            }
            .keyboardShortcut("0", modifiers: [.command])

            Divider()

            Button("Export…") {
                actions?.export()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Start Presentation…") {
                actions?.startPresentation()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Light/Dark Appearance") {
                toggleAppearance()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func toggleAppearance() {
        let appearance = AppAppearance.resolved(appAppearanceRaw)
        let isDark: Bool
        switch appearance {
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .light:
            isDark = false
        case .dark:
            isDark = true
        }
        appAppearanceRaw = isDark ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue
    }
}
