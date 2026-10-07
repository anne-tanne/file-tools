import AppKit

// Draws the layers of AppIcon.icon (Icon Composer format). The canvas is the whole icon shape
// (1024 = edge of the squircle), no background and no shadows: macOS adds glass, shadow and the
// light gradient fill from icon.json itself. Run: swift icon_layers.swift
//
// Design: an orange photo and a blue glass page overlapping, tilted apart.

let size: CGFloat = 1024
let dir = "AppIcon.icon/Assets"
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func layer(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}

func rotated(_ center: CGPoint, _ angle: CGFloat, _ body: () -> Void) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: angle * .pi / 180)
    body()
    ctx.restoreGState()
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

// Rounded card of size w × h around the (rotated) origin
func card(_ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}

// White SF Symbol centred on the (rotated) origin, offset by dy
func symbol(_ name: String, _ pointSize: CGFloat, _ weight: NSFont.Weight, dy: CGFloat = 0) {
    let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))!
    let white = NSImage(size: sym.size, flipped: false) { r in sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
    white.draw(in: CGRect(x: -sym.size.width / 2, y: -sym.size.height / 2 + dy, width: sym.size.width, height: sym.size.height))
}

// Blue page in front (glass, partly see-through)
layer("page") {
    rotated(CGPoint(x: 616, y: 498), 8) {
        card(496, 637, 83, color(60, 130, 255))
        symbol("doc.text", 236, .medium, dy: -36)
    }
}

// Orange photo behind
layer("photo") {
    rotated(CGPoint(x: 403, y: 545), -8) {
        card(519, 519, 94, color(255, 140, 50))
        symbol("photo", 248, .semibold)
    }
}
print("layers written to \(dir)")
