import SwiftUI

struct DocumentWorkspace: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Binding var document: MermaidDocument
    let fileURL: URL?

    @StateObject private var renderStore = RenderStore()
    @State private var mode = WorkspaceMode.split
    @State private var theme = AppPreferences.shared.defaultTheme
    @State private var navigateToLine: Int?
    @State private var showsPublishPopover = false
    @State private var showsExportPanel = false
    @State private var showsPresentationBuilder = false
    @State private var showsImageCopied = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var editorCommand: MermaidEditorCommand?
    @State private var renameTarget: DiagramOutlineItem?
    @State private var actionErrorTitle = String(localized: "Unable to update diagram")
    @State private var actionErrorMessage: String?
    @SceneStorage("showsDiagramInspector") private var showsDiagramInspector = false

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
                copyImage: copyImage,
                copyMarkdown: { ExportService.copyMarkdownBlock(document.text) },
                toggleInspector: { showsDiagramInspector.toggle() },
                isInspectorShown: showsDiagramInspector,
                canCopyImage: canCopyImage,
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
        .sheet(item: $renameTarget) { item in
            RenameDiagramSheet(
                source: document.text,
                diagramType: renderStore.analysis?.diagramType ?? "",
                item: item
            ) { newIdentifier in
                rename(item, to: newIdentifier)
            }
        }
        .inspector(isPresented: $showsDiagramInspector) {
            DiagramInspectorView(
                analysis: renderStore.analysis,
                isRendering: renderStore.isRendering,
                onNavigate: navigate,
                onRename: { renameTarget = $0 }
            )
        }
        .alert(actionErrorTitle, isPresented: actionErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .onAppear {
            dismissWindow(id: "welcome")
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
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
        MermaidTextEditor(
            text: $document.text,
            errorLine: renderStore.error?.line,
            navigateToLine: navigateToLine,
            command: $editorCommand,
            fontName: editorFontName,
            fontSize: editorFontSize,
            wrapsLines: wrapsLines
        )
        .background(.background)
    }

    private var previewPane: some View {
        ZStack {
            CanvasBackdrop()
            MermaidPreviewWebView(code: document.text, theme: theme, store: renderStore)

            VStack {
                if showsImageCopied {
                    Label("Image copied", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 14)
                }

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
        .contextMenu {
            Button("Copy Image", action: copyImage)
                .disabled(!canCopyImage)
        }
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
            Button(action: copyImage) {
                Label("Copy Image", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(!canCopyImage)
        }

        ToolbarItem {
            Button {
                showsExportPanel = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(renderStore.lastSVG == nil)
        }

        ToolbarItem {
            Button {
                showsDiagramInspector.toggle()
            } label: {
                Label("Diagram Inspector", systemImage: "sidebar.trailing")
            }
        }
    }

    private var documentTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled Diagram")
    }

    private var canPublish: Bool {
        renderStore.canPublish(code: document.text, theme: theme)
    }

    private var canCopyImage: Bool {
        renderStore.lastSVG != nil && renderStore.lastSuccessfulTheme != nil
    }

    private var actionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )
    }

    private func navigate(to line: Int) {
        navigateToLine = nil
        Task { @MainActor in
            navigateToLine = line
        }
    }

    private func rename(_ item: DiagramOutlineItem, to newIdentifier: String) {
        let originalSource = document.text
        Task { @MainActor in
            do {
                let plan = try DiagramSourceTools.renamePlan(
                    source: originalSource,
                    diagramType: renderStore.analysis?.diagramType ?? "",
                    item: item,
                    newIdentifier: newIdentifier
                )
                _ = try await DiagramRenderService.shared.render(code: plan.source, theme: theme)
                guard document.text == originalSource else {
                    throw WorkspaceActionError.sourceChanged
                }
                editorCommand = MermaidEditorCommand(
                    replacementText: plan.source,
                    actionName: String(localized: "Rename Diagram Identifier")
                )
            } catch {
                actionErrorTitle = String(localized: "Unable to update diagram")
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func copyImage() {
        guard let svg = renderStore.lastSVG,
              let renderedTheme = renderStore.lastSuccessfulTheme else { return }
        do {
            try ExportService.copyImageForSharing(svg, theme: renderedTheme)
            copyFeedbackTask?.cancel()
            withAnimation(.snappy) {
                showsImageCopied = true
            }
            copyFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    showsImageCopied = false
                }
            }
        } catch {
            actionErrorTitle = String(localized: "Unable to copy image")
            actionErrorMessage = error.localizedDescription
        }
    }
}

private enum WorkspaceActionError: LocalizedError {
    case sourceChanged

    var errorDescription: String? {
        String(localized: "The source changed while the rename was being validated. Try again.")
    }
}
