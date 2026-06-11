import SwiftUI

struct RenameDiagramSheet: View {
    let source: String
    let diagramType: String
    let item: DiagramOutlineItem
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newIdentifier: String

    init(
        source: String,
        diagramType: String,
        item: DiagramOutlineItem,
        onRename: @escaping (String) -> Void
    ) {
        self.source = source
        self.diagramType = diagramType
        self.item = item
        self.onRename = onRename
        _newIdentifier = State(initialValue: item.identifier ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Diagram Identifier")
                .font(.headline)

            TextField("New identifier", text: $newIdentifier)
                .textFieldStyle(.roundedBorder)

            if let plan {
                Text("Rename \(item.identifier ?? item.title) to \(newIdentifier) in \(plan.replacementCount) occurrence(s) across \(plan.affectedLines.count) line(s).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Rename") {
                    onRename(newIdentifier)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private var plan: DiagramSourceTools.RenamePlan? {
        try? DiagramSourceTools.renamePlan(
            source: source,
            diagramType: diagramType,
            item: item,
            newIdentifier: newIdentifier
        )
    }

    private var errorMessage: String? {
        do {
            _ = try DiagramSourceTools.renamePlan(
                source: source,
                diagramType: diagramType,
                item: item,
                newIdentifier: newIdentifier
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
