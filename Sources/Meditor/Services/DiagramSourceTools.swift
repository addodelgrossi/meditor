import Foundation

enum DiagramSourceTools {
    struct RenamePlan: Equatable {
        let source: String
        let replacementCount: Int
        let affectedLines: [Int]
    }

    enum RenameError: LocalizedError, Equatable {
        case unsupported
        case invalidIdentifier
        case identifierAlreadyExists
        case noOccurrences

        var errorDescription: String? {
            switch self {
            case .unsupported:
                String(localized: "Renaming is not supported for this diagram element.")
            case .invalidIdentifier:
                String(localized: "Use an identifier that starts with a letter or underscore and contains only letters, numbers, underscores, or hyphens.")
            case .identifierAlreadyExists:
                String(localized: "Another diagram element already uses that identifier.")
            case .noOccurrences:
                String(localized: "No safe occurrences of this identifier were found.")
            }
        }
    }

    static func markdownBlock(for source: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in source {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        let fence = String(repeating: "`", count: max(longestRun + 1, 3))
        let trailingNewline = source.hasSuffix("\n") ? "" : "\n"
        return "\(fence)mermaid\n\(source)\(trailingNewline)\(fence)"
    }

    static func enrich(_ analysis: DiagramAnalysis, source: String) -> DiagramAnalysis {
        var enriched = analysis
        enriched.outline = analysis.outline.map {
            enrich($0, diagramType: analysis.diagramType, source: source)
        }
        enriched.issues = issues(for: enriched, source: source)
        return enriched
    }

    static func renamePlan(
        source: String,
        diagramType: String,
        item: DiagramOutlineItem,
        newIdentifier: String
    ) throws -> RenamePlan {
        guard item.kind.canRename, let oldIdentifier = item.identifier else {
            throw RenameError.unsupported
        }
        guard newIdentifier.range(
            of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) != nil else {
            throw RenameError.invalidIdentifier
        }
        guard oldIdentifier != newIdentifier else {
            throw RenameError.noOccurrences
        }

        let ranges: [(range: NSRange, line: Int)]
        let collisionRanges: [(range: NSRange, line: Int)]
        if diagramType.hasPrefix("flowchart") {
            ranges = flowchartRenameRanges(in: source, identifier: oldIdentifier)
            collisionRanges = flowchartRenameRanges(in: source, identifier: newIdentifier)
        } else if diagramType == "sequence" {
            ranges = sequenceRenameRanges(in: source, identifier: oldIdentifier)
            collisionRanges = sequenceRenameRanges(in: source, identifier: newIdentifier)
        } else {
            throw RenameError.unsupported
        }
        guard collisionRanges.isEmpty else {
            throw RenameError.identifierAlreadyExists
        }
        guard !ranges.isEmpty else {
            throw RenameError.noOccurrences
        }

        let mutable = NSMutableString(string: source)
        for replacement in ranges.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: replacement.range, with: newIdentifier)
        }
        return RenamePlan(
            source: mutable as String,
            replacementCount: ranges.count,
            affectedLines: Array(Set(ranges.map(\.line))).sorted()
        )
    }

    private static func enrich(
        _ item: DiagramOutlineItem,
        diagramType: String,
        source: String
    ) -> DiagramOutlineItem {
        var item = item
        item.children = item.children.map {
            enrich($0, diagramType: diagramType, source: source)
        }
        if let identifier = item.identifier {
            let lines = declarationLines(
                in: source,
                diagramType: diagramType,
                kind: item.kind,
                identifier: identifier
            )
            item.line = lines.count == 1 ? lines[0] : nil
        }
        return item
    }

    private static func issues(for analysis: DiagramAnalysis, source: String) -> [DiagramIssue] {
        if analysis.diagramType.hasPrefix("flowchart") {
            return flowchartIssues(for: analysis, source: source)
        }
        if analysis.diagramType == "sequence" {
            return sequenceIssues(for: analysis, source: source)
        }
        return []
    }

    private static func flowchartIssues(for analysis: DiagramAnalysis, source: String) -> [DiagramIssue] {
        let connected = Set(analysis.connections.flatMap { [$0.from, $0.to] })
        var issues: [DiagramIssue] = []

        for item in analysis.allOutlineItems where item.kind == .node {
            guard let identifier = item.identifier else { continue }
            let declarations = declarationLines(
                in: source,
                diagramType: analysis.diagramType,
                kind: item.kind,
                identifier: identifier
            )
            if declarations.count > 1 {
                issues.append(
                    DiagramIssue(
                        id: "duplicate:\(identifier)",
                        kind: .duplicateIdentifier,
                        message: String(localized: "“\(identifier)” is explicitly declared more than once."),
                        line: declarations.first
                    )
                )
            }
            if !connected.contains(identifier) {
                issues.append(
                    DiagramIssue(
                        id: "disconnected:\(identifier)",
                        kind: .disconnectedElement,
                        message: String(localized: "“\(identifier)” is not connected to another node."),
                        line: declarations.count == 1 ? declarations[0] : nil
                    )
                )
            }
        }
        return issues
    }

    private static func sequenceIssues(for analysis: DiagramAnalysis, source: String) -> [DiagramIssue] {
        let connected = Set(analysis.connections.flatMap { [$0.from, $0.to] })
        var issues: [DiagramIssue] = []

        for item in analysis.allOutlineItems where item.kind == .participant || item.kind == .actor {
            guard let identifier = item.identifier else { continue }
            let declarations = declarationLines(
                in: source,
                diagramType: analysis.diagramType,
                kind: item.kind,
                identifier: identifier
            )
            if declarations.count > 1 {
                issues.append(
                    DiagramIssue(
                        id: "duplicate:\(identifier)",
                        kind: .duplicateIdentifier,
                        message: String(localized: "“\(identifier)” is explicitly declared more than once."),
                        line: declarations.first
                    )
                )
            }
            if !connected.contains(identifier) {
                issues.append(
                    DiagramIssue(
                        id: "disconnected:\(identifier)",
                        kind: .disconnectedElement,
                        message: String(localized: "“\(identifier)” does not send or receive a message."),
                        line: declarations.count == 1 ? declarations[0] : nil
                    )
                )
            }
        }
        return issues
    }

    private static func declarationLines(
        in source: String,
        diagramType: String,
        kind: DiagramOutlineKind,
        identifier: String
    ) -> [Int] {
        let escaped = NSRegularExpression.escapedPattern(for: identifier)
        let pattern: String
        switch kind {
        case .node where diagramType.hasPrefix("flowchart"):
            return flowchartDeclarationRanges(in: source, identifier: identifier).map(\.line)
        case .subgraph:
            pattern = #"^\s*subgraph\s+"# + escaped + #"(?:\s|$|\[)"#
        case .participant, .actor:
            pattern = #"^\s*(?:create\s+)?(?:participant|actor)\s+"# + escaped + #"(?:\s+as\b|\s*$)"#
        case .class:
            pattern = #"^\s*class\s+"# + escaped + #"(?:\s|$|\{)"#
        case .state:
            pattern = #"^\s*state\s+(?:\"[^\"]+\"\s+as\s+)?"# + escaped + #"(?:\s|$|\{)"#
        case .entity:
            pattern = #"^\s*"# + escaped + #"\s*\{"#
        case .group:
            pattern = #"^\s*group\s+"# + escaped + #"(?:\s|\()"#
        case .service:
            pattern = #"^\s*service\s+"# + escaped + #"(?:\s|\()"#
        case .junction:
            pattern = #"^\s*junction\s+"# + escaped + #"(?:\s|\()"#
        default:
            return []
        }
        return matchingLines(pattern: pattern, in: source)
    }

    private static func flowchartDeclarationRanges(
        in source: String,
        identifier: String
    ) -> [(range: NSRange, line: Int)] {
        candidateRanges(in: source, identifier: identifier).filter { candidate in
            let line = candidate.lineText as NSString
            let local = NSRange(
                location: candidate.range.location - candidate.lineRange.location,
                length: candidate.range.length
            )
            guard !isProtected(local, in: candidate.lineText) else { return false }
            let suffix = line.substring(from: NSMaxRange(local))
            if suffix.range(
                of: #"^\s*(?:\[\[|\(\[|\(\(|\[\(|\[|\(|\{|>|@)"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            return candidate.lineText.trimmingCharacters(in: .whitespaces) == identifier
        }.map { ($0.range, $0.line) }
    }

    private static func matchingLines(pattern: String, in source: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { lineNumber(at: $0.range.location, in: source) }
    }

    private static func flowchartRenameRanges(in source: String, identifier: String) -> [(NSRange, Int)] {
        candidateRanges(in: source, identifier: identifier).filter { candidate in
            let line = candidate.lineText as NSString
            let local = NSRange(
                location: candidate.range.location - candidate.lineRange.location,
                length: candidate.range.length
            )
            guard !isProtected(local, in: candidate.lineText) else { return false }
            let suffix = line.substring(from: NSMaxRange(local))
            if suffix.range(of: #"^\s*(?:\[\[|\(\[|\(\(|\[\(|\[|\(|\{|>|@)"#, options: .regularExpression) != nil {
                return true
            }
            if candidate.lineText.range(of: #"(-->|---|==>|-.->|<-->|--x|--o|~~~)"#, options: .regularExpression) != nil {
                return true
            }
            let prefix = line.substring(to: local.location)
            return prefix.range(
                of: #"^\s*(?:style|click|class|link)\s+(?:[A-Za-z_][A-Za-z0-9_-]*\s*,\s*)*$"#,
                options: .regularExpression
            ) != nil || candidate.lineText.trimmingCharacters(in: .whitespaces) == identifier
        }.map { ($0.range, $0.line) }
    }

    private static func sequenceRenameRanges(in source: String, identifier: String) -> [(NSRange, Int)] {
        candidateRanges(in: source, identifier: identifier).filter { candidate in
            let line = candidate.lineText as NSString
            let local = NSRange(
                location: candidate.range.location - candidate.lineRange.location,
                length: candidate.range.length
            )
            let prefix = line.substring(to: local.location)
            let suffix = line.substring(from: NSMaxRange(local))
            if prefix.range(of: #"^\s*(?:participant|actor)\s+$"#, options: .regularExpression) != nil {
                return true
            }
            if prefix.range(
                of: #"^\s*(?:activate|deactivate|create\s+(?:participant|actor)|destroy)\s+$"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            let syntax = candidate.lineText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if NSLocationInRange(local.location, NSRange(location: 0, length: (syntax as NSString).length)),
               syntax.range(
                of: #"(?:--?>>|--?>|--?x|--?\)|<<--?|<--?)"#,
                options: .regularExpression
               ) != nil {
                return true
            }
            if prefix.range(of: #"^\s*note\s+(?:over|left of|right of)\s+(?:[A-Za-z_][A-Za-z0-9_-]*\s*,\s*)*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
            return suffix.range(of: #"^\s*(?:,|$)"#, options: .regularExpression) != nil
                && prefix.range(of: #"^\s*note\s+(?:over|left of|right of)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil
        }.map { ($0.range, $0.line) }
    }

    private static func candidateRanges(
        in source: String,
        identifier: String
    ) -> [(range: NSRange, line: Int, lineRange: NSRange, lineText: String)] {
        let escaped = NSRegularExpression.escapedPattern(for: identifier)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_])"# + escaped + #"(?![A-Za-z0-9_])"#
        ) else { return [] }
        let string = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let lineRange = string.lineRange(for: match.range)
            let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard !lineText.trimmingCharacters(in: .whitespaces).hasPrefix("%%") else { return nil }
            let localRange = NSRange(
                location: match.range.location - lineRange.location,
                length: match.range.length
            )
            guard hasIdentifierBoundaries(localRange, in: lineText) else { return nil }
            return (match.range, lineNumber(at: match.range.location, in: source), lineRange, lineText)
        }
    }

    private static func hasIdentifierBoundaries(_ range: NSRange, in line: String) -> Bool {
        let line = line as NSString
        let prefix = line.substring(to: range.location)
        let suffix = line.substring(from: NSMaxRange(range))

        if let previous = prefix.last, previous == "-" {
            guard prefix.range(
                of: #"(?:-{2,}|=+>|-\.[->]+|--?[xo\)])$"#,
                options: .regularExpression
            ) != nil else { return false }
        } else if let previous = prefix.last, previous == "_" || previous.isLetter || previous.isNumber {
            return false
        }

        if let next = suffix.first, next == "-" {
            guard suffix.range(
                of: #"^(?:-{2,}|-+>|-\.[->]+|--?[xo\)])"#,
                options: .regularExpression
            ) != nil else { return false }
        } else if let next = suffix.first, next == "_" || next.isLetter || next.isNumber {
            return false
        }
        return true
    }

    private static func isProtected(_ range: NSRange, in line: String) -> Bool {
        let patterns = [#""[^"]*""#, #"\|[^|]*\|"#, #"\[[^\]]*\]"#, #"\([^)]*\)"#, #"\{[^}]*\}"#]
        let fullRange = NSRange(line.startIndex..., in: line)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.matches(in: line, range: fullRange).contains { NSIntersectionRange($0.range, range).length > 0 }
        }
    }

    private static func lineNumber(at utf16Location: Int, in source: String) -> Int {
        let prefix = (source as NSString).substring(to: min(utf16Location, (source as NSString).length))
        return prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }
}
