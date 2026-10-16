// Draws the "how to use the Shortcut" tutorial: PNG slides and an animated GIF.
// Flat vector style matching the app icon (graphite background, white shapes, red accent).
// Usage (from the repository root):
//   swift scripts/make-tutorial.swift slides   -> docs/images/tutorial/slide-N.png
//   swift scripts/make-tutorial.swift gif      -> docs/images/tutorial/bose-shortcut.gif
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 960, H: CGFloat = 540
let white = NSColor(white: 0.96, alpha: 1)
let red = NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
let slate = NSColor(red: 0.36, green: 0.39, blue: 0.45, alpha: 1)
let slateDark = NSColor(red: 0.27, green: 0.29, blue: 0.34, alpha: 1)
let dim = NSColor(white: 0.70, alpha: 1)
let skin = NSColor(red: 0.87, green: 0.74, blue: 0.62, alpha: 1)
let skinShade = NSColor(red: 0.74, green: 0.60, blue: 0.49, alpha: 1)

/// Everything that changes between frames.
struct Scene {
    var step = 1                 // 1...4, drives the text
    var stripGlow: CGFloat = 0   // 0...1 highlight on the volume strip
    var finger: CGFloat = 0      // 0 = off screen, 1 = touching the strip
    var hold: CGFloat? = nil     // progress ring 0...1 while holding
    var muted = false            // menu bar state
    var cue: Cue? = nil          // tone cue animation
    var cuePhase: CGFloat = 0    // 0...1
    enum Cue { case down, up }
}

let strip = CGPoint(x: 377, y: 300)   // contact point on the right ear cup's volume strip

func ease(_ t: CGFloat) -> CGFloat { let t = max(0, min(1, t)); return t * t * (3 - 2 * t) }

// MARK: Drawing

func fill(_ path: CGPath, _ color: NSColor, in ctx: CGContext) {
    ctx.addPath(path); ctx.setFillColor(color.cgColor); ctx.fillPath()
}

func drawBackground(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1).cgColor,
        NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    // soft spotlight behind the head
    let spot = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(white: 1, alpha: 0.07).cgColor, NSColor(white: 1, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(spot, startCenter: CGPoint(x: 300, y: 290), startRadius: 0,
                           endCenter: CGPoint(x: 300, y: 290), endRadius: 290, options: [])
}

/// Side profile facing left, so the viewer sees the person's right side (where the strip is).
func headPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 395, y: 560))
    p.addCurve(to: CGPoint(x: 372, y: 430), control1: CGPoint(x: 380, y: 520), control2: CGPoint(x: 368, y: 470))
    p.addCurve(to: CGPoint(x: 412, y: 270), control1: CGPoint(x: 400, y: 390), control2: CGPoint(x: 418, y: 330))
    p.addCurve(to: CGPoint(x: 285, y: 128), control1: CGPoint(x: 410, y: 180), control2: CGPoint(x: 360, y: 128))
    p.addCurve(to: CGPoint(x: 190, y: 225), control1: CGPoint(x: 225, y: 128), control2: CGPoint(x: 192, y: 170))
    p.addCurve(to: CGPoint(x: 182, y: 262), control1: CGPoint(x: 189, y: 240), control2: CGPoint(x: 190, y: 250))
    p.addLine(to: CGPoint(x: 152, y: 312))        // nose bridge -> tip
    p.addCurve(to: CGPoint(x: 178, y: 330), control1: CGPoint(x: 148, y: 322), control2: CGPoint(x: 160, y: 330))
    p.addCurve(to: CGPoint(x: 174, y: 352), control1: CGPoint(x: 176, y: 337), control2: CGPoint(x: 168, y: 345))
    p.addCurve(to: CGPoint(x: 176, y: 374), control1: CGPoint(x: 180, y: 358), control2: CGPoint(x: 168, y: 368))
    p.addCurve(to: CGPoint(x: 205, y: 412), control1: CGPoint(x: 172, y: 392), control2: CGPoint(x: 184, y: 410))
    p.addCurve(to: CGPoint(x: 268, y: 425), control1: CGPoint(x: 228, y: 416), control2: CGPoint(x: 250, y: 420))
    p.addCurve(to: CGPoint(x: 285, y: 560), control1: CGPoint(x: 280, y: 470), control2: CGPoint(x: 282, y: 520))
    p.closeSubpath()
    return p
}

func drawHeadphones(_ ctx: CGContext, glow: CGFloat) {
    // headband: rises from the cup and goes over the crown (the other side is hidden)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(white.cgColor)
    ctx.setLineWidth(30)
    ctx.move(to: CGPoint(x: 326, y: 232))
    ctx.addCurve(to: CGPoint(x: 300, y: 116), control1: CGPoint(x: 336, y: 190), control2: CGPoint(x: 318, y: 140))
    ctx.strokePath()
    ctx.setStrokeColor(slateDark.cgColor)
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: 314, y: 226))
    ctx.addCurve(to: CGPoint(x: 290, y: 128), control1: CGPoint(x: 322, y: 190), control2: CGPoint(x: 306, y: 150))
    ctx.strokePath()
    // yoke
    ctx.setStrokeColor(white.cgColor)
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: 306, y: 230)); ctx.addLine(to: CGPoint(x: 346, y: 230)); ctx.strokePath()
    // ear cup
    let cup = CGPath(roundedRect: CGRect(x: 262, y: 222, width: 122, height: 158), cornerWidth: 56, cornerHeight: 64, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    fill(cup, white, in: ctx)
    ctx.restoreGState()
    // cup detail ring
    ctx.setStrokeColor(NSColor(white: 0.82, alpha: 1).cgColor)
    ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 276, y: 238, width: 94, height: 126), cornerWidth: 44, cornerHeight: 52, transform: nil))
    ctx.strokePath()
    // volume strip on the rear edge (right ear cup)
    if glow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 22 * glow, color: red.withAlphaComponent(0.9 * glow).cgColor)
        fill(CGPath(roundedRect: CGRect(x: 370, y: 254, width: 14, height: 92), cornerWidth: 7, cornerHeight: 7, transform: nil),
             red.withAlphaComponent(0.25 + 0.75 * glow), in: ctx)
        ctx.restoreGState()
    }
    fill(CGPath(roundedRect: CGRect(x: 373, y: 258, width: 8, height: 84), cornerWidth: 4, cornerHeight: 4, transform: nil),
         glow > 0 ? red : NSColor(white: 0.70, alpha: 1), in: ctx)
}

/// Stylised hand coming from the right, index finger pointing left at `tip`.
func drawHand(_ ctx: CGContext, tip: CGPoint) {
    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 12, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    // forearm going down and to the right, out of the frame
    ctx.saveGState()
    ctx.translateBy(x: 140, y: 70)
    ctx.rotate(by: 1.15)
    fill(CGPath(roundedRect: CGRect(x: 0, y: -44, width: 320, height: 88), cornerWidth: 40, cornerHeight: 40, transform: nil), skinShade, in: ctx)
    ctx.restoreGState()
    // palm with curled fingers
    fill(CGPath(roundedRect: CGRect(x: 70, y: -6, width: 130, height: 112), cornerWidth: 44, cornerHeight: 44, transform: nil), skin, in: ctx)
    // index finger
    fill(CGPath(roundedRect: CGRect(x: 0, y: -14, width: 120, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil), skin, in: ctx)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    // curled finger knuckles
    ctx.setStrokeColor(skinShade.cgColor)
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    for y in [34.0, 58.0, 82.0] {
        ctx.move(to: CGPoint(x: 78, y: y)); ctx.addLine(to: CGPoint(x: 128, y: y)); ctx.strokePath()
    }
    // thumb
    fill(CGPath(roundedRect: CGRect(x: 92, y: -30, width: 70, height: 26), cornerWidth: 13, cornerHeight: 13,
                transform: nil), skin, in: ctx)
    ctx.move(to: CGPoint(x: 100, y: -4)); ctx.addLine(to: CGPoint(x: 150, y: -4)); ctx.strokePath()
    // finger nail
    fill(CGPath(roundedRect: CGRect(x: 6, y: -9, width: 20, height: 18), cornerWidth: 8, cornerHeight: 8, transform: nil),
         NSColor(red: 0.95, green: 0.85, blue: 0.78, alpha: 1), in: ctx)
    ctx.restoreGState()
}

func drawHoldRing(_ ctx: CGContext, progress: CGFloat) {
    let c = strip
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
    ctx.setLineWidth(7)
    ctx.addArc(center: c, radius: 52, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    if progress > 0 {
        ctx.setStrokeColor(red.cgColor)
        ctx.addArc(center: c, radius: 52, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * progress, clockwise: false)
        ctx.strokePath()
    }
    let seconds = String(format: "%.1f s", 2 * progress)
    text(seconds, at: CGPoint(x: c.x + 50, y: c.y - 88), size: 18, weight: .semibold, color: progress >= 1 ? red : white, width: 80)
}

func drawCue(_ ctx: CGContext, _ cue: Scene.Cue, phase: CGFloat) {
    // three notes stepping down (mute) or up (unmute), fading in one after another
    for i in 0..<3 {
        let t = max(0, min(1, phase * 3 - CGFloat(i)))
        guard t > 0 else { continue }
        let step = CGFloat(i) * 34
        let y = cue == .down ? 150 + step : 218 - step
        let color = (cue == .down ? red : white).withAlphaComponent(t)
        text("♪", at: CGPoint(x: 420 + CGFloat(i) * 38, y: y - 10 * (1 - t)), size: 40, weight: .bold, color: color, width: 60)
    }
}

/// The app's mic glyph (same shapes as the icon), drawn at `origin` with height `h`.
func micGlyph(_ ctx: CGContext, origin: CGPoint, h: CGFloat, color: NSColor, slashed: Bool) {
    let s = h / 24
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: s, y: s)
    fill(CGPath(roundedRect: CGRect(x: 6, y: 0, width: 8, height: 14), cornerWidth: 4, cornerHeight: 4, transform: nil), color, in: ctx)
    ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(2); ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 10, y: 9), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 10, y: 16)); ctx.addLine(to: CGPoint(x: 10, y: 21))
    ctx.move(to: CGPoint(x: 6, y: 21)); ctx.addLine(to: CGPoint(x: 14, y: 21)); ctx.strokePath()
    if slashed {
        ctx.setLineWidth(2.4)
        ctx.move(to: CGPoint(x: 2, y: 1)); ctx.addLine(to: CGPoint(x: 18, y: 21)); ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawMenuBar(_ ctx: CGContext, muted: Bool) {
    let bar = CGRect(x: 560, y: 432, width: 360, height: 40)
    fill(CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil), NSColor(white: 1, alpha: 0.10), in: ctx)
    text("barra de menus", at: CGPoint(x: 572, y: 410), size: 13, weight: .regular, color: NSColor(white: 0.55, alpha: 1), width: 200)
    // decoy items
    text("14:32", at: CGPoint(x: 862, y: 441), size: 16, weight: .medium, color: dim, width: 60)
    fill(CGPath(roundedRect: CGRect(x: 818, y: 445, width: 28, height: 14), cornerWidth: 3, cornerHeight: 3, transform: nil), dim, in: ctx)
    // the app's status item
    if muted {
        fill(CGPath(roundedRect: CGRect(x: 688, y: 438, width: 108, height: 28), cornerWidth: 8, cornerHeight: 8, transform: nil),
             red.withAlphaComponent(0.16), in: ctx)
        micGlyph(ctx, origin: CGPoint(x: 696, y: 441), h: 22, color: red, slashed: true)
        text("MUTE", at: CGPoint(x: 726, y: 441), size: 16, weight: .bold, color: red, width: 70)
    } else {
        micGlyph(ctx, origin: CGPoint(x: 760, y: 441), h: 22, color: white, slashed: false)
    }
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = size * 0.18
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ]
    NSAttributedString(string: s, attributes: attrs)
        .draw(with: CGRect(x: p.x, y: p.y, width: width, height: 400), options: [.usesLineFragmentOrigin])
}

let steps: [(String, String)] = [
    ("Atalho do QC Ultra 2", "A faixa de volume fica na borda traseira do fone direito. No app Bose, configure o Atalho como “controle de voz”."),
    ("Toque e segure", "Encoste o dedo na faixa de volume e segure por cerca de 2 segundos. Não deslize: deslizar muda o volume."),
    ("Microfones mutados", "Tom descendente no fone e ícone vermelho MUTE na barra de menus. Todos os microfones do Mac ficam mudos."),
    ("Repita para reativar", "Toque e segure de novo: tom ascendente e os microfones voltam ao estado anterior."),
]

func drawText(_ step: Int) {
    let (title, body) = steps[step - 1]
    text("\(step) / \(steps.count)", at: CGPoint(x: 560, y: 92), size: 16, weight: .semibold, color: red, width: 120)
    text(title, at: CGPoint(x: 560, y: 120), size: 36, weight: .bold, color: white, width: 370)
    text(body, at: CGPoint(x: 560, y: 180), size: 20, weight: .regular, color: dim, width: 360)
    text("Mantenha a Siri ligada; o app a fecha sozinho.", at: CGPoint(x: 560, y: 490), size: 14, weight: .regular,
         color: NSColor(white: 0.55, alpha: 1), width: 380)
}

func render(_ scene: Scene, scale: CGFloat) -> CGImage {
    let pw = Int(W * scale), ph = Int(H * scale)
    let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // top-left origin, y down
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    drawBackground(ctx)
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: 545, height: H)); ctx.clip()
    ctx.translateBy(x: -40, y: 0)
    fill(headPath(), slate, in: ctx)
    drawHeadphones(ctx, glow: scene.stripGlow)
    if let cue = scene.cue { drawCue(ctx, cue, phase: scene.cuePhase) }
    if scene.finger > 0 {
        let x = strip.x + 4 + (1 - ease(scene.finger)) * 220
        drawHand(ctx, tip: CGPoint(x: x, y: strip.y))
    }
    if let hold = scene.hold { drawHoldRing(ctx, progress: hold) }
    ctx.restoreGState()

    drawText(scene.step)
    drawMenuBar(ctx, muted: scene.muted)

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// MARK: Output

func writePNG(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// Key frame of each step, as shown in the slides.
let slides: [Scene] = [
    Scene(step: 1, stripGlow: 1),
    Scene(step: 2, stripGlow: 1, finger: 1, hold: 0.65),
    Scene(step: 3, stripGlow: 0, muted: true, cue: .down, cuePhase: 1),
    Scene(step: 4, stripGlow: 1, finger: 1, hold: 0.65, muted: true),
]

/// Animation timeline (10 fps).
func timeline() -> [(Scene, Double)] {
    var frames: [(Scene, Double)] = []
    let d = 0.1
    for i in 0..<16 { frames.append((Scene(step: 1, stripGlow: 0.5 + 0.5 * sin(CGFloat(i) / 16 * .pi * 4)), d)) }
    for i in 0..<8 { frames.append((Scene(step: 2, stripGlow: 1, finger: CGFloat(i + 1) / 8), d)) }
    for i in 0...20 { frames.append((Scene(step: 2, stripGlow: 1, finger: 1, hold: CGFloat(i) / 20), d)) }
    for i in 0..<22 {
        let leave = max(0, 1 - CGFloat(i) / 7)
        frames.append((Scene(step: 3, stripGlow: 0, finger: leave, muted: true, cue: .down, cuePhase: min(1, CGFloat(i) / 12)), d))
    }
    frames.append((Scene(step: 3, muted: true, cue: .down, cuePhase: 1), 1.2))
    for i in 0..<8 { frames.append((Scene(step: 4, stripGlow: 1, finger: CGFloat(i + 1) / 8, muted: true), d)) }
    for i in 0...20 { frames.append((Scene(step: 4, stripGlow: 1, finger: 1, hold: CGFloat(i) / 20, muted: true), d)) }
    for i in 0..<22 {
        let leave = max(0, 1 - CGFloat(i) / 7)
        frames.append((Scene(step: 4, stripGlow: 0, finger: leave, muted: false, cue: .up, cuePhase: min(1, CGFloat(i) / 12)), d))
    }
    frames.append((Scene(step: 4, muted: false, cue: .up, cuePhase: 1), 1.5))
    return frames
}

let outDir = "docs/images/tutorial"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let mode = CommandLine.arguments.dropFirst().first ?? "slides"

if mode == "slides" {
    for (i, scene) in slides.enumerated() {
        let path = "\(outDir)/slide-\(i + 1).png"
        writePNG(render(scene, scale: 2), to: path)
        print(path)
    }
} else {
    let frames = timeline()
    let path = "\(outDir)/bose-shortcut.gif"
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (scene, delay) in frames {
        CGImageDestinationAddImage(dest, render(scene, scale: 0.75),
                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("\(path) (\(frames.count) frames)")
}
