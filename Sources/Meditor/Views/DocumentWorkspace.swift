import SwiftUI

struct DocumentWorkspace: View {
    @Binding var document: MermaidDocument
    @StateObject private var renderStore = RenderStore()
    @State private var mode = WorkspaceMode.split
    @State private var theme = AppPreferences.shared.defaultTheme
    @State private var navigateToLine: Int?
    @State private var exportErrorMessage: String?
    @State private var showsTemplateGallery = true

    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("wrapLines") private var wrapsLines = false
    @AppStorage("defaultExportScale") private var exportScaleRaw = ExportScale.two.rawValue
    @AppStorage("transparentExport") private var transparentExport = true

    var body: some View {
        VStack(spacing: 0) {
            if let error = renderStore.error {
                RenderErrorBanner(error: error) {
                    mode = mode == .preview ? .split : mode
                    navigateToLine = nil
                    Task { @MainActor in
                        navigateToLine = error.line
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            workspace
        }
        .background {
            Brand.gradient.opacity(0.035)
        }
        .toolbar {
            toolbarContent
        }
        .focusedSceneValue(
            \.workspaceActions,
            WorkspaceActions(
                setMode: { mode = $0 },
                fitPreview: renderStore.fit,
                exportSVG: { export(.svg) }
            )
        )
        .alert("Export failed", isPresented: exportAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch mode {
        case .editor:
            editorPane
        case .split:
            HSplitView {
                editorPane
                    .frame(minWidth: 340, idealWidth: 520)
                previewPane
                    .frame(minWidth: 420, idealWidth: 720)
            }
        case .preview:
            previewPane
        }
    }

    private var editorPane: some View {
        ZStack {
            MermaidTextEditor(
                text: $document.text,
                errorLine: renderStore.error?.line,
                navigateToLine: navigateToLine,
                fontName: editorFontName,
                fontSize: editorFontSize,
                wrapsLines: wrapsLines
            )

            if showsTemplateGallery,
               document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TemplateGallery { template in
                    document.text = template.source
                } onStartBlank: {
                    showsTemplateGallery = false
                }
            }
        }
        .background(.background)
    }

    private var previewPane: some View {
        ZStack {
            CanvasBackdrop()
            MermaidPreviewWebView(code: document.text, theme: theme, store: renderStore)

            VStack {
                Spacer()
                if (renderStore.info != nil && renderStore.error == nil) || renderStore.isRendering {
                    HStack(spacing: 8) {
                        if let info = renderStore.info, renderStore.error == nil {
                            Label(info.diagramType.capitalized, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        if renderStore.isRendering {
                            ProgressView()
                                .controlSize(.small)
                            Text("Rendering…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(12)
                }
            }
        }
        .clipped()
        .accessibilityLabel("Diagram preview")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Layout", selection: $mode) {
                ForEach(WorkspaceMode.allCases) { layout in
                    Label(layout.label, systemImage: layout.systemImage)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }

        ToolbarItem {
            Menu {
                ForEach(MermaidTemplate.all) { template in
                    Button {
                        document.text = template.source
                    } label: {
                        Label(template.title, systemImage: template.systemImage)
                    }
                }
            } label: {
                Label("Templates", systemImage: "square.grid.2x2")
            }
        }

        ToolbarItem {
            Menu {
                Picker("Diagram theme", selection: $theme) {
                    ForEach(MermaidTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            Button(action: renderStore.zoomOut) {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }
            Button(action: renderStore.fit) {
                Label("Fit diagram", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button(action: renderStore.zoomIn) {
                Label("Zoom in", systemImage: "plus.magnifyingglass")
            }
        }

        ToolbarItem {
            Menu {
                Section("Export") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.label) {
                            export(format)
                        }
                        .disabled(renderStore.lastSVG == nil)
                    }
                }
                Section("Copy") {
                    Button("Copy SVG") {
                        guard let svg = renderStore.lastSVG else { return }
                        ExportService.copySVG(svg)
                    }
                    Button("Copy PNG") {
                        guard let svg = renderStore.lastSVG else { return }
                        performCatching {
                            try ExportService.copyPNG(
                                svg,
                                scale: exportScale,
                                transparentBackground: transparentExport
                            )
                        }
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var exportScale: ExportScale {
        ExportScale(rawValue: exportScaleRaw) ?? .two
    }

    private var exportAlertIsPresented: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )
    }

    private func export(_ format: ExportFormat) {
        guard let svg = renderStore.lastSVG else { return }
        performCatching {
            try ExportService.export(
                svg: svg,
                format: format,
                scale: exportScale,
                transparentBackground: transparentExport
            )
        }
    }

    private func performCatching(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}
