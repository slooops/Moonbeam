import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Moonbeam app icon generator: swift design/AppIcon.swift <outDir> [palette]
// Writes AppIcon.png (opaque), AppIcon-Dark.png and AppIcon-Tinted.png at 1024x1024.
// With palette "all", writes one light preview per palette instead.
let outDir = CommandLine.arguments[1]
let paletteArg = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "dusk"
let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Background gradient stops, top-left to bottom-right.
let palettes: [(String, [UInt32])] = [
    ("navy",     [0x2F55B8, 0x1A3378, 0x0C1838]),  // a softened take on the reference blue
    ("midnight", [0x23407F, 0x142650, 0x080F24]),  // deeper, closer to the night sky
    ("dusk",     [0x3A6FA8, 0x1F4A7A, 0x0E2340]),  // lighter steel blue
    ("ink",      [0x1C2A4A, 0x111A30, 0x070B16]),  // nearly black, just a hint of blue
]

func ccwContains(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> Bool {
    func norm(_ x: CGFloat) -> CGFloat { var y = x.truncatingRemainder(dividingBy: 2 * .pi); if y < 0 { y += 2 * .pi }; return y }
    return norm(t - a) < norm(b - a)
}

/// Circle (c1, r1) minus circle (c2, r2), built from two arcs.
func crescent(_ c1: CGPoint, _ r1: CGFloat, _ c2: CGPoint, _ r2: CGFloat) -> CGPath {
    let dx = c2.x - c1.x, dy = c2.y - c1.y
    let d = (dx * dx + dy * dy).squareRoot()
    let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    let h = (r1 * r1 - a * a).squareRoot()
    let mx = c1.x + a * dx / d, my = c1.y + a * dy / d
    let p1 = CGPoint(x: mx + h * dy / d, y: my - h * dx / d)
    let p2 = CGPoint(x: mx - h * dy / d, y: my + h * dx / d)
    func ang(_ p: CGPoint, _ c: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) }
    let away = atan2(-dy, -dx)
    let path = CGMutablePath()
    let o1 = ang(p1, c1), o2 = ang(p2, c1)
    path.move(to: p1)
    path.addArc(center: c1, radius: r1, startAngle: o1, endAngle: o2, clockwise: !ccwContains(o1, o2, away))
    let i2 = ang(p2, c2), i1 = ang(p1, c2)
    path.addArc(center: c2, radius: r2, startAngle: i2, endAngle: i1, clockwise: !ccwContains(i2, i1, away))
    path.closeSubpath()
    return path
}

let lineWidth: CGFloat = 52

/// The outline crescent, translated so its stroked bounds sit dead center.
let moon: CGPath = {
    let raw = crescent(CGPoint(x: 490, y: 540), 300, CGPoint(x: 650, y: 400), 262)
    let box = raw.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 1).boundingBoxOfPath
    var t = CGAffineTransform(translationX: S / 2 - box.midX, y: S / 2 - box.midY)
    return raw.copy(using: &t)!
}()

enum Variant { case light, dark, tinted }

func render(_ v: Variant, stops: [UInt32], to name: String) {
    let info = v == .light ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: info.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    if v == .light {
        let bg = CGGradient(colorsSpace: space, colors: stops.map { rgb($0) } as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 0), end: CGPoint(x: 700, y: S),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    let line: CGColor, glow: CGColor, haloColor: CGColor
    switch v {
    case .light:  line = rgb(0xFFF4E0); glow = rgb(0xFFD79A, 0.5);  haloColor = rgb(0xFFE2B0, 0.14)
    case .dark:   line = rgb(0xFFE9C4); glow = rgb(0xFFD79A, 0.45); haloColor = rgb(0xFFE2B0, 0.10)
    case .tinted: line = rgb(0xFFFFFF); glow = rgb(0xFFFFFF, 0.35); haloColor = rgb(0xFFFFFF, 0.10)
    }

    let c = CGPoint(x: S / 2, y: S / 2)
    let halo = CGGradient(colorsSpace: space, colors: [haloColor, rgb(0xFFE2B0, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: c, startRadius: 0, endCenter: c, endRadius: 470, options: [])

    ctx.setShadow(offset: .zero, blur: 50, color: glow)
    ctx.addPath(moon)
    ctx.setStrokeColor(line); ctx.setLineWidth(lineWidth)
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.strokePath()

    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

if paletteArg == "all" {
    for (name, stops) in palettes { render(.light, stops: stops, to: "C-\(name).png") }
} else {
    let stops = palettes.first { $0.0 == paletteArg }!.1
    render(.light, stops: stops, to: "AppIcon.png")
    render(.dark, stops: stops, to: "AppIcon-Dark.png")
    render(.tinted, stops: stops, to: "AppIcon-Tinted.png")
}
