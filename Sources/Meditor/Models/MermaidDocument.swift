import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mermaidSource = UTType(
        exportedAs: "com.addodelgrossi.meditor.mermaid",
        conformingTo: .plainText
    )
}

struct MermaidDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.mermaidSource, .plainText]
    static let writableContentTypes: [UTType] = [.mermaidSource, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encodedData())
    }

    func encodedData() throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
