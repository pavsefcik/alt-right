#!/usr/bin/env swift
// Renders the app icon: the same blue gradient tile and “cursor click” symbol the
// app uses in its settings window and in Finder, so there is only one icon design.
//
// usage:
//   swift scripts/gen_icon.swift icon.png     # preview PNG
//   swift scripts/gen_icon.swift AppIcon.icns # full .icns (via iconutil)
import AppKit

let side: CGFloat = 1024
let inset: CGFloat = 84          // macOS icon grid padding
let radius: CGFloat = 200

// MARK: - Tile with the SF Symbol

func makeSymbolImage() -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return nil }

    let size = symbol.size
    let image = NSImage(size: size)
    image.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: size))
    // Tint the symbol white without touching anything transparent.
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    image.unlockFocus()
    return image
}

func makeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.29, blue: 0.82, alpha: 1),
    ])!
    gradient.draw(in: tilePath, angle: -90)

    if let symbol = makeSymbolImage() {
        let symbolSize = symbol.size
        let origin = NSPoint(
            x: (side - symbolSize.width) / 2,
            y: (side - symbolSize.height) / 2
        )
        symbol.draw(in: NSRect(origin: origin, size: symbolSize))
    }

    image.unlockFocus()
    return image
}

// MARK: - Output

func pngData(from image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let data = pngData(from: image, pixels: pixels) else {
        throw NSError(domain: "AltRightIcon", code: 1)
    }
    try data.write(to: url)
}

let icon = makeIcon()
let output = URL(fileURLWithPath: CommandLine.arguments[1])

if output.pathExtension.lowercased() == "icns" {
    let fileManager = FileManager.default
    let iconset = fileManager.temporaryDirectory
        .appendingPathComponent("AltRightIcon-\(UUID().uuidString).iconset", isDirectory: true)
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: iconset) }

    let variants: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for (pixels, name) in variants {
        try writePNG(icon, pixels: pixels, to: iconset.appendingPathComponent(name))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "AltRightIcon", code: 2)
    }
} else {
    try writePNG(icon, pixels: Int(side), to: output)
}
