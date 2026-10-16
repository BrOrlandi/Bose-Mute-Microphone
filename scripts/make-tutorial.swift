// Draws the "how to use the Shortcut" tutorial: PNG slides and an animated GIF.
// Black-and-white line art on white, in the style of headphone setup guides
// (no brand logos). Usage (from the repository root):
//   swift scripts/make-tutorial.swift slides   -> docs/images/tutorial/slide-N.png (1080x1080)
//   swift scripts/make-tutorial.swift gif      -> docs/images/tutorial/bose-shortcut.gif (540x540)
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 1080, H: CGFloat = 1080
let ink = NSColor(white: 0.08, alpha: 1)        // text, strip, emphasis
let line = NSColor(white: 0.42, alpha: 1)       // headphone outlines
let faint = NSColor(white: 0.72, alpha: 1)      // head outline
let touch = NSColor(white: 0.74, alpha: 1)      // touch point fill
let paper = NSColor.white

struct Scene {
    var step = 1
    var finger: CGFloat = 0      // 0 = away, 1 = touching
    var hold: CGFloat? = nil     // 0...1 progress while holding
    var muted = false
    var cue: Cue? = nil
    var cuePhase: CGFloat = 0
    var pulse: CGFloat = 0       // touch point pulse 0...1
    enum Cue { case down, up }
}

let touchPoint = CGPoint(x: 662, y: 420)

func ease(_ t: CGFloat) -> CGFloat { let t = max(0, min(1, t)); return t * t * (3 - 2 * t) }

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: NSColor, _ width: CGFloat, fill: NSColor? = nil, dash: [CGFloat]? = nil) {
    if let fill { ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath() }
    ctx.addPath(path)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: dash ?? [])
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
}

func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rotation)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
}

/// Side profile facing left (viewer sees the person's right side).
func headPath() -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 320) * 1.45 + 560, y: (y - 300) * 1.45 + 430) }
    p.move(to: pt(395, 560))
    p.addCurve(to: pt(372, 430), control1: pt(380, 520), control2: pt(368, 470))
    p.addCurve(to: pt(412, 270), control1: pt(400, 390), control2: pt(418, 330))
    p.addCurve(to: pt(285, 128), control1: pt(410, 180), control2: pt(360, 128))
    p.addCurve(to: pt(190, 225), control1: pt(225, 128), control2: pt(192, 170))
    p.addCurve(to: pt(182, 262), control1: pt(189, 240), control2: pt(190, 250))
    p.addLine(to: pt(152, 312))
    p.addCurve(to: pt(178, 330), control1: pt(148, 322), control2: pt(160, 330))
    p.addCurve(to: pt(174, 352), control1: pt(176, 337), control2: pt(168, 345))
    p.addCurve(to: pt(176, 374), control1: pt(180, 358), control2: pt(168, 368))
    p.addCurve(to: pt(205, 412), control1: pt(172, 392), control2: pt(184, 410))
    p.addCurve(to: pt(268, 425), control1: pt(228, 416), control2: pt(250, 420))
    p.addCurve(to: pt(285, 560), control1: pt(280, 470), control2: pt(282, 520))
    return p
}

func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                   y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
}

func drawHeadphones(_ ctx: CGContext) {
    // headband: two parallel lines rising from the cup, fading out over the head
    // follows the skull over the crown
    let bands: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 600, y: 300), CGPoint(x: 616, y: 222), CGPoint(x: 590, y: 158), CGPoint(x: 492, y: 150)),
        (CGPoint(x: 626, y: 300), CGPoint(x: 646, y: 214), CGPoint(x: 608, y: 128), CGPoint(x: 492, y: 120)),
    ]
    for (p0, p1, p2, p3) in bands {
        let segments = 18
        for i in 0..<segments {
            let t0 = CGFloat(i) / CGFloat(segments), t1 = CGFloat(i + 1) / CGFloat(segments)
            let path = CGMutablePath()
            path.move(to: bezier(p0, p1, p2, p3, t0)); path.addLine(to: bezier(p0, p1, p2, p3, t1))
            stroke(ctx, path, line.withAlphaComponent(1 - max(0, t0 - 0.45) / 0.55), 3)
        }
    }
    // yoke joining band and cup
    let yoke = CGMutablePath()
    yoke.move(to: CGPoint(x: 598, y: 300))
    yoke.addCurve(to: CGPoint(x: 640, y: 318), control1: CGPoint(x: 600, y: 330), control2: CGPoint(x: 636, y: 340))
    yoke.addLine(to: CGPoint(x: 628, y: 296))
    stroke(ctx, yoke, line, 3, fill: paper)

    // ear cup in a slight 3/4 view: rear shell + outer plate; the band between them is the back edge
    stroke(ctx, ellipse(CGPoint(x: 598, y: 432), 104, 150, rotation: 0.10), line, 3.2, fill: paper)
    stroke(ctx, ellipse(CGPoint(x: 560, y: 436), 92, 138, rotation: 0.10), line, 3.2, fill: paper)
    stroke(ctx, ellipse(CGPoint(x: 556, y: 438), 70, 112, rotation: 0.10), line.withAlphaComponent(0.55), 2)

    // back edge details: mic grille dots, button, Bluetooth button
    ctx.setFillColor(line.cgColor)
    for i in 0..<5 { for j in 0..<2 {
        ctx.fillEllipse(in: CGRect(x: 664 + CGFloat(j) * 8 + CGFloat(i) * 1.6, y: 316 + CGFloat(i) * 8, width: 4.5, height: 4.5))
    } }
    stroke(ctx, CGPath(roundedRect: CGRect(x: 676, y: 474, width: 15, height: 40), cornerWidth: 7.5, cornerHeight: 7.5, transform: nil), line, 2.6)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 670, y: 534, width: 17, height: 21), cornerWidth: 7, cornerHeight: 7, transform: nil), line, 2.6)

    // volume strip: a curved slot along the back edge
    let strip = CGMutablePath()
    strip.move(to: CGPoint(x: 650, y: 352))
    strip.addCurve(to: CGPoint(x: 654, y: 492), control1: CGPoint(x: 668, y: 390), control2: CGPoint(x: 666, y: 450))
    stroke(ctx, strip, ink, 12)
    stroke(ctx, strip, paper, 6)
}

/// Line-art hand coming from the right, index finger at `tip`.
func drawHand(_ ctx: CGContext, tip: CGPoint) {
    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.saveGState()
    ctx.translateBy(x: 160, y: 80)
    ctx.rotate(by: 0.95)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 0, y: -50, width: 460, height: 100), cornerWidth: 46, cornerHeight: 46, transform: nil), line, 3, fill: paper)
    ctx.restoreGState()
    stroke(ctx, CGPath(roundedRect: CGRect(x: 78, y: -4, width: 148, height: 126), cornerWidth: 50, cornerHeight: 50, transform: nil), line, 3, fill: paper)
    for y in [38.0, 66.0, 94.0] {
        let k = CGMutablePath(); k.move(to: CGPoint(x: 92, y: y)); k.addLine(to: CGPoint(x: 150, y: y))
        stroke(ctx, k, line.withAlphaComponent(0.7), 2.4)
    }
    stroke(ctx, CGPath(roundedRect: CGRect(x: 104, y: -32, width: 84, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil), line, 3, fill: paper)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 0, y: -17, width: 140, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil), line, 3, fill: paper)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 8, y: -10, width: 22, height: 20), cornerWidth: 8, cornerHeight: 8, transform: nil), line.withAlphaComponent(0.6), 2)
    ctx.restoreGState()
}

func drawTouchPoint(_ ctx: CGContext, scene: Scene) {
    let c = touchPoint
    let r: CGFloat = 36 + 6 * scene.pulse
    ctx.setFillColor(touch.withAlphaComponent(0.85).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44))
    stroke(ctx, ellipse(c, r, r), ink, 3, dash: [2, 8])
    if let hold = scene.hold, hold > 0 {
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: r, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * hold, clockwise: false)
        stroke(ctx, arc, ink, 6)
        text(String(format: "%.1f s", 2 * hold), at: CGPoint(x: c.x + 50, y: c.y - 100), size: 30, weight: .semibold, color: ink, width: 120)
    }
}

func drawCue(_ ctx: CGContext, _ cue: Scene.Cue, phase: CGFloat) {
    for i in 0..<3 {
        let t = max(0, min(1, phase * 3 - CGFloat(i)))
        guard t > 0 else { continue }
        let step = CGFloat(i) * 46
        let y = cue == .down ? 170 + step : 262 - step
        text("♪", at: CGPoint(x: 760 + CGFloat(i) * 52, y: y - 12 * (1 - t)), size: 54, weight: .regular, color: ink.withAlphaComponent(t), width: 80)
    }
}

func micGlyph(_ ctx: CGContext, origin: CGPoint, h: CGFloat, slashed: Bool) {
    let s = h / 24
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: s, y: s)
    ctx.setFillColor(ink.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 6, y: 0, width: 8, height: 14), cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(2); ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 10, y: 9), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 10, y: 16)); ctx.addLine(to: CGPoint(x: 10, y: 21))
    ctx.move(to: CGPoint(x: 6, y: 21)); ctx.addLine(to: CGPoint(x: 14, y: 21)); ctx.strokePath()
    if slashed {
        ctx.setStrokeColor(paper.cgColor); ctx.setLineWidth(4.4)
        ctx.move(to: CGPoint(x: 2, y: 1)); ctx.addLine(to: CGPoint(x: 18, y: 21)); ctx.strokePath()
        ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(2.2)
        ctx.move(to: CGPoint(x: 2, y: 1)); ctx.addLine(to: CGPoint(x: 18, y: 21)); ctx.strokePath()
    }
    ctx.restoreGState()
}

/// macOS-style menu bar across the top, showing the app's status item.
func drawMenuBar(_ ctx: CGContext, muted: Bool) {
    ctx.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: 52))
    ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 52, width: W, height: 1.5))
    text("2:32 PM", at: CGPoint(x: 950, y: 12), size: 22, weight: .medium, color: ink, width: 120)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 884, y: 17, width: 40, height: 19), cornerWidth: 5, cornerHeight: 5, transform: nil), ink, 2)
    ctx.setFillColor(ink.cgColor); ctx.fill(CGRect(x: 888, y: 21, width: 26, height: 11))
    if muted {
        stroke(ctx, CGPath(roundedRect: CGRect(x: 736, y: 9, width: 128, height: 35), cornerWidth: 9, cornerHeight: 9, transform: nil),
               ink, 2, fill: paper)
        micGlyph(ctx, origin: CGPoint(x: 746, y: 13), h: 27, slashed: true)
        text("MUTE", at: CGPoint(x: 782, y: 12), size: 22, weight: .heavy, color: ink, width: 80)
    } else {
        micGlyph(ctx, origin: CGPoint(x: 832, y: 13), h: 27, slashed: false)
    }
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = size * 0.28
    NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ]).draw(with: CGRect(x: p.x, y: p.y, width: width, height: 600), options: [.usesLineFragmentOrigin])
}

let steps: [(String, String)] = [
    ("Shortcut", "The volume strip is on the back edge of the right ear cup. In the Bose app, set the Shortcut to voice control."),
    ("Touch and hold", "Touch the volume strip and hold for about 2 seconds. Don't swipe: swiping changes the volume."),
    ("Microphones muted", "A falling tone plays and the menu bar shows MUTE. Every microphone on the Mac is muted."),
    ("Repeat to unmute", "Touch and hold again: a rising tone plays and the microphones go back to how they were."),
]

func render(_ scene: Scene, scale: CGFloat) -> CGImage {
    let pw = Int(W * scale), ph = Int(H * scale)
    let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    ctx.setFillColor(paper.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // illustration panel; fades out at the bottom so the neck does not run into the text
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 53, width: W, height: 680)); ctx.clip()
    stroke(ctx, headPath(), faint, 3)
    drawHeadphones(ctx)
    if let cue = scene.cue { drawCue(ctx, cue, phase: scene.cuePhase) }
    drawTouchPoint(ctx, scene: scene)
    if scene.finger > 0 {
        let x = touchPoint.x + 16 + (1 - ease(scene.finger)) * 320
        drawHand(ctx, tip: CGPoint(x: x, y: touchPoint.y))
    }
    let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: 610), end: CGPoint(x: 0, y: 733), options: [])
    ctx.restoreGState()

    drawMenuBar(ctx, muted: scene.muted)

    let (title, body) = steps[scene.step - 1]
    text("\(scene.step) / \(steps.count)", at: CGPoint(x: 100, y: 742), size: 26, weight: .semibold, color: NSColor(white: 0.5, alpha: 1), width: 200)
    text(title, at: CGPoint(x: 100, y: 778), size: 68, weight: .bold, color: ink, width: 900)
    text(body, at: CGPoint(x: 100, y: 872), size: 34, weight: .regular, color: ink, width: 880)
    text("Keep Siri on. The app closes it for you.", at: CGPoint(x: 100, y: 1020), size: 24, weight: .regular,
         color: NSColor(white: 0.5, alpha: 1), width: 880)

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let slides: [Scene] = [
    Scene(step: 1),
    Scene(step: 2, finger: 1, hold: 0.65),
    Scene(step: 3, muted: true, cue: .down, cuePhase: 1),
    Scene(step: 4, finger: 1, hold: 0.65, muted: true),
]

func timeline() -> [(Scene, Double)] {
    var f: [(Scene, Double)] = []
    let d = 0.1
    for i in 0..<16 { f.append((Scene(step: 1, pulse: 0.5 + 0.5 * sin(CGFloat(i) / 16 * .pi * 4)), d)) }
    for i in 0..<8 { f.append((Scene(step: 2, finger: CGFloat(i + 1) / 8), d)) }
    for i in 0...20 { f.append((Scene(step: 2, finger: 1, hold: CGFloat(i) / 20), d)) }
    for i in 0..<22 {
        f.append((Scene(step: 3, finger: max(0, 1 - CGFloat(i) / 7), muted: true, cue: .down, cuePhase: min(1, CGFloat(i) / 12)), d))
    }
    f.append((Scene(step: 3, muted: true, cue: .down, cuePhase: 1), 1.2))
    for i in 0..<8 { f.append((Scene(step: 4, finger: CGFloat(i + 1) / 8, muted: true), d)) }
    for i in 0...20 { f.append((Scene(step: 4, finger: 1, hold: CGFloat(i) / 20, muted: true), d)) }
    for i in 0..<22 {
        f.append((Scene(step: 4, finger: max(0, 1 - CGFloat(i) / 7), muted: false, cue: .up, cuePhase: min(1, CGFloat(i) / 12)), d))
    }
    f.append((Scene(step: 4, muted: false, cue: .up, cuePhase: 1), 1.5))
    return f
}

let outDir = "docs/images/tutorial"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
if (CommandLine.arguments.dropFirst().first ?? "slides") == "slides" {
    for (i, scene) in slides.enumerated() {
        let path = "\(outDir)/slide-\(i + 1).png"
        writePNG(render(scene, scale: 1), to: path)
        print(path)
    }
} else {
    let frames = timeline()
    let path = "\(outDir)/bose-shortcut.gif"
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (scene, delay) in frames {
        CGImageDestinationAddImage(dest, render(scene, scale: 0.5),
                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("\(path) (\(frames.count) frames)")
}
