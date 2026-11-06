#!/usr/bin/swift
// Renders the 1024×1024 app icon master to Resources/AppIcon-source.png.
// `make icon` (Scripts/make_icon.swift) then downsamples it into AppIcon.icns.
//
// Layout follows Apple's macOS icon grid: an 824×824 rounded-square ("squircle")
// tile centred on a 1024 canvas, with a soft drop shadow in the margin.
//
//   swift Scripts/render_icon.swift [output.png] [canvasSize]

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outputPath = args.count > 1 ? args[1] : "Resources/AppIcon-source.png"
let size = CGFloat(args.count > 2 ? Double(args[2]) ?? 1024 : 1024)
let s = size / 1024  // scale factor; all geometry below is in 1024-pt units

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map(\.0) as CFArray,
               locations: stops.map(\.1))!
}

/// Superellipse ("squircle") close to Apple's continuous-corner icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), si = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (si < 0 ? -1 : 1) * pow(abs(si), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Shield: gently sloped top with rounded shoulders, sides curving to a point.
func shield(center: CGPoint, width w: CGFloat, height h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let cx = center.x, cy = center.y
    let top = cy + h / 2, bottom = cy - h / 2
    let left = cx - w / 2, right = cx + w / 2
    let shoulderY = top - h * 0.07
    let corner = w * 0.13
    p.move(to: CGPoint(x: cx, y: top))
    p.addArc(tangent1End: CGPoint(x: right, y: shoulderY), tangent2End: CGPoint(x: right, y: cy), radius: corner)
    p.addLine(to: CGPoint(x: right, y: cy + h * 0.04))
    p.addCurve(to: CGPoint(x: cx, y: bottom),
               control1: CGPoint(x: right, y: cy - h * 0.24),
               control2: CGPoint(x: cx + w * 0.20, y: bottom + h * 0.07))
    p.addCurve(to: CGPoint(x: left, y: cy + h * 0.04),
               control1: CGPoint(x: cx - w * 0.20, y: bottom + h * 0.07),
               control2: CGPoint(x: left, y: cy - h * 0.24))
    p.addArc(tangent1End: CGPoint(x: left, y: shoulderY), tangent2End: CGPoint(x: cx, y: top), radius: corner)
    p.closeSubpath()
    return p
}

/// Microphone glyph: capsule head, U-shaped yoke, stem and base, as one fill.
func microphone(center: CGPoint, scale k: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let headW = 118 * k, headH = 206 * k
    let headRect = CGRect(x: center.x - headW / 2, y: center.y - headH / 2 + 46 * k,
                          width: headW, height: headH)
    p.addRoundedRect(in: headRect, cornerWidth: headW / 2, cornerHeight: headW / 2)

    let stroke = 26 * k
    let yoke = CGMutablePath()
    let yokeR = 100 * k
    let yokeCenter = CGPoint(x: center.x, y: headRect.minY + headW / 2 + 4 * k)
    yoke.addArc(center: yokeCenter, radius: yokeR, startAngle: .pi, endAngle: 0, clockwise: false)
    // Short vertical lead-ins so the yoke hugs the capsule.
    let yokeFull = CGMutablePath()
    yokeFull.move(to: CGPoint(x: yokeCenter.x - yokeR, y: yokeCenter.y + 30 * k))
    yokeFull.addLine(to: CGPoint(x: yokeCenter.x - yokeR, y: yokeCenter.y))
    yokeFull.addPath(yoke)
    yokeFull.addLine(to: CGPoint(x: yokeCenter.x + yokeR, y: yokeCenter.y + 30 * k))
    p.addPath(yokeFull.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))

    let stemTop = yokeCenter.y - yokeR
    let stemBottom = stemTop - 62 * k
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: center.x, y: stemTop))
    stem.addLine(to: CGPoint(x: center.x, y: stemBottom))
    stem.move(to: CGPoint(x: center.x - 70 * k, y: stemBottom))
    stem.addLine(to: CGPoint(x: center.x + 70 * k, y: stemBottom))
    p.addPath(stem.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))
    return p
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)
ctx.setShouldAntialias(true)

// Tile: 824 squircle, nudged up slightly so the shadow sits in the bottom margin.
let tileRect = CGRect(x: 100, y: 112, width: 824, height: 824)
let tile = squircle(in: tileRect)

// Drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(rgb(0x0B7A55))
ctx.fillPath()
ctx.restoreGState()

// Background: emerald gradient, lighter at the top.
ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
ctx.drawLinearGradient(
    gradient([(rgb(0x3EE6A5), 0), (rgb(0x14B87F), 0.55), (rgb(0x07805A), 1)]),
    start: CGPoint(x: 512, y: tileRect.maxY), end: CGPoint(x: 512, y: tileRect.minY), options: [])
// Soft top light.
ctx.drawRadialGradient(
    gradient([(rgb(0xFFFFFF, 0.28), 0), (rgb(0xFFFFFF, 0), 1)]),
    startCenter: CGPoint(x: 512, y: tileRect.maxY + 40), startRadius: 0,
    endCenter: CGPoint(x: 512, y: tileRect.maxY + 40), endRadius: 560, options: [])
ctx.restoreGState()

// Thin inner rim highlight for a glassy edge.
ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
ctx.addPath(tile)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.22))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Frosted-glass shield.
let shieldPath = shield(center: CGPoint(x: 512, y: 516), width: 500, height: 590)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x034D35, 0.30))
ctx.addPath(shieldPath)
ctx.setFillColor(rgb(0xFFFFFF, 0.16))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shieldPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([(rgb(0xFFFFFF, 0.30), 0), (rgb(0xFFFFFF, 0.06), 1)]),
    start: CGPoint(x: 512, y: 812), end: CGPoint(x: 512, y: 212), options: [])
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shieldPath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.55))
ctx.setLineWidth(5)
ctx.strokePath()
ctx.restoreGState()

// Microphone: solid white with a faint mint gradient and a soft shadow.
let mic = microphone(center: CGPoint(x: 512, y: 520), scale: 1.0)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x024A33, 0.40))
ctx.addPath(mic)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(mic)
ctx.clip()
ctx.drawLinearGradient(
    gradient([(rgb(0xFFFFFF), 0), (rgb(0xF0FFF8), 1)]),
    start: CGPoint(x: 512, y: 760), end: CGPoint(x: 512, y: 300), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
print("✓ \(outputPath)")
