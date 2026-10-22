import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Regenerate the Moonbeam app icons: swift design/AppIcon.swift <output-directory>
// Each variant is an opaque, full-bleed 1024px square; iOS applies the corner mask.
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(name: String, background: [UInt32], foreground: UInt32) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    let gradient = CGGradient(colorsSpace: space,
                              colors: background.map { rgb($0) } as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 170, y: 100),
                           end: CGPoint(x: 850, y: 1024),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Two intersecting circles leave a slender crescent, opening toward the rays.
    // Clip the cutout rather than painting over it, preserving the background gradient.
    ctx.saveGState()
    let clip = CGMutablePath()
    clip.addRect(CGRect(x: 0, y: 0, width: size, height: size))
    clip.addEllipse(in: CGRect(x: 280, y: 205, width: 540, height: 540))
    ctx.addPath(clip)
    ctx.clip(using: .evenOdd)
    ctx.setFillColor(rgb(foreground))
    ctx.fillEllipse(in: CGRect(x: 200, y: 242, width: 540, height: 540))
    ctx.restoreGState()

    // Align the parallel rays with the line between the two circle centers.
    // This runs through the thickest part of the crescent and its opening.
    ctx.setStrokeColor(rgb(foreground))
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    let angle = atan2(CGFloat(-37), CGFloat(80))
    let direction = CGPoint(x: cos(angle), y: sin(angle))
    let normal = CGPoint(x: -direction.y, y: direction.x)
    for (offset, length): (CGFloat, CGFloat) in [(-60, 210), (0, 270), (60, 240)] {
        let start = CGPoint(x: 470 + 150 * direction.x + offset * normal.x,
                            y: 512 + 150 * direction.y + offset * normal.y)
        ctx.move(to: start)
        ctx.addLine(to: CGPoint(x: start.x + length * direction.x,
                               y: start.y + length * direction.y))
        ctx.strokePath()
    }

    let url = outDir.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Unable to write \(name)")
}

render(name: "AppIcon.png", background: [0x1B102D, 0x090610], foreground: 0xEEE6FF)
render(name: "AppIcon-Dark.png", background: [0x140C23, 0x06040B], foreground: 0xE6DCFA)
render(name: "AppIcon-Tinted.png", background: [0x191919, 0x070707], foreground: 0xEEEEEE)
