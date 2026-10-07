import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background (macOS grid: 824pt body, 100pt margin)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
NSColor.white.setFill(); bg.fill()
ctx.restoreGState()
bg.addClip()
NSGradient(colors: [NSColor(red: 1.00, green: 0.55, blue: 0.30, alpha: 1),
                    NSColor(red: 0.93, green: 0.27, blue: 0.48, alpha: 1),
                    NSColor(red: 0.45, green: 0.30, blue: 0.85, alpha: 1)])!
    .draw(in: body, angle: -60)

// Back photo card (tilted)
func card(_ rect: CGRect, angle: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY); ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -rect.width/2, y: -rect.height/2, width: rect.width, height: rect.height)
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.25); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -12); s.set()
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40).fill()
    ctx.restoreGState()
}
card(CGRect(x: 250, y: 330, width: 440, height: 360), angle: 10, alpha: 0.55)

// Front photo card with picture
let front = CGRect(x: 300, y: 290, width: 460, height: 380)
ctx.saveGState()
ctx.translateBy(x: front.midX, y: front.midY); ctx.rotate(by: -4 * .pi / 180)
let fr = CGRect(x: -front.width/2, y: -front.height/2, width: front.width, height: front.height)
let s2 = NSShadow(); s2.shadowColor = NSColor.black.withAlphaComponent(0.3); s2.shadowBlurRadius = 36; s2.shadowOffset = NSSize(width: 0, height: -14); s2.set()
NSColor.white.setFill(); NSBezierPath(roundedRect: fr, xRadius: 40, yRadius: 40).fill()
NSShadow().set()
let pic = fr.insetBy(dx: 28, dy: 28)
let picPath = NSBezierPath(roundedRect: pic, xRadius: 22, yRadius: 22)
picPath.addClip()
NSGradient(colors: [NSColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1), NSColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1)])!.draw(in: pic, angle: 90)
// sun
NSColor(red: 1.0, green: 0.80, blue: 0.25, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: pic.maxX - 130, y: pic.maxY - 125, width: 80, height: 80)).fill()
// mountains
let m1 = NSBezierPath(); m1.move(to: CGPoint(x: pic.minX - 10, y: pic.minY))
m1.line(to: CGPoint(x: pic.minX + 130, y: pic.minY + 190)); m1.line(to: CGPoint(x: pic.minX + 300, y: pic.minY)); m1.close()
NSColor(red: 0.20, green: 0.55, blue: 0.45, alpha: 1).setFill(); m1.fill()
let m2 = NSBezierPath(); m2.move(to: CGPoint(x: pic.minX + 150, y: pic.minY))
m2.line(to: CGPoint(x: pic.minX + 290, y: pic.minY + 140)); m2.line(to: CGPoint(x: pic.maxX + 10, y: pic.minY)); m2.close()
NSColor(red: 0.13, green: 0.42, blue: 0.38, alpha: 1).setFill(); m2.fill()
ctx.restoreGState()

// Convert badge
let badge = CGRect(x: 600, y: 170, width: 230, height: 230)
ctx.saveGState()
let s3 = NSShadow(); s3.shadowColor = NSColor.black.withAlphaComponent(0.3); s3.shadowBlurRadius = 24; s3.shadowOffset = NSSize(width: 0, height: -8); s3.set()
NSColor.white.setFill(); NSBezierPath(ovalIn: badge).fill()
ctx.restoreGState()
let cfg = NSImage.SymbolConfiguration(pointSize: 130, weight: .bold)
if let sym = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r); NSColor(red: 0.90, green: 0.30, blue: 0.45, alpha: 1).set(); r.fill(using: .sourceAtop); return true }
    let w = sym.size.width, h = sym.size.height
    tinted.draw(in: CGRect(x: badge.midX - w/2, y: badge.midY - h/2, width: w, height: h))
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
