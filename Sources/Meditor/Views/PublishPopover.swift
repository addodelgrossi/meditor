import AppKit
import SwiftUI

/// Popover shown from the toolbar's Publish button. Lets the user pick a
/// lifetime, publishes the rendered diagram, and surfaces the resulting link.
struct PublishPopover: View {
    let code: String
    let theme: MermaidTheme
    let svg: String?

    @State private var duration: ShareDuration = .oneDay
    @State private var phase: Phase = .form
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case form
        case publishing
        case published(ShareResponse)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
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
                Picker("Expires after", selection: $duration) {
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
                publish()
            } label: {
                Text("Publish").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(svg == nil)
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
                Button("Copy link") { copy(response.url) }
                Button("Open") { openURL(response.url) }
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
                Button("Try again") { phase = .form }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func header(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    // MARK: - Actions

    private func publish() {
        guard let svg else { return }
        phase = .publishing
        Task {
            do {
                let response = try await PublishService().publish(
                    code: code,
                    theme: theme,
                    svg: svg,
                    duration: duration
                )
                copy(response.url)
                PublishedLinkStore.shared.add(
                    PublishedLink(
                        id: response.id,
                        url: response.url,
                        createdAt: Date(),
                        expiresAt: response.expiresAt
                    ),
                    deleteToken: response.deleteToken
                )
                phase = .published(response)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
