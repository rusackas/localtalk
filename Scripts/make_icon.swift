#!/usr/bin/swift
import AppKit

_ = NSApplication.shared  // initialise AppKit for off-screen rendering

let iconsetPath = "Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Each entry: (logical pt size, pixel multiplier) → filename
let entries: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func renderPNG(pixels: Int) -> Data? {
    let s = pixels
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: s, pixelsHigh: s,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let fs = CGFloat(s)

    // Blue-to-indigo gradient background
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [CGColor(red: 0.22, green: 0.45, blue: 0.92, alpha: 1),
                  CGColor(red: 0.09, green: 0.18, blue: 0.68, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: 0, y: fs),
                          end: CGPoint(x: fs * 0.8, y: 0),
                          options: [])

    // mic.fill SF Symbol, white, centred at ~58% of icon size
    let symPt = fs * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: symPt, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let ms = mic.size
        mic.draw(in: NSRect(x: (fs - ms.width) / 2, y: (fs - ms.height) / 2,
                            width: ms.width, height: ms.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [.interlaced: false])
}

for (pt, scale) in entries {
    let pixels = pt * scale
    guard let png = renderPNG(pixels: pixels) else {
        print("✗ failed \(pixels)px"); continue
    }
    let suffix = scale == 2 ? "@2x" : ""
    let path = "\(iconsetPath)/icon_\(pt)x\(pt)\(suffix).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)")
}

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]
proc.launch()
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    print("✗ iconutil failed"); exit(1)
}
print("✓ Resources/AppIcon.icns")
