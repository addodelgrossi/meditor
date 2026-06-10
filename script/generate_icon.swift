#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
let output = assets.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw NSError(domain: "Icon", code: 1) }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let s = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    let outer = NSBezierPath(roundedRect: NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [
        NSColor(red: 0.035, green: 0.07, blue: 0.13, alpha: 1),
        NSColor(red: 0.08, green: 0.10, blue: 0.24, alpha: 1)
    ])!.draw(in: outer, angle: -45)

    let glass = NSBezierPath(roundedRect: NSRect(x: s * 0.11, y: s * 0.11, width: s * 0.78, height: s * 0.78), xRadius: s * 0.18, yRadius: s * 0.18)
    NSColor.white.withAlphaComponent(0.055).setFill()
    glass.fill()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    glass.lineWidth = max(1, s * 0.008)
    glass.stroke()

    let points = [
        NSPoint(x: s * 0.26, y: s * 0.29),
        NSPoint(x: s * 0.26, y: s * 0.69),
        NSPoint(x: s * 0.50, y: s * 0.48),
        NSPoint(x: s * 0.74, y: s * 0.69),
        NSPoint(x: s * 0.74, y: s * 0.29)
    ]
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.line(to: points[3])
    path.line(to: points[4])
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = s * 0.07
    NSGradient(colors: [
        NSColor(red: 0.16, green: 0.82, blue: 0.86, alpha: 1),
        NSColor(red: 0.33, green: 0.39, blue: 0.96, alpha: 1)
    ])!.draw(in: path, angle: 0)

    for point in points {
        let radius = s * 0.045
        let node = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        NSColor.white.setFill()
        node.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    return data
}

for (name, size) in entries {
    try drawIcon(size: size).write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }

try? FileManager.default.removeItem(at: iconset)
print("Generated \(output.path)")
