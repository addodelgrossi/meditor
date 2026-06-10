import SwiftUI

/// Popover shown from the toolbar's Publish button. Lets the user pick a
/// lifetime, publishes the rendered diagram, and surfaces the resulting link.
struct PublishPopover: View {
    @StateObject private var viewModel: PublishViewModel
    @Environment(\.dismiss) private var dismiss

    init(code: String, theme: MermaidTheme) {
        _viewModel = StateObject(wrappedValue: PublishViewModel(code: code, theme: theme))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch viewModel.phase {
            case .form:
                formContent
            case .publishing:
                publishingContent
            case let .published(response):
                publishedContent(response)
            case let .failed(message):
                failedContent(message)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    // MARK: - Phases

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Publish diagram", systemImage: "square.and.arrow.up.on.square")

            VStack(alignment: .leading, spacing: 6) {
                Text("Expires after")
                    .font(.subheadline.weight(.medium))
                Picker("Expires after", selection: $viewModel.duration) {
                    ForEach(ShareDuration.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Label {
                Text("Anyone with the link can view this diagram until it expires.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.publish() }
            } label: {
                Text("Publish").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var publishingContent: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Publishing…")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private func publishedContent(_ response: ShareResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Link copied", systemImage: "checkmark.circle.fill")

            Text(response.url)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Text("Expires \(response.expiresAt.formatted(.relative(presentation: .named))).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Copy link") { viewModel.copy(response.url) }
                Button("Open") { viewModel.open(response.url) }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Couldn't publish", systemImage: "exclamationmark.triangle.fill")
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Try again") { viewModel.tryAgain() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func header(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

}
