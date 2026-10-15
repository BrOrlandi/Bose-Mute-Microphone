// Renders Resources/AppIcon.icns: headphones over a muted microphone.
// Drawn with plain Core Graphics paths (SF Symbols may not be used in app icons).
// Usage: swift scripts/make-icon.swift  (run from the repository root)
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824pt rounded square centred in 1024, with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 1).cgColor,
        NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let white = NSColor(white: 0.96, alpha: 1).cgColor
    ctx.setStrokeColor(white)
    ctx.setFillColor(white)
    ctx.setLineCap(.round)

    // Headband.
    ctx.setLineWidth(46)
    ctx.addArc(center: CGPoint(x: 512, y: 470), radius: 290, startAngle: .pi * 0.06, endAngle: .pi * 0.94, clockwise: false)
    ctx.strokePath()
    // Ear cups.
    for x in [190.0, 742.0] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 330, width: 92, height: 210), cornerWidth: 46, cornerHeight: 46, transform: nil))
        ctx.fillPath()
    }

    // Microphone: capsule, cradle, stem, base.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 452, y: 400, width: 120, height: 220), cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.fillPath()
    ctx.setLineWidth(30)
    ctx.addArc(center: CGPoint(x: 512, y: 480), radius: 100, startAngle: .pi, endAngle: 0, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 512, y: 380))
    ctx.addLine(to: CGPoint(x: 512, y: 300))
    ctx.move(to: CGPoint(x: 452, y: 300))
    ctx.addLine(to: CGPoint(x: 572, y: 300))
    ctx.strokePath()

    // Mute slash: dark gap first so it reads at small sizes, then red.
    let slashStart = CGPoint(x: 405, y: 640), slashEnd = CGPoint(x: 630, y: 275)
    ctx.setStrokeColor(NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1).cgColor)
    ctx.setLineWidth(70)
    ctx.move(to: slashStart); ctx.addLine(to: slashEnd); ctx.strokePath()
    ctx.setStrokeColor(NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1).cgColor)
    ctx.setLineWidth(38)
    ctx.move(to: slashStart); ctx.addLine(to: slashEnd); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
try? fm.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
exit(p.terminationStatus)
