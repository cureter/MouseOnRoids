// Zeichnet das App-Icon (1024×1024 PNG). Aufruf: swift tools/make-icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.last(where: { $0.hasSuffix(".png") }) ?? "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Hintergrund: macOS-Raster (824 px Fläche, 100 px Rand), Verlauf Orange → Violett
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(0x6A1BD8).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [color(0xFF7A2F), color(0xF0306B), color(0x7B2CF5)],
           atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -60)
// dezenter Glanz oben
NSGradient(starting: .white.withAlphaComponent(0.22), ending: .white.withAlphaComponent(0))!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Tempo-Streifen links neben der Maus
let streaks: [(y: CGFloat, x: CGFloat, w: CGFloat, a: CGFloat)] = [
    (610, 190, 170, 0.85), (520, 160, 200, 0.95), (430, 205, 150, 0.75),
]
for s in streaks {
    color(0xFFFFFF, s.a).setFill()
    NSBezierPath(roundedRect: NSRect(x: s.x, y: s.y, width: s.w, height: 34), xRadius: 17, yRadius: 17).fill()
}

// Maus (leicht schräg, als würde sie nach rechts oben "abheben")
ctx.saveGState()
ctx.translateBy(x: 590, y: 512)
ctx.rotate(by: -0.26)
let mouse = NSRect(x: -175, y: -265, width: 350, height: 530)
let mousePath = NSBezierPath(roundedRect: mouse, xRadius: 175, yRadius: 190)

NSGraphicsContext.saveGraphicsState()
let mShadow = NSShadow()
mShadow.shadowColor = color(0x2A0060, 0.45)
mShadow.shadowBlurRadius = 30
mShadow.shadowOffset = NSSize(width: 10, height: -18)
mShadow.set()
color(0xFFFFFF).setFill()
mousePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
mousePath.addClip()
NSGradient(starting: color(0xFFFFFF), ending: color(0xE6E0F5))!.draw(in: mouse, angle: -90)
// Tastentrennung
color(0xC9BFE3).setFill()
NSBezierPath(rect: NSRect(x: -4, y: 60, width: 8, height: 210)).fill()
NSBezierPath(rect: NSRect(x: -175, y: 56, width: 350, height: 8)).fill()
NSGraphicsContext.restoreGraphicsState()

// Scrollrad
NSGradient(starting: color(0xFF7A2F), ending: color(0xF0306B))!
    .draw(in: NSBezierPath(roundedRect: NSRect(x: -26, y: 120, width: 52, height: 110), xRadius: 26, yRadius: 26),
          angle: -90)

// Blitz
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 30, y: 10))
bolt.line(to: NSPoint(x: -70, y: -120))
bolt.line(to: NSPoint(x: -8, y: -120))
bolt.line(to: NSPoint(x: -38, y: -215))
bolt.line(to: NSPoint(x: 75, y: -75))
bolt.line(to: NSPoint(x: 12, y: -75))
bolt.close()
NSGradient(starting: color(0xFF7A2F), ending: color(0x7B2CF5))!.draw(in: bolt, angle: -90)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Icon geschrieben: \(out)")
