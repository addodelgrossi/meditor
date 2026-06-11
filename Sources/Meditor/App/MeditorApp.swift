import AppKit
import SwiftUI

@main
struct MeditorApp: App {
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue

    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { configuration in
            DocumentWorkspace(document: configuration.$document, fileURL: configuration.fileURL)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            MeditorCommands()
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appAppearance.colorScheme)
        }

        Window("Published Links", id: "published-links") {
            PublishedLinksView()
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 620, height: 430)

        WindowGroup("Presentation", id: "presentation", for: PresentationDeck.self) { deck in
            if let deck = deck.wrappedValue, !deck.slides.isEmpty {
                PresentationView(deck: deck)
            }
        }
        .defaultSize(width: 1_280, height: 800)
        .restorationBehavior(.disabled)
    }

    private var appAppearance: AppAppearance {
        AppAppearance.resolved(appAppearanceRaw)
    }
}
