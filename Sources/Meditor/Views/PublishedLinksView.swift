import AppKit
import SwiftUI

/// "My published links" — lists everything the user has shared, with actions to
/// open, copy, or unpublish (which deletes it from the server early).
struct PublishedLinksView: View {
    @ObservedObject private var store = PublishedLinkStore.shared
    @State private var working: Set<String> = []
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Published Links").font(.headline)
                Spacer()
                Button("Clear Expired") {
                    store.clearExpired()
                }
                .disabled(!store.links.contains(where: \.isExpired))
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if store.links.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.links) { link in
                        row(link)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .alert("Unpublish failed", isPresented: errorAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No published links yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ link: PublishedLink) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.url)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text("Created \(link.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    if link.isExpired {
                        Text("Expired")
                    } else {
                        Text("Expires \(link.expiresAt.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if working.contains(link.id) {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button("Copy link") { copy(link.url) }
                    Button("Open") { open(link.url) }
                    Divider()
                    Button(link.isExpired ? "Remove" : "Unpublish", role: .destructive) {
                        unpublish(link)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .opacity(link.isExpired ? 0.55 : 1)
    }

    // MARK: - Actions

    private func unpublish(_ link: PublishedLink) {
        // Expired links are already gone server-side; just forget locally.
        guard !link.isExpired, let token = store.deleteToken(for: link.id) else {
            store.forget(link.id)
            return
        }
        working.insert(link.id)
        Task {
            defer { working.remove(link.id) }
            do {
                let baseURL = try ShareServiceURL(publishedLink: link.url)
                try await ShareClient(baseURL: baseURL).unpublish(id: link.id, deleteToken: token)
                store.forget(link.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
