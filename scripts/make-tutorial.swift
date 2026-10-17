// Draws the "how to use the Shortcut" tutorial: PNG slides and an animated GIF.
// Black-and-white line art on white, in the style of headphone setup guides
// (no brand logos). Usage (from the repository root):
//   swift scripts/make-tutorial.swift slides   -> docs/images/tutorial/slide-N.png (1080x1080)
//   swift scripts/make-tutorial.swift gif      -> docs/images/tutorial/bose-shortcut.gif (540x540)
//   swift scripts/make-tutorial.swift video    -> docs/images/tutorial/bose-shortcut.mp4 (1080x1080, 30 fps, needs ffmpeg)
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
    var speaking = true          // voice waves from the mouth
    var time: CGFloat = 0        // drives the voice/level animation
    var slash: CGFloat = 0       // 0 = mic icon intact, 1 = fully crossed out
    enum Cue { case down, up }
    /// What the microphone picks up: follows the voice unless muted.
    var level: CGFloat { speaking ? (1 - slash) * (0.35 + 0.65 * abs(sin(time * 1.7) * sin(time * 0.6 + 1))) : 0 }
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

/// Hand drawn by Gemini "Nano Banana 2" (gemini-3.1-flash-image) as line art on white,
/// saved in docs/images/tutorial/assets/hand-source.png. The white around it is made transparent
/// here: flood fill from the borders, with the open forearm end closed first so the inside stays white.
let handImage: CGImage = {
    let src = NSImage(contentsOfFile: "docs/images/tutorial/assets/hand-source.png")!
        .cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = src.width, h = src.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    var wall = [Bool](repeating: false, count: w * h)
    for i in 0..<(w * h) where min(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) < 215 { wall[i] = true }
    // close the forearm: the two outline ends (found by scanning the source image)
    let a = CGPoint(x: 933, y: 619), b = CGPoint(x: 831, y: 820)
    for step in 0...400 {
        let t = CGFloat(step) / 400
        let x = Int(a.x + (b.x - a.x) * t), y = Int(a.y + (b.y - a.y) * t)
        for dy in -5...5 { for dx in -5...5 where (0..<w).contains(x + dx) && (0..<h).contains(y + dy) { wall[(y + dy) * w + x + dx] = true } }
    }
    var outside = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    while let i = stack.popLast() {
        guard !outside[i], !wall[i] else { continue }
        outside[i] = true
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
    }
    for i in 0..<(w * h) where outside[i] { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0 }
    return CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}()
let handTip = CGPoint(x: 129, y: 372)   // index fingertip in the source image
let handScale: CGFloat = 0.5

func drawHand(_ ctx: CGContext, tip: CGPoint) {
    let size = CGSize(width: CGFloat(handImage.width) * handScale, height: CGFloat(handImage.height) * handScale)
    let origin = CGPoint(x: tip.x - handTip.x * handScale, y: tip.y - handTip.y * handScale)
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y + size.height)   // the context is flipped: draw images upright
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(handImage, in: CGRect(origin: .zero, size: size))
    ctx.restoreGState()
}

/// Voice coming out of the mouth: arcs that travel outwards and fade.
func drawVoice(_ ctx: CGContext, time: CGFloat) {
    let mouth = CGPoint(x: 330, y: 520)
    for i in 0..<3 {
        let phase = (time * 0.9 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
        let r = 28 + phase * 110
        let arc = CGMutablePath()
        arc.addArc(center: mouth, radius: r, startAngle: .pi * 0.78, endAngle: .pi * 1.18, clockwise: false)
        stroke(ctx, arc, ink.withAlphaComponent(0.85 * (1 - phase)), 3.2)
    }
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

func micGlyph(_ ctx: CGContext, origin: CGPoint, h: CGFloat, slash: CGFloat) {
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
    if slash > 0 {
        let end = CGPoint(x: 1 + 18 * slash, y: 0 + 22 * slash)
        ctx.setStrokeColor(NSColor(white: 0.95, alpha: 1).cgColor); ctx.setLineWidth(4.6)
        ctx.move(to: CGPoint(x: 1, y: 0)); ctx.addLine(to: end); ctx.strokePath()
        ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(2.3)
        ctx.move(to: CGPoint(x: 1, y: 0)); ctx.addLine(to: end); ctx.strokePath()
    }
    ctx.restoreGState()
}

/// A macOS menu bar strip below the art, showing the app's status item up close.
func drawMenuBar(_ ctx: CGContext, scene: Scene) {
    let bar = CGRect(x: 100, y: 652, width: 880, height: 66)
    stroke(ctx, CGPath(roundedRect: bar, cornerWidth: 14, cornerHeight: 14, transform: nil), NSColor(white: 0.82, alpha: 1), 2,
           fill: NSColor(white: 0.95, alpha: 1))
    text("Menu bar", at: CGPoint(x: 126, y: 670), size: 24, weight: .regular, color: NSColor(white: 0.55, alpha: 1), width: 200)
    text("2:32 PM", at: CGPoint(x: 846, y: 669), size: 26, weight: .medium, color: ink, width: 120)
    stroke(ctx, CGPath(roundedRect: CGRect(x: 772, y: 674, width: 46, height: 22), cornerWidth: 6, cornerHeight: 6, transform: nil), ink, 2.2)
    ctx.setFillColor(ink.cgColor); ctx.fill(CGRect(x: 777, y: 679, width: 30, height: 12))

    // the app's status item: level meter (what the mic picks up) + mic icon, crossed out when muted
    let level = scene.level
    for i in 0..<5 {
        let weight: [CGFloat] = [0.55, 0.85, 1.0, 0.75, 0.5]
        let hBar = 4 + 30 * level * weight[i]
        ctx.setFillColor((level > 0.01 ? ink : NSColor(white: 0.7, alpha: 1)).cgColor)
        ctx.fill(CGRect(x: 512 + CGFloat(i) * 11, y: 685 - hBar / 2, width: 6, height: hBar))
    }
    micGlyph(ctx, origin: CGPoint(x: 582, y: 666), h: 38, slash: scene.slash)
    if scene.slash > 0 {
        text("MUTE", at: CGPoint(x: 628, y: 668), size: 28, weight: .heavy, color: ink.withAlphaComponent(scene.slash), width: 90)
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
    ("Microphone on", "Your Mac's microphones pick up your voice. The Shortcut is the volume strip on the back edge of the right ear cup."),
    ("Touch and hold", "Hold the volume strip for about 2 seconds. Don't swipe: swiping changes the volume."),
    ("Muted", "The microphone icon is crossed out and nothing is picked up, even while you talk. A falling tone confirms it."),
    ("Touch and hold again", "A rising tone plays and the microphones hear you again."),
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
    ctx.addRect(CGRect(x: 0, y: 0, width: W, height: 640)); ctx.clip()
    ctx.translateBy(x: 0, y: -40)   // art sits a little higher now that the menu bar is below it
    stroke(ctx, headPath(), faint, 3)
    if scene.speaking { drawVoice(ctx, time: scene.time) }
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
    ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: 560), end: CGPoint(x: 0, y: 681), options: [])
    ctx.restoreGState()

    drawMenuBar(ctx, scene: scene)

    let (title, body) = steps[scene.step - 1]
    text("\(scene.step) / \(steps.count)", at: CGPoint(x: 100, y: 748), size: 26, weight: .semibold, color: NSColor(white: 0.5, alpha: 1), width: 200)
    text(title, at: CGPoint(x: 100, y: 780), size: 64, weight: .bold, color: ink, width: 900)
    text(body, at: CGPoint(x: 100, y: 866), size: 32, weight: .regular, color: ink, width: 880)
    text("Bose app: set the Shortcut to voice control. Keep Siri on; the app closes it.", at: CGPoint(x: 100, y: 1026), size: 24, weight: .regular,
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
    Scene(step: 1, time: 0.9),
    Scene(step: 2, finger: 1, hold: 0.65, time: 1.6),
    Scene(step: 3, muted: true, cue: .down, cuePhase: 1, time: 2.2, slash: 1),
    Scene(step: 4, finger: 1, hold: 0.65, muted: true, time: 3.1, slash: 1),
]

/// Animation timeline. `sub` subdivides every 0.1 s step: 1 for the GIF (10 fps), 3 for the video (30 fps).
func timeline(sub: Int = 1) -> [(Scene, Double)] {
    var f: [(Scene, Double)] = []
    let d = 0.1 / Double(sub)
    var t: CGFloat = 0
    func add(_ s: Scene) { var s = s; s.time = t; f.append((s, d)); t += CGFloat(d) }
    /// `count` steps of 0.1 s, each subdivided; yields the (fractional) step index.
    func steps(_ count: Int, _ body: (CGFloat) -> Void) {
        for k in 0..<(count * sub) { body(CGFloat(k) / CGFloat(sub)) }
    }
    steps(30) { i in add(Scene(step: 1, pulse: 0.5 + 0.5 * sin(i / 30 * .pi * 6))) }
    steps(8) { i in add(Scene(step: 2, finger: min(1, (i + 1) / 8))) }
    steps(21) { i in add(Scene(step: 2, finger: 1, hold: min(1, i / 20))) }
    steps(34) { i in   // slash draws in, falling tone, hand leaves, voice continues but nothing is picked up
        add(Scene(step: 3, finger: max(0, 1 - i / 7), muted: true, cue: .down,
                  cuePhase: min(1, i / 12), slash: min(1, (i + 1) / 7)))
    }
    steps(8) { i in add(Scene(step: 4, finger: min(1, (i + 1) / 8), muted: true, slash: 1)) }
    steps(21) { i in add(Scene(step: 4, finger: 1, hold: min(1, i / 20), muted: true, slash: 1)) }
    steps(30) { i in   // slash goes away, rising tone, the mic picks up the voice again
        add(Scene(step: 4, finger: max(0, 1 - i / 7), muted: false, cue: .up,
                  cuePhase: min(1, i / 12), slash: max(0, 1 - (i + 1) / 7)))
    }
    return f
}

let outDir = "docs/images/tutorial"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let mode = CommandLine.arguments.dropFirst().first ?? "slides"
if mode == "slides" {
    for (i, scene) in slides.enumerated() {
        let path = "\(outDir)/slide-\(i + 1).png"
        writePNG(render(scene, scale: 1), to: path)
        print(path)
    }
} else if mode == "video" {
    // 1080x1080 at 30 fps, H.264 (needs ffmpeg). Frames go to a temp dir, then get encoded.
    let fps = 30
    var frames = timeline(sub: fps / 10)
    if let last = frames.last { frames += Array(repeating: last, count: fps * 3 / 2) }   // hold the end for 1.5 s
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bose-tutorial-\(getpid())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    for (i, (scene, _)) in frames.enumerated() {
        writePNG(render(scene, scale: 1), to: tmp.appendingPathComponent(String(format: "f%05d.png", i)).path)
    }
    let path = "\(outDir)/bose-shortcut.mp4"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", "\(fps)", "-i", tmp.appendingPathComponent("f%05d.png").path,
                   "-c:v", "libx264", "-preset", "slow", "-tune", "animation", "-crf", "24",
                   "-pix_fmt", "yuv420p", "-movflags", "+faststart", path]
    try p.run(); p.waitUntilExit()
    print(p.terminationStatus == 0 ? "\(path) (\(frames.count) frames)" : "ffmpeg failed")
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
