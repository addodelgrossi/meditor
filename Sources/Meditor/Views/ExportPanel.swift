import AppKit
import SwiftUI

struct ExportPanel: View {
    let code: String
    let currentTheme: MermaidTheme
    let suggestedName: String

    @StateObject private var renderStore: RenderStore
    @State private var format = ExportFormat.png
    @State private var themePreset = ExportThemePreset.current
    @State private var background: ExportBackground
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var batchProgress: (current: Int, total: Int)?

    @AppStorage("defaultExportScale") private var exportScaleRaw = ExportScale.two.rawValue
    @AppStorage("defaultExportBackground") private var exportBackgroundRaw = ""

    init(code: String, currentTheme: MermaidTheme, suggestedName: String) {
        self.code = code
        self.currentTheme = currentTheme
        self.suggestedName = suggestedName
        _renderStore = StateObject(wrappedValue: RenderStore(purpose: .export))
        _background = State(
            initialValue: ExportBackground.resolved(
                UserDefaults.standard.string(forKey: "defaultExportBackground"),
                legacyTransparent: UserDefaults.standard.object(forKey: "transparentExport") as? Bool ?? true
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                controls
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 310)
                preview
                    .frame(minWidth: 520, idealWidth: 680)
            }

            Divider()

            HStack {
                Button("Copy SVG as Text") {
                    guard let svg = renderStore.lastSVG else { return }
                    ExportService.copySVGText(svg)
                }
                .disabled(!isReady)

                Button("Export All Themes…") {
                    exportAllThemes()
                }
                .disabled(batchProgress != nil || !isReady)

                Spacer()

                if let batchProgress {
                    ProgressView(value: Double(batchProgress.current), total: Double(batchProgress.total))
                        .frame(width: 120)
                    Text("\(batchProgress.current)/\(batchProgress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button("Copy Image") {
                    performCatching {
                        guard let svg = renderStore.lastSVG else { return }
                        try ExportService.copyImage(svg, scale: exportScale, background: background)
                    }
                }
                .disabled(!isReady)

                Button("Export…") {
                    performCatching {
                        guard let svg = renderStore.lastSVG else { return }
                        try ExportService.export(
                            svg: svg,
                            format: format,
                            scale: exportScale,
                            background: background,
                            suggestedName: suggestedName
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady)
            }
            .padding(16)
        }
        .frame(width: 980, height: 620)
        .onChange(of: background) { _, newValue in
            exportBackgroundRaw = newValue.rawValue
        }
        .alert("Export failed", isPresented: errorAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Export complete", isPresented: resultAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var controls: some View {
        Form {
            Section("Format") {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Image scale", selection: $exportScaleRaw) {
                    ForEach(ExportScale.allCases) { scale in
                        Text(scale.label).tag(scale.rawValue)
                    }
                }
            }

            Section("Appearance") {
                Picker("Export theme", selection: $themePreset) {
                    ForEach(ExportThemePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                Picker("Background", selection: $background) {
                    ForEach(ExportBackground.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section {
                Text("Copy Image includes SVG, PDF, PNG, and TIFF so each destination can choose its preferred representation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        ZStack {
            exportBackground
            MermaidPreviewWebView(code: code, theme: selectedTheme, store: renderStore)

            if renderStore.isRendering {
                ProgressView("Rendering…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if let error = renderStore.error {
                ContentUnavailableView(
                    "Unable to render diagram",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.message)
                )
            }
        }
        .clipped()
        .accessibilityLabel("Export preview")
    }

    @ViewBuilder
    private var exportBackground: some View {
        switch background {
        case .transparent:
            CanvasBackdrop()
        case .light:
            Color.white.ignoresSafeArea()
        case .dark:
            Color(red: 0x11 / 255, green: 0x13 / 255, blue: 0x18 / 255).ignoresSafeArea()
        }
    }

    private var selectedTheme: MermaidTheme {
        themePreset.resolved(currentTheme: currentTheme)
    }

    private var exportScale: ExportScale {
        ExportScale(rawValue: exportScaleRaw) ?? .two
    }

    private var isReady: Bool {
        renderStore.hasCurrentRender(code: code, theme: selectedTheme)
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var resultAlertIsPresented: Binding<Bool> {
        Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )
    }

    private func performCatching(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportAllThemes() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Export All Themes")
        panel.prompt = String(localized: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let batchFormat = format
        let batchScale = exportScale
        let batchBackground = background
        let destinations = ExportService.batchURLs(
            directory: directory,
            suggestedName: suggestedName,
            format: batchFormat
        )
        let collisions = destinations.filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }
        if !collisions.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Replace existing exports?")
            alert.informativeText = String(
                localized: "\(collisions.count) file(s) already exist in the selected folder."
            )
            alert.addButton(withTitle: String(localized: "Replace"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        batchProgress = (0, destinations.count)
        Task { @MainActor in
            var activeTheme: MermaidTheme?
            do {
                var outputs: [(url: URL, data: Data)] = []
                for (index, destination) in destinations.enumerated() {
                    batchProgress = (index, destinations.count)
                    activeTheme = destination.theme
                    let result = try await DiagramRenderService.shared.render(
                        code: code,
                        theme: destination.theme
                    )
                    outputs.append(
                        (
                            destination.url,
                            try ExportService.data(
                                svg: result.svg,
                                format: batchFormat,
                                scale: batchScale,
                                background: batchBackground
                            )
                        )
                    )
                    batchProgress = (index + 1, destinations.count)
                }
                activeTheme = nil
                try ExportService.writeBatch(outputs)
                batchProgress = nil
                resultMessage = String(
                    localized: "Exported \(outputs.count) themed diagram(s) to \(directory.lastPathComponent)."
                )
            } catch {
                batchProgress = nil
                if let activeTheme {
                    errorMessage = String(
                        localized: "The \(activeTheme.rawValue) theme failed: \(error.localizedDescription)"
                    )
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
