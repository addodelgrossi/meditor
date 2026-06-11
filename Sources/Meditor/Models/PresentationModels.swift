import Foundation

struct PresentationSlide: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var code: String

    init(id: UUID = UUID(), title: String, code: String) {
        self.id = id
        self.title = title
        self.code = code
    }
}

struct PresentationDeck: Codable, Hashable, Identifiable {
    let id: UUID
    var slides: [PresentationSlide]
    var theme: MermaidTheme

    init(id: UUID = UUID(), slides: [PresentationSlide], theme: MermaidTheme) {
        self.id = id
        self.slides = slides
        self.theme = theme
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        slides.move(fromOffsets: offsets, toOffset: destination)
    }

    mutating func remove(at offsets: IndexSet) {
        slides.remove(atOffsets: offsets)
    }
}

struct PresentationPosition: Equatable {
    private(set) var index: Int
    let count: Int

    init(index: Int = 0, count: Int) {
        self.count = count
        self.index = min(max(index, 0), max(count - 1, 0))
    }

    var canGoPrevious: Bool { index > 0 }
    var canGoNext: Bool { index + 1 < count }

    mutating func goPrevious() {
        guard canGoPrevious else { return }
        index -= 1
    }

    mutating func goNext() {
        guard canGoNext else { return }
        index += 1
    }
}

enum PresentationDeckLoader {
    static func slides(from urls: [URL]) throws -> [PresentationSlide] {
        try urls.map { url in
            let data = try Data(contentsOf: url)
            let document = try MermaidDocument(data: data)
            return PresentationSlide(
                title: url.deletingPathExtension().lastPathComponent,
                code: document.text
            )
        }
    }
}
