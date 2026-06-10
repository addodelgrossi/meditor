import AppKit
import UniformTypeIdentifiers

@MainActor
enum ExportService {
    static func export(
        svg: String,
        format: ExportFormat,
        scale: ExportScale,
        transparentBackground: Bool = true,
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
            transparentBackground: transparentBackground
        )
        try data.write(to: url, options: .atomic)
    }

    static func copySVG(_ svg: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(svg, forType: .string)
    }

    static func copyPNG(_ svg: String, scale: ExportScale, transparentBackground: Bool = true) throws {
        let data = try pngData(svg: svg, scale: scale, transparentBackground: transparentBackground)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
    }

    static func data(
        svg: String,
        format: ExportFormat,
        scale: ExportScale,
        transparentBackground: Bool = true
    ) throws -> Data {
        switch format {
        case .svg:
            guard let data = svg.data(using: .utf8) else { throw ExportError.invalidSVG }
            return data
        case .png:
            return try pngData(svg: svg, scale: scale, transparentBackground: transparentBackground)
        case .pdf:
            return try pdfData(svg: svg)
        }
    }

    private static func pngData(svg: String, scale: ExportScale, transparentBackground: Bool) throws -> Data {
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
        (transparentBackground ? NSColor.clear : NSColor.white).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.rasterizationFailed
        }
        return data
    }

    private static func pdfData(svg: String) throws -> Data {
        let image = try image(from: svg)
        let view = ExportImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
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

    enum ExportError: LocalizedError {
        case invalidSVG
        case rasterizationFailed

        var errorDescription: String? {
            switch self {
            case .invalidSVG: String(localized: "The diagram could not be converted.")
            case .rasterizationFailed: String(localized: "The image could not be created.")
            }
        }
    }
}

private final class ExportImageView: NSView {
    var image: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image?.draw(in: bounds)
    }
}
