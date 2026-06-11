import AppKit
import SwiftUI

struct PresentationView: View {
    let deck: PresentationDeck

    @StateObject private var renderStore = RenderStore(purpose: .presentation)
    @State private var position: PresentationPosition
    @State private var theme: MermaidTheme
    @State private var hudIsVisible = true
    @State private var hideHUDTask: Task<Void, Never>?
    @State private var window: NSWindow?

    init(deck: PresentationDeck) {
        self.deck = deck
        _position = State(initialValue: PresentationPosition(count: deck.slides.count))
        _theme = State(initialValue: deck.theme)
    }

    var body: some View {
        ZStack {
            presentationBackground
            MermaidPreviewWebView(
                code: currentSlide.code,
                theme: theme,
                store: renderStore,
                onInteraction: revealHUD
            )

            if let error = renderStore.error {
                ContentUnavailableView(
                    "Unable to render diagram",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.message)
                )
                .padding(32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }

            if hudIsVisible {
                hud
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background {
            PresentationWindowBridge { window in
                self.window = window
            }
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(.onHover)
        .focusable()
        .focusEffectDisabled()
        .onAppear(perform: revealHUD)
        .onContinuousHover { _ in revealHUD() }
        .onKeyPress { press in
            handle(press)
        }
        .animation(.easeInOut(duration: 0.18), value: hudIsVisible)
        .accessibilityLabel("Presentation")
    }

    @ViewBuilder
    private var presentationBackground: some View {
        if theme == .dark {
            Color(red: 0x11 / 255, green: 0x13 / 255, blue: 0x18 / 255).ignoresSafeArea()
        } else {
            Color.white.ignoresSafeArea()
        }
    }

    private var hud: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSlide.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(verbatim: "\(position.index + 1) / \(position.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(minWidth: 180, alignment: .leading)

                Divider()
                    .frame(height: 28)

                Button(action: previous) {
                    Label("Previous slide", systemImage: "chevron.left")
                }
                .disabled(!position.canGoPrevious)

                Button(action: next) {
                    Label("Next slide", systemImage: "chevron.right")
                }
                .disabled(!position.canGoNext)

                Divider()
                    .frame(height: 28)

                Button(action: renderStore.zoomOut) {
                    Label("Zoom out", systemImage: "minus.magnifyingglass")
                }
                Button(action: renderStore.fit) {
                    Label("Fit diagram", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button(action: renderStore.zoomIn) {
                    Label("Zoom in", systemImage: "plus.magnifyingglass")
                }

                Menu {
                    Picker("Diagram theme", selection: $theme) {
                        ForEach(MermaidTheme.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }

                Button(action: closePresentation) {
                    Label("End Presentation", systemImage: "xmark")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 24)
        }
    }

    private var currentSlide: PresentationSlide {
        deck.slides[position.index]
    }

    private func previous() {
        position.goPrevious()
        revealHUD()
    }

    private func next() {
        position.goNext()
        revealHUD()
    }

    private func revealHUD() {
        hideHUDTask?.cancel()
        hudIsVisible = true
        hideHUDTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            hudIsVisible = false
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        revealHUD()
        switch press.key {
        case .leftArrow, .upArrow:
            previous()
        case .rightArrow, .downArrow, .space:
            next()
        case .escape:
            closePresentation()
        default:
            switch press.characters {
            case "0": renderStore.fit()
            case "+", "=": renderStore.zoomIn()
            case "-", "_": renderStore.zoomOut()
            default: return .ignored
            }
        }
        return .handled
    }

    private func closePresentation() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                window.performClose(nil)
            }
        } else {
            window.performClose(nil)
        }
    }
}

private struct PresentationWindowBridge: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindow: onWindow)
    }

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindow = { window in
            context.coordinator.attach(window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        nsView.onWindow = { window in
            context.coordinator.attach(window)
        }
        nsView.notifyIfNeeded()
    }

    @MainActor
    final class Coordinator {
        private let onWindow: @MainActor (NSWindow) -> Void
        private weak var attachedWindow: NSWindow?

        init(onWindow: @escaping @MainActor (NSWindow) -> Void) {
            self.onWindow = onWindow
        }

        @MainActor
        func attach(_ window: NSWindow) {
            guard attachedWindow !== window else { return }
            attachedWindow = window
            window.collectionBehavior.formUnion([.fullScreenPrimary, .fullScreenDisallowsTiling])
            window.title = String(localized: "Presentation")
            onWindow(window)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }
}

private final class WindowObservingView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyIfNeeded()
    }

    func notifyIfNeeded() {
        guard let window else { return }
        onWindow?(window)
    }
}
