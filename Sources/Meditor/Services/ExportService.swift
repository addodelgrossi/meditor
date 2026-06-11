import AppKit
import UniformTypeIdentifiers

@MainActor
enum ExportService {
    static func export(
        svg: String,
        format: ExportFormat,
        scale: ExportScale,
        background: ExportBackground,
        suggestedName: String = "Diagram"
    ) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [contentType(for: format)]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data = try data(
            svg: svg,
            format: format,
            scale: scale,
            background: background
        )
        try data.write(to: url, options: .atomic)
    }

    static func copySVGText(_ svg: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(svg, forType: .string)
    }

    static func copyMarkdownBlock(_ source: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagramSourceTools.markdownBlock(for: source), forType: .string)
    }

    static func copyImage(_ svg: String, scale: ExportScale, background: ExportBackground) throws {
        let png = try pngData(svg: svg, scale: scale, background: background)
        let pdf = try pdfData(svg: svg, background: background)
        let svgData = try svgData(svg: svg, background: background)
        guard let image = NSImage(data: png), let tiff = image.tiffRepresentation else {
            throw ExportError.rasterizationFailed
        }

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        item.setData(pdf, forType: .pdf)
        item.setData(svgData, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else {
            throw ExportError.clipboardWriteFailed
        }
    }

    static func data(
        svg: String,
        format: ExportFormat,
        scale: ExportScale,
        background: ExportBackground = .transparent
    ) throws -> Data {
        switch format {
        case .svg:
            return try svgData(svg: svg, background: background)
        case .png:
            return try pngData(svg: svg, scale: scale, background: background)
        case .pdf:
            return try pdfData(svg: svg, background: background)
        }
    }

    static func batchURLs(
        directory: URL,
        suggestedName: String,
        format: ExportFormat
    ) -> [(theme: MermaidTheme, url: URL)] {
        let baseName = safeFileName(suggestedName)
        return MermaidTheme.allCases.map { theme in
            (
                theme,
                directory.appendingPathComponent(
                    "\(baseName)-\(theme.rawValue).\(format.fileExtension)"
                )
            )
        }
    }

    static func writeBatch(_ outputs: [(url: URL, data: Data)]) throws {
        guard let directory = outputs.first?.url.deletingLastPathComponent() else { return }
        let stagingDirectory = directory.appendingPathComponent(
            ".meditor-export-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        var staged: [(source: URL, destination: URL)] = []
        for output in outputs {
            let stagedURL = stagingDirectory.appendingPathComponent(output.url.lastPathComponent)
            try output.data.write(to: stagedURL, options: .atomic)
            staged.append((stagedURL, output.url))
        }

        for item in staged {
            if FileManager.default.fileExists(atPath: item.destination.path) {
                _ = try FileManager.default.replaceItemAt(
                    item.destination,
                    withItemAt: item.source
                )
            } else {
                try FileManager.default.moveItem(at: item.source, to: item.destination)
            }
        }
    }

    private static func svgData(svg: String, background: ExportBackground) throws -> Data {
        let output: String
        if let color = background.svgColor {
            guard let openingTagEnd = svg.firstIndex(of: ">") else {
                throw ExportError.invalidSVG
            }
            let rectangle = #"<rect width="100%" height="100%" fill="\#(color)"/>"#
            output = String(svg[...openingTagEnd]) + rectangle + String(svg[svg.index(after: openingTagEnd)...])
        } else {
            output = svg
        }
        guard let data = output.data(using: .utf8) else {
            throw ExportError.invalidSVG
        }
        return data
    }

    private static func pngData(svg: String, scale: ExportScale, background: ExportBackground) throws -> Data {
        let image = try image(from: svg)
        let width = max(Int(image.size.width * Double(scale.rawValue)), 1)
        let height = max(Int(image.size.height * Double(scale.rawValue)), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.rasterizationFailed
        }

        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        background.nsColor.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.rasterizationFailed
        }
        return data
    }

    private static func pdfData(svg: String, background: ExportBackground) throws -> Data {
        let image = try image(from: svg)
        let view = ExportImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.background = background.nsColor
        return view.dataWithPDF(inside: view.bounds)
    }

    private static func image(from svg: String) throws -> NSImage {
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
            throw ExportError.invalidSVG
        }
        return image
    }

    private static func contentType(for format: ExportFormat) -> UTType {
        switch format {
        case .svg: .svg
        case .png: .png
        case .pdf: .pdf
        }
    }

    private static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let components = name.components(separatedBy: invalid)
        let result = components.filter { !$0.isEmpty }.joined(separator: "-")
        return result.isEmpty ? "Diagram" : result
    }

    enum ExportError: LocalizedError {
        case invalidSVG
        case rasterizationFailed
        case clipboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidSVG: String(localized: "The diagram could not be converted.")
            case .rasterizationFailed: String(localized: "The image could not be created.")
            case .clipboardWriteFailed: String(localized: "The image could not be copied.")
            }
        }
    }
}

private final class ExportImageView: NSView {
    var image: NSImage?
    var background = NSColor.clear

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        background.setFill()
        bounds.fill()
        image?.draw(in: bounds)
    }
}

private extension ExportBackground {
    var nsColor: NSColor {
        switch self {
        case .transparent: .clear
        case .light: .white
        case .dark: NSColor(srgbRed: 0x11 / 255, green: 0x13 / 255, blue: 0x18 / 255, alpha: 1)
        }
    }

    var svgColor: String? {
        switch self {
        case .transparent: nil
        case .light: "#FFFFFF"
        case .dark: "#111318"
        }
    }
}
