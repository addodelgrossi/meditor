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

                Spacer()

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

    private func performCatching(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
