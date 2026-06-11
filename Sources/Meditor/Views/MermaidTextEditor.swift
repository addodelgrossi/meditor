@preconcurrency import AppKit
import SwiftUI

struct MermaidTextEditor: NSViewRepresentable {
    @Binding var text: String
    let errorLine: Int?
    let navigateToLine: Int?
    @Binding var command: MermaidEditorCommand?
    let fontName: String
    let fontSize: Double
    let wrapsLines: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MermaidNSTextView()
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.string = text
        textView.font = editorFont()
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        Self.configureFind(in: textView)
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.insertionPointColor = .controlAccentColor
        textView.setAccessibilityLabel(String(localized: "Mermaid source editor"))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrapsLines
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.ruler = ruler

        configureWrapping(textView: textView, scrollView: scrollView)
        MermaidSyntaxHighlighter.apply(to: textView, errorLine: errorLine)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MermaidNSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }

        textView.font = editorFont()
        configureWrapping(textView: textView, scrollView: scrollView)
        MermaidSyntaxHighlighter.apply(to: textView, errorLine: errorLine)
        context.coordinator.ruler?.needsDisplay = true

        if navigateToLine != context.coordinator.lastNavigatedLine {
            context.coordinator.lastNavigatedLine = navigateToLine
            context.coordinator.navigate(to: navigateToLine)
        }

        if command?.id != context.coordinator.lastCommandID, let command {
            context.coordinator.lastCommandID = command.id
            context.coordinator.replaceText(using: command)
            Task { @MainActor in
                if context.coordinator.parent.command?.id == command.id {
                    context.coordinator.parent.command = nil
                }
            }
        }
    }

    private func configureWrapping(textView: NSTextView, scrollView: NSScrollView) {
        textView.isHorizontallyResizable = !wrapsLines
        textView.textContainer?.widthTracksTextView = wrapsLines
        textView.textContainer?.containerSize = NSSize(
            width: wrapsLines ? scrollView.contentSize.width : .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        )
        scrollView.hasHorizontalScroller = !wrapsLines
    }

    private func editorFont() -> NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    static func configureFind(in textView: NSTextView) {
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
    }

    static func apply(_ command: MermaidEditorCommand, to textView: NSTextView) {
        let selection = textView.selectedRange()
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.window?.makeFirstResponder(textView)
        textView.insertText(command.replacementText, replacementRange: fullRange)
        textView.undoManager?.setActionName(command.actionName)
        textView.setSelectedRange(
            NSRange(
                location: min(selection.location, (command.replacementText as NSString).length),
                length: 0
            )
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: MermaidTextEditor
        weak var ruler: LineNumberRulerView?
        weak var textView: NSTextView?
        var lastNavigatedLine: Int?
        var lastCommandID: UUID?

        init(parent: MermaidTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MermaidSyntaxHighlighter.apply(to: textView, errorLine: parent.errorLine)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), let textView else { return }
            MermaidSyntaxHighlighter.apply(
                to: textView,
                errorLine: parent.errorLine,
                editedRange: editedRange
            )
        }

        func navigate(to line: Int?) {
            guard let line,
                  let textView = ruler?.textView,
                  let range = MermaidSyntaxHighlighter.range(ofLine: line, in: textView.string as NSString) else { return }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.window?.makeFirstResponder(textView)
        }

        func replaceText(using command: MermaidEditorCommand) {
            guard let textView else { return }
            MermaidTextEditor.apply(command, to: textView)
        }
    }
}

final class MermaidNSTextView: NSTextView {
    private let mermaidCompletions = [
        "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2", "erDiagram",
        "gantt", "mindmap", "architecture-beta", "C4Context", "C4Container", "C4Component",
        "C4Dynamic", "C4Deployment", "subgraph", "participant", "actor", "section",
        "direction", "title", "dateFormat", "classDef", "Person", "Person_Ext", "System",
        "System_Ext", "SystemDb", "SystemQueue", "Boundary", "Enterprise_Boundary",
        "System_Boundary", "Container", "ContainerDb", "ContainerQueue", "Component",
        "Rel", "Rel_Back", "Rel_Neighbor"
    ]

    override func completions(
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
        let partial = (string as NSString).substring(with: charRange)
        return mermaidCompletions.filter {
            $0.range(of: partial, options: [.anchored, .caseInsensitive]) != nil
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), event.charactersIgnoringModifiers == " " {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 42

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateRuler),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateRuler),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func invalidateRuler() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let scrollView,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView.contentView.bounds
        let text = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        if text.length == 0 {
            ("1" as NSString).draw(at: NSPoint(x: 25, y: textView.textContainerInset.height), withAttributes: attributes)
            return
        }

        var line = 1
        var index = 0
        repeat {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
            var fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            fragment.origin.y += textView.textContainerOrigin.y - visibleRect.origin.y

            if fragment.maxY >= 0, fragment.minY <= bounds.maxY {
                let label = "\(line)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: ruleThickness - size.width - 9, y: fragment.minY + 1),
                    withAttributes: attributes
                )
            }

            index = NSMaxRange(lineRange)
            line += 1
        } while index < text.length

        _ = textContainer
    }
}
