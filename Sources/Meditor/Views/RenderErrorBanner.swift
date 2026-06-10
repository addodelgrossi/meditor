import SwiftUI

struct RenderErrorBanner: View {
    let error: MermaidRenderError
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview paused")
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if error.line != nil {
                    Label("Go to error", systemImage: "arrow.right")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.orange.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Moves the cursor to the Mermaid syntax error")
    }

    private var detail: String {
        if let line = error.line {
            return String(localized: "Line \(line): \(error.message)")
        }
        return error.message
    }
}
