#!/usr/bin/swift
import Foundation

let sourcePath = "Resources/AppIcon-source.png"
let iconsetPath = "Resources/AppIcon.iconset"

try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let entries: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func sips(from source: String, to output: String, size: Int) {
    let p = Process()
    p.launchPath = "/usr/bin/sips"
    p.arguments = ["-z", "\(size)", "\(size)", source, "--out", output]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    p.launch(); p.waitUntilExit()
}

for (pt, scale) in entries {
    let suffix = scale == 2 ? "@2x" : ""
    let out = "\(iconsetPath)/icon_\(pt)x\(pt)\(suffix).png"
    sips(from: sourcePath, to: out, size: pt * scale)
    print("✓ \(out)")
}

let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]
iconutil.launch(); iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else { print("✗ iconutil failed"); exit(1) }
print("✓ Resources/AppIcon.icns")
