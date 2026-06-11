import SwiftUI

struct DiagramInspectorView: View {
    let analysis: DiagramAnalysis?
    let isRendering: Bool
    let onNavigate: (Int) -> Void
    let onRename: (DiagramOutlineItem) -> Void

    @State private var selection: DiagramOutlineItem.ID?

    var body: some View {
        Group {
            if isRendering {
                ProgressView("Analyzing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analysis {
                inspector(analysis)
            } else {
                ContentUnavailableView(
                    "No diagram analysis",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Analysis appears after the current source renders successfully.")
                )
            }
        }
        .frame(minWidth: 250, idealWidth: 300)
        .navigationTitle("Diagram Inspector")
    }

    private func inspector(_ analysis: DiagramAnalysis) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary(analysis)
                    if !analysis.issues.isEmpty {
                        issues(analysis.issues)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 230)

            Divider()

            List(selection: $selection) {
                OutlineGroup(analysis.outline, children: \.optionalChildren) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            if item.title != item.identifier, let identifier = item.identifier {
                                Text(identifier)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = item.id
                        if let line = item.line {
                            onNavigate(line)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button("Rename…") {
                    guard let selection, let item = analysis.item(id: selection) else { return }
                    onRename(item)
                }
                .disabled(selectedItem(in: analysis)?.kind.canRename != true)

                Spacer()

                if let line = selectedItem(in: analysis)?.line {
                    Button("Go to Line \(line)") {
                        onNavigate(line)
                    }
                }
            }
            .padding(12)
        }
    }

    private func summary(_ analysis: DiagramAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            LabeledContent("Type", value: analysis.diagramType)
            if let count = analysis.elementCount {
                LabeledContent("Elements", value: count.formatted())
            }
            if let count = analysis.connectionCount {
                LabeledContent("Connections", value: count.formatted())
            }
        }
    }

    private func issues(_ issues: [DiagramIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Warnings", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(issues) { issue in
                Button {
                    if let line = issue.line {
                        onNavigate(line)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text(issue.message)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(issue.line == nil)
            }
        }
    }

    private func selectedItem(in analysis: DiagramAnalysis) -> DiagramOutlineItem? {
        guard let selection else { return nil }
        return analysis.item(id: selection)
    }
}
