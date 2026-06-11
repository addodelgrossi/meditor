import SwiftUI

struct DocumentWorkspace: View {
    @Binding var document: MermaidDocument
    let fileURL: URL?

    @StateObject private var renderStore = RenderStore()
    @State private var mode = WorkspaceMode.split
    @State private var theme = AppPreferences.shared.defaultTheme
    @State private var navigateToLine: Int?
    @State private var showsTemplateGallery = true
    @State private var showsPublishPopover = false
    @State private var showsExportPanel = false
    @State private var showsPresentationBuilder = false

    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("wrapLines") private var wrapsLines = false
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
                export: { showsExportPanel = true },
                startPresentation: { showsPresentationBuilder = true },
                publish: { showsPublishPopover = true },
                canPublish: canPublish
            )
        )
        .sheet(isPresented: $showsExportPanel) {
            ExportPanel(
                code: document.text,
                currentTheme: theme,
                suggestedName: documentTitle
            )
        }
        .sheet(isPresented: $showsPresentationBuilder) {
            PresentationDeckBuilderView(
                currentCode: document.text,
                currentTitle: documentTitle,
                theme: theme
            )
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
            Button {
                showsPresentationBuilder = true
            } label: {
                Label("Present", systemImage: "play.rectangle")
            }
        }

        ToolbarItem {
            Button {
                showsPublishPopover = true
            } label: {
                Label("Publish", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!canPublish)
            .popover(isPresented: $showsPublishPopover, arrowEdge: .bottom) {
                PublishPopover(
                    code: document.text,
                    theme: theme
                )
            }
        }

        ToolbarItem {
            Button {
                showsExportPanel = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(renderStore.lastSVG == nil)
        }
    }

    private var documentTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled Diagram")
    }

    private var canPublish: Bool {
        renderStore.canPublish(code: document.text, theme: theme)
    }

}
