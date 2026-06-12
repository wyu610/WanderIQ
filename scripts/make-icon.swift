// Renders the Planova app icon: teal gradient, white location pin,
// teal checkmark. Run from repo root:
//   swift scripts/make-icon.swift
import AppKit

let s: CGFloat = 1024
let image = NSImage(size: NSSize(width: s, height: s))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let colors = [
    CGColor(red: 0.10, green: 0.52, blue: 0.65, alpha: 1),
    CGColor(red: 0.05, green: 0.30, blue: 0.40, alpha: 1)
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s),
                       end: CGPoint(x: s, y: 0), options: [])

// White location pin: circle head + tapering point.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let cx: CGFloat = 512, cy: CGFloat = 580, r: CGFloat = 230
let pin = CGMutablePath()
pin.addArc(center: CGPoint(x: cx, y: cy), radius: r,
           startAngle: .pi * 1.25, endAngle: .pi * -0.25, clockwise: false)
pin.addLine(to: CGPoint(x: cx, y: cy - r - 210))
pin.closeSubpath()
ctx.addPath(pin)
ctx.fillPath()

// Teal checkmark inside the pin head.
ctx.setStrokeColor(CGColor(red: 0.06, green: 0.34, blue: 0.44, alpha: 1))
ctx.setLineWidth(72)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: cx - 105, y: cy + 10))
ctx.addLine(to: CGPoint(x: cx - 25, y: cy - 75))
ctx.addLine(to: CGPoint(x: cx + 120, y: cy + 95))
ctx.strokePath()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
let out = "Planova/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
