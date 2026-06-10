import AppKit
import SwiftUI

@main
struct MeditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { configuration in
            DocumentWorkspace(document: configuration.$document)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            MeditorCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
