import AppKit

// Flat fallback for AppIcon.icon (used when Xcode's actool is missing):
// gradient from icon.json, then the layer PNGs with a soft shadow, clipped to the squircle.
// Run: swift icon.swift → icon_1024.png (then iconutil)
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle (macOS grid: 824pt body, 100pt margin); the layer canvas maps onto the body
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
NSColor.white.setFill(); shape.fill()
ctx.restoreGState()
shape.addClip()

// Fill: white at the top to light grey at 70 % height
let top = NSColor(displayP3Red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
let bottom = NSColor(displayP3Red: 0.90, green: 0.91, blue: 0.94, alpha: 1)
NSGradient(colors: [top, bottom])!.draw(from: CGPoint(x: body.midX, y: body.maxY),
                                         to: CGPoint(x: body.midX, y: body.maxY - body.height * 0.7),
                                         options: [.drawsAfterEndingLocation])

// Layers back to front: page is translucent glass, photo opaque
for (name, alpha) in [("page", 0.8), ("photo", 1.0)] {
    let layer = NSImage(contentsOfFile: "AppIcon.icon/Assets/\(name).png")!
    ctx.saveGState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.25); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -12); s.set()
    layer.draw(in: body, from: .zero, operation: .sourceOver, fraction: alpha)
    ctx.restoreGState()
}
NSGraphicsContext.current = nil

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
