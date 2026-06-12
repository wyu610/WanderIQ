// Renders the Planova app icon: teal gradient, white location pin,
// teal checkmark. Run from repo root:
//   swift scripts/make-icon.swift
//
// Renders into an alpha-free bitmap: App Store validation rejects app
// icons that contain an alpha channel (ITMS-90717).
import AppKit

let s = 1024
let ctx = CGContext(data: nil, width: s, height: s,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let sf = CGFloat(s)

let colors = [
    CGColor(red: 0.10, green: 0.52, blue: 0.65, alpha: 1),
    CGColor(red: 0.05, green: 0.30, blue: 0.40, alpha: 1)
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: sf),
                       end: CGPoint(x: sf, y: 0), options: [])

// White location pin: full circle head over a triangular tail.
// (Origin is bottom-left; +y is up.)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let cx: CGFloat = 512, cy: CGFloat = 600, r: CGFloat = 230
let tail = CGMutablePath()
tail.move(to: CGPoint(x: cx - 132, y: cy - 186))
tail.addLine(to: CGPoint(x: cx + 132, y: cy - 186))
tail.addLine(to: CGPoint(x: cx, y: 220))
tail.closeSubpath()
ctx.addPath(tail)
ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))

// Teal checkmark inside the pin head.
ctx.setStrokeColor(CGColor(red: 0.06, green: 0.34, blue: 0.44, alpha: 1))
ctx.setLineWidth(72)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: cx - 110, y: cy + 5))
ctx.addLine(to: CGPoint(x: cx - 30, y: cy - 80))
ctx.addLine(to: CGPoint(x: cx + 115, y: cy + 90))
ctx.strokePath()

let cgImage = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: cgImage)
let png = rep.representation(using: .png, properties: [:])!
let out = "Planova/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
