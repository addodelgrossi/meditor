import AppKit
import SwiftUI

struct PresentationDeckBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var slides: [PresentationSlide]
    @State private var errorMessage: String?

    private let theme: MermaidTheme

    init(currentCode: String, currentTitle: String, theme: MermaidTheme) {
        let currentSlides: [PresentationSlide]
        if currentCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentSlides = []
        } else {
            currentSlides = [PresentationSlide(title: currentTitle, code: currentCode)]
        }
        _slides = State(initialValue: currentSlides)
        self.theme = theme
    }

    var body: some View {
        VStack(spacing: 0) {
            if slides.isEmpty {
                ContentUnavailableView(
                    "No slides yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Add Mermaid files to build a presentation.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Image(systemName: "doc.text.image")
                                .foregroundStyle(Brand.gradient)
                            Text(slide.title)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { slides.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { slides.remove(atOffsets: $0) }
                }
            }

            Divider()

            HStack {
                Button("Add Files…", action: addFiles)

                Text("Drag rows to reorder. Files are read once when added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Button("Start Presentation") {
                    openWindow(
                        id: "presentation",
                        value: PresentationDeck(slides: slides, theme: theme)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slides.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 650, height: 500)
        .navigationTitle("Build Presentation")
        .alert("Unable to add files", isPresented: errorAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mermaidSource]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        do {
            slides.append(contentsOf: try PresentationDeckLoader.slides(from: panel.urls))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
