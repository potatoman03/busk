// Renders the 1024x1024 opaque app icon: swift scripts/make_icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Background gradient: deep court orange to dark.
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.98, green: 0.45, blue: 0.13, alpha: 1),
    CGColor(red: 0.55, green: 0.16, blue: 0.05, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Ball.
let c = CGPoint(x: s * 0.5, y: s * 0.5)
let r = s * 0.30
ctx.setFillColor(CGColor(red: 0.99, green: 0.62, blue: 0.24, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
ctx.setStrokeColor(CGColor(red: 0.18, green: 0.07, blue: 0.03, alpha: 1))
ctx.setLineWidth(s * 0.022)
ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
ctx.move(to: CGPoint(x: c.x - r, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + r, y: c.y))
ctx.move(to: CGPoint(x: c.x, y: c.y - r)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + r))
ctx.strokePath()
ctx.addArc(center: CGPoint(x: c.x - r * 1.35, y: c.y), radius: r * 0.95, startAngle: -0.8, endAngle: 0.8, clockwise: false)
ctx.strokePath()
ctx.addArc(center: CGPoint(x: c.x + r * 1.35, y: c.y), radius: r * 0.95, startAngle: .pi - 0.8, endAngle: .pi + 0.8, clockwise: false)
ctx.strokePath()

// Arc trail above the ball.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
ctx.setLineWidth(s * 0.03)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [s * 0.05, s * 0.045])
ctx.addArc(center: CGPoint(x: s * 0.5, y: s * 0.40), radius: s * 0.40, startAngle: .pi * 0.88, endAngle: .pi * 0.12, clockwise: true)
ctx.strokePath()

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: out)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
