// make-icon.swift — render the app icon master PNG (1024x1024).
// Usage: swift scripts/make-icon.swift <output.png>
// A simple, native-feeling mark: indigo→blue squircle with a white database cylinder.
import AppKit

let size = 1024.0
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background squircle with diagonal gradient.
let inset = size * 0.07
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let corner = size * 0.225
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()
let colors = [
    NSColor(srgbRed: 0.36, green: 0.40, blue: 0.98, alpha: 1).cgColor,
    NSColor(srgbRed: 0.49, green: 0.27, blue: 0.86, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
ctx.restoreGState()

// White database cylinder.
let cw = size * 0.46
let cx = size / 2
let topY = size * 0.36
let botY = size * 0.64
let ry = cw * 0.15

ctx.setFillColor(NSColor.white.cgColor)
// Body
ctx.fill(CGRect(x: cx - cw / 2, y: topY, width: cw, height: botY - topY))
// Bottom cap
ctx.fillEllipse(in: CGRect(x: cx - cw / 2, y: botY - ry, width: cw, height: 2 * ry))
// Top cap
ctx.fillEllipse(in: CGRect(x: cx - cw / 2, y: topY - ry, width: cw, height: 2 * ry))

// Disk separation lines in the gradient tint.
ctx.setStrokeColor(NSColor(srgbRed: 0.42, green: 0.34, blue: 0.92, alpha: 1).cgColor)
ctx.setLineWidth(size * 0.020)
ctx.setLineCap(.round)
for fraction in [0.0, 0.5] {
    let y = topY + (botY - topY) * fraction
    ctx.strokeEllipse(in: CGRect(x: cx - cw / 2, y: y - ry, width: cw, height: 2 * ry))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
