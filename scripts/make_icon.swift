// Renders every brand image from Sources/UI/Logo.swift: the AppIcon.iconset PNGs, the README logo,
// a menu bar preview, and the DMG window's backdrop and drop slot.
// Usage: scripts/make_icon.sh
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ w: Int, _ h: Int, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func png(_ w: Int, _ h: Int, to name: String, draw: (CGContext) -> Void) {
    try! NSBitmapImageRep(cgImage: render(w, h, draw: draw)).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name))
}

for pt in [16, 32, 128, 256, 512] {
    for s in [1, 2] {
        let px = pt * s
        png(px, px, to: "icon_\(pt)x\(pt)\(s == 2 ? "@2x" : "").png") { Logo.drawIcon($0, size: CGFloat(px)) }
    }
}

// README logo, as it looks in a light and a dark menu bar.
func glyph(_ h: CGFloat, to name: String, color: CGColor, scale: CGFloat = 4) {
    // Half a point of margin each side so antialiased ring edges aren't clipped.
    png(Int((Logo.logoWidth(height: h) + 1) * scale), Int(h * scale), to: name) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0.5, y: 0)
        Logo.drawLogo(ctx, height: h, color: color)
    }
}
glyph(60, to: "logo.png", color: Logo.ink)
glyph(60, to: "logo-dark.png", color: .white)
glyph(16, to: "menubar_preview.png", color: .black)

// MARK: DMG window

// Finder coordinates (points, y down) in a 600×330 window. Must match scripts/release.sh: window size,
// icon size, TAUdo.app and Applications positions.
let iconSize: CGFloat = 112
let appAt = CGPoint(x: 135, y: 150), slotAt = CGPoint(x: 335, y: 150)
/// Finder draws the backdrop at its natural size, pinned top-left: the canvas runs past the window.
let canvas = CGSize(width: 1200, height: 800)
let paper = CGColor(gray: 0.96, alpha: 1)

/// The backdrop: the logo's rings with the check circle missing, and an arrow from the app to that slot.
func backdrop(_ ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(paper); ctx.fill(CGRect(origin: .zero, size: canvas))
    func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: canvas.height - p.y) }   // Finder → y-up

    let d = Logo.iconCircle * iconSize, slot = up(slotAt)
    Logo.drawRings(ctx, beside: CGRect(x: slot.x - d / 2, y: slot.y - d / 2, width: d, height: d), color: Logo.ink)

    // Finder prints icon names in black (Light Mode) or white (Dark Mode) and a backdrop can't follow
    // the appearance: a mid-grey capsule under each name keeps both readable.
    ctx.setFillColor(CGColor(gray: 0.52, alpha: 1))
    for c in [appAt, slotAt] {
        let r = CGRect(x: c.x - 62, y: canvas.height - (c.y + iconSize / 2 + 30), width: 124, height: 22)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil)); ctx.fillPath()
    }

    // Dotted arrow from the app to the slot.
    let y = up(appAt).y, x0 = appAt.x + iconSize / 2 + 14, x1 = slotAt.x - d / 2 - 16
    ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1)); ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 10])
    ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1 - 8, y: y)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.move(to: CGPoint(x: x1 - 12, y: y + 11)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.addLine(to: CGPoint(x: x1 - 12, y: y - 11))
    ctx.strokePath()
}

let tiff = NSImage(size: canvas)
for s: CGFloat in [1, 2] {
    let rep = NSBitmapImageRep(cgImage: render(Int(canvas.width * s), Int(canvas.height * s)) { backdrop($0, scale: s) })
    rep.size = canvas
    tiff.addRepresentation(rep)
}
try! tiff.tiffRepresentation(using: .lzw, factor: 1)!.write(to: out.appendingPathComponent("dmg-background.tiff"))

// The Applications alias's icon: an empty, dashed check circle — the slot the app is dragged into.
png(1024, 1024, to: "dmg-slot.png") { ctx in
    let d = Logo.iconCircle * 1024, r = CGRect(x: (1024 - d) / 2, y: (1024 - d) / 2, width: d, height: d)
    // A faint fill so the whole circle, not just its outline, takes the drop.
    ctx.setFillColor(Logo.ink.copy(alpha: 0.05)!); ctx.fillEllipse(in: r)
    ctx.setStrokeColor(Logo.ink.copy(alpha: 0.55)!); ctx.setLineWidth(24); ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [48, 40])
    ctx.strokeEllipse(in: r.insetBy(dx: 12, dy: 12))
}
