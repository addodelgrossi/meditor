import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @State private var recentDocuments: [URL] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 18) {
                    MeditorMark()
                        .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Welcome to Meditor")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Create, preview, and share Mermaid diagrams.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 14) {
                    WelcomeActionCard(
                        title: "New diagram",
                        subtitle: "Start with an empty Mermaid document",
                        systemImage: "plus.square",
                        prominent: true
                    ) {
                        createDocument()
                    }

                    WelcomeActionCard(
                        title: "Open file…",
                        subtitle: "Open an existing .mmd or .mermaid file",
                        systemImage: "folder",
                        prominent: false
                    ) {
                        chooseDocument()
                    }
                }

                if !recentDocuments.isEmpty {
                    recentSection
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Start with a template")
                        .font(.title3.weight(.semibold))

                    Text("Choose a starting point and make it your own.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    templateGrid
                }
            }
            .padding(32)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Brand.gradient.opacity(0.055)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            reloadRecentDocuments()
        }
        .alert("Unable to open document", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.title3.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(Array(recentDocuments.enumerated()), id: \.element) { index, url in
                    Button {
                        open(url)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.title3)
                                .foregroundStyle(Brand.gradient)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < recentDocuments.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.separator.opacity(0.35))
            }
        }
    }

    private var templateGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(MermaidTemplate.all) { template in
                Button {
                    createDocument(text: template.source)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: template.systemImage)
                            .font(.title2)
                            .foregroundStyle(Brand.gradient)
                        Spacer()
                        Text(template.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(template.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.separator.opacity(0.35))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func createDocument(text: String = "") {
        newDocument(MermaidDocument(text: text))
        dismissWindow(id: "welcome")
    }

    private func chooseDocument() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Mermaid Diagram")
        panel.prompt = String(localized: "Open")
        panel.allowedContentTypes = MermaidDocument.readableContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    private func open(_ url: URL) {
        Task { @MainActor in
            do {
                try await openDocument(at: url)
                dismissWindow(id: "welcome")
            } catch {
                errorMessage = error.localizedDescription
                reloadRecentDocuments()
            }
        }
    }

    private func reloadRecentDocuments() {
        recentDocuments = WelcomeDocumentLibrary.recentDocuments(
            from: NSDocumentController.shared.recentDocumentURLs
        )
    }
}

enum WelcomeDocumentLibrary {
    static func recentDocuments(
        from urls: [URL],
        limit: Int = 5,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard seen.insert(url).inserted, fileExists(url.path) else { return nil }
            return url
        }
        .prefix(limit)
        .map { $0 }
    }
}

private struct WelcomeActionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Brand.gradient))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.78)
                }

                Spacer()
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(16)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Brand.gradient)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.separator.opacity(prominent ? 0 : 0.35))
            }
        }
        .buttonStyle(.plain)
    }
}

struct MeditorMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Brand.gradient, lineWidth: 1.5)

            Canvas { context, size in
                let leftTop = CGPoint(x: size.width * 0.24, y: size.height * 0.30)
                let leftBottom = CGPoint(x: size.width * 0.24, y: size.height * 0.72)
                let center = CGPoint(x: size.width * 0.50, y: size.height * 0.54)
                let rightTop = CGPoint(x: size.width * 0.76, y: size.height * 0.30)
                let rightBottom = CGPoint(x: size.width * 0.76, y: size.height * 0.72)

                var path = Path()
                path.move(to: leftBottom)
                path.addLine(to: leftTop)
                path.addLine(to: center)
                path.addLine(to: rightTop)
                path.addLine(to: rightBottom)
                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [Brand.aqua, Brand.indigo]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ), lineWidth: 5)

                for point in [leftTop, leftBottom, center, rightTop, rightBottom] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                        with: .color(.white)
                    )
                }
            }
            .padding(9)
        }
        .shadow(color: Brand.indigo.opacity(0.18), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}
