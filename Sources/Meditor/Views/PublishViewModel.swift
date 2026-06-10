import AppKit
import Foundation

@MainActor
final class PublishViewModel: ObservableObject {
    enum Phase {
        case form
        case publishing
        case published(ShareResponse)
        case failed(String)
    }

    @Published var duration: ShareDuration = .oneDay
    @Published private(set) var phase: Phase = .form

    private let code: String
    private let theme: MermaidTheme
    private let renderer: SocialPreviewRenderer
    private let store: PublishedLinkStore
    private let clientFactory: @MainActor () -> ShareClient

    init(
        code: String,
        theme: MermaidTheme,
        renderer: SocialPreviewRenderer = SocialPreviewRenderer(),
        store: PublishedLinkStore = .shared,
        clientFactory: @escaping @MainActor () -> ShareClient = { ShareClient() }
    ) {
        self.code = code
        self.theme = theme
        self.renderer = renderer
        self.store = store
        self.clientFactory = clientFactory
    }

    func publish() async {
        phase = .publishing
        do {
            let ogImage = try await renderer.render(code: code, theme: theme)
            let response = try await clientFactory().publish(
                code: code,
                theme: theme,
                ogImage: ogImage,
                duration: duration
            )
            copy(response.url)
            store.add(
                PublishedLink(
                    id: response.id,
                    url: response.url,
                    createdAt: Date(),
                    expiresAt: response.expiresAt,
                    ttlSeconds: duration.ttlSeconds
                ),
                deleteToken: response.deleteToken
            )
            phase = .published(response)
        } catch let error as PublishError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(PublishError.invalidResponse.localizedDescription)
        }
    }

    func tryAgain() {
        phase = .form
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
