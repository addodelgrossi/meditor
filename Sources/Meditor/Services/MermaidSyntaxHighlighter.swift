import AppKit

@MainActor
enum MermaidSyntaxHighlighter {
    static func apply(to textView: NSTextView, errorLine: Int?, editedRange: NSRange? = nil) {
        guard let layoutManager = textView.layoutManager else { return }
        let text = textView.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let stylingRange = expandedLineRange(editedRange, in: text) ?? fullRange

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: stylingRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: stylingRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: stylingRange)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.labelColor, forCharacterRange: stylingRange)

        apply(
            pattern: #"(?m)^\s*(flowchart|graph|sequenceDiagram|classDiagram|stateDiagram-v2|stateDiagram|erDiagram|gantt|mindmap|architecture-beta|C4Context|C4Container|C4Component|C4Dynamic|C4Deployment|journey|gitGraph|pie|timeline|quadrantChart|sankey-beta|xychart-beta)\b"#,
            color: .systemPurple,
            text: textView.string,
            range: stylingRange,
            layoutManager: layoutManager
        )
        apply(
            pattern: #"(?m)\b(participant|actor|class|state|section|subgraph|end|title|dateFormat|direction|service|group|Person|Person_Ext|System|System_Ext|SystemDb|SystemQueue|Boundary|Enterprise_Boundary|System_Boundary|Container|ContainerDb|ContainerQueue|Component|Rel|Rel_Back|Rel_Neighbor)\b"#,
            color: .systemBlue,
            text: textView.string,
            range: stylingRange,
            layoutManager: layoutManager
        )
        apply(
            pattern: #"(-->|-->>|->>|---|==>|-.->|<-->|--x|--o|:\s)"#,
            color: .systemTeal,
            text: textView.string,
            range: stylingRange,
            layoutManager: layoutManager
        )
        apply(
            pattern: #"(?m)%%(?!\{).*$"#,
            color: .tertiaryLabelColor,
            text: textView.string,
            range: stylingRange,
            layoutManager: layoutManager
        )
        apply(
            pattern: #"%%\{.*?\}%%"#,
            options: [.dotMatchesLineSeparators],
            color: .systemOrange,
            text: textView.string,
            range: stylingRange,
            layoutManager: layoutManager
        )

        if let selectedRange = text.lineRange(for: textView.selectedRange()) as NSRange? {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.08),
                forCharacterRange: selectedRange
            )
        }

        if let errorLine, let lineRange = range(ofLine: errorLine, in: text) {
            layoutManager.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.thick.rawValue,
                forCharacterRange: lineRange
            )
            layoutManager.addTemporaryAttribute(.underlineColor, value: NSColor.systemRed, forCharacterRange: lineRange)
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemRed.withAlphaComponent(0.07),
                forCharacterRange: lineRange
            )
        }
    }

    static func range(ofLine line: Int, in text: NSString) -> NSRange? {
        guard line > 0 else { return nil }
        var currentLine = 1
        var index = 0
        while index < text.length {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            if currentLine == line { return range }
            index = NSMaxRange(range)
            currentLine += 1
        }
        return currentLine == line ? NSRange(location: text.length, length: 0) : nil
    }

    private static func expandedLineRange(_ range: NSRange?, in text: NSString) -> NSRange? {
        guard let range else { return nil }
        let location = min(range.location, text.length)
        let length = min(range.length, text.length - location)
        return text.lineRange(for: NSRange(location: location, length: length))
    }

    private static func apply(
        pattern: String,
        options: NSRegularExpression.Options = [],
        color: NSColor,
        text: String,
        range: NSRange,
        layoutManager: NSLayoutManager
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: text, range: range) { result, _, _ in
            guard let result else { return }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: result.range)
        }
    }
}
