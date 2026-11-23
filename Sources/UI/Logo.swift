import AppKit

/// TAUdo marks, redrawn after Tel Aviv University's logo with a to-do twist:
/// - App icon: the logo's solid circle with the torch emblem, whose bowl is a check mark.
/// - Menu bar: the logo's three circles read as a checklist — done (✓), in progress (heavy ring), to do (thin rings).
/// For personal use; the TAU logo is the university's trademark.
enum Logo {
    static let navy = CGColor(srgbRed: 0.05, green: 0.17, blue: 0.36, alpha: 1)
    static let navyLight = CGColor(srgbRed: 0.11, green: 0.27, blue: 0.50, alpha: 1)

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// Teardrop flame pointing up, symmetric about x = cx.
    private static func drop(_ path: CGMutablePath, cx: CGFloat, top: CGFloat, bottom: CGFloat, halfWidth w: CGFloat) {
        let h = bottom - top, wide = top + 0.68 * h
        path.move(to: p(cx, top))
        path.addCurve(to: p(cx + w, wide), control1: p(cx + 0.3 * w, top + 0.22 * h), control2: p(cx + w, top + 0.42 * h))
        path.addCurve(to: p(cx, bottom), control1: p(cx + w, wide + 0.2 * h), control2: p(cx + 0.45 * w, bottom))
        path.addCurve(to: p(cx - w, wide), control1: p(cx - 0.45 * w, bottom), control2: p(cx - w, wide + 0.2 * h))
        path.addCurve(to: p(cx, top), control1: p(cx - w, top + 0.42 * h), control2: p(cx - 0.3 * w, top + 0.22 * h))
        path.closeSubpath()
    }

    static let stemX: CGFloat = 0.40

    /// Flame and check-bowl in a unit box (y down). Fill with the even-odd rule.
    static func emblem() -> CGPath {
        let path = CGMutablePath()
        let cx = stemX
        // Torch flame: solid, with a dark inner flame holding a thin light sliver.
        drop(path, cx: cx, top: 0.00, bottom: 0.50, halfWidth: 0.11)
        drop(path, cx: cx, top: 0.18, bottom: 0.42, halfWidth: 0.045)
        drop(path, cx: cx, top: 0.28, bottom: 0.40, halfWidth: 0.014)
        // Bowl drawn as a check mark: straight outer edges, flat tops, a crescent inside around the flame.
        path.move(to: p(0.00, 0.40))
        path.addLine(to: p(cx - 0.03, 0.97))
        path.addLine(to: p(cx + 0.03, 0.97))
        path.addLine(to: p(1.00, 0.06))
        path.addLine(to: p(0.80, 0.11))
        path.addCurve(to: p(cx, 0.72), control1: p(0.62, 0.40), control2: p(0.52, 0.72))
        path.addCurve(to: p(0.19, 0.45), control1: p(0.28, 0.72), control2: p(0.22, 0.60))
        path.closeSubpath()
        return path
    }

    /// Stem from the flame through the bowl, with ת and א either side, as in the emblem.
    private static func stemAndLetters(_ ctx: CGContext) {
        ctx.fill(CGRect(x: stemX - 0.014, y: 0.48, width: 0.028, height: 0.26))   // thin stem under the flame
        ctx.fill(CGRect(x: stemX - 0.035, y: 0.95, width: 0.07, height: 0.33))    // stem between the letters
        let font = CTFontCreateWithName("ArialHebrew-Bold" as CFString, 0.36, nil)
        func glyph(_ s: String, right: CGFloat? = nil, left: CGFloat? = nil) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
                .init(kCTFontAttributeName as String): font, .init(kCTForegroundColorFromContextAttributeName as String): true]))
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // y-down context
            ctx.textPosition = p(right.map { $0 - w } ?? left ?? 0, 1.28)
            CTLineDraw(line, ctx)
        }
        glyph("ת", right: stemX - 0.045)
        glyph("א", left: stemX + 0.045)
    }

    /// App icon into a unit square scaled to `size` (CoreGraphics context, y up).
    static func drawIcon(_ ctx: CGContext, size: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: size, y: -size)
        // macOS icon grid: 824/1024 tile.
        let m: CGFloat = 100 / 1024
        let tile = CGPath(roundedRect: CGRect(x: m, y: m, width: 1 - 2 * m, height: 1 - 2 * m), cornerWidth: 0.185, cornerHeight: 0.185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0.012), blur: 0.03, color: CGColor(gray: 0, alpha: 0.3))
        ctx.addPath(tile); ctx.setFillColor(.white); ctx.fillPath()
        ctx.restoreGState()
        // The logo's solid circle.
        let circle = CGRect(x: 0.17, y: 0.17, width: 0.66, height: 0.66)
        ctx.saveGState()
        ctx.addEllipse(in: circle); ctx.clip()
        ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [navyLight, navy] as CFArray, locations: [0, 1])!,
                               start: p(0.5, circle.minY), end: p(0.5, circle.maxY), options: [])
        ctx.restoreGState()
        // White emblem centred in the circle (the stem sits on the centre line).
        let w: CGFloat = 0.37
        ctx.translateBy(x: 0.5 - stemX * w, y: 0.255); ctx.scaleBy(x: w, y: w)
        ctx.setFillColor(.white)
        ctx.addPath(emblem()); ctx.fillPath(using: .evenOdd)
        stemAndLetters(ctx)
        ctx.restoreGState()
    }

    /// Menu bar glyph in points (y down): ● with a knocked-out ✓, a heavy ring, interlocking thin rings.
    static func drawMenuBar(_ ctx: CGContext, height h: CGFloat) {
        let d = h - 2, y: CGFloat = 1, gap: CGFloat = 2
        ctx.setFillColor(.black); ctx.setStrokeColor(.black)
        // 1. Done: solid circle, check knocked out.
        ctx.fillEllipse(in: CGRect(x: 0, y: y, width: d, height: d))
        ctx.saveGState()
        ctx.setBlendMode(.clear); ctx.setLineWidth(d * 0.14); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: p(d * 0.27, y + d * 0.52)); ctx.addLine(to: p(d * 0.44, y + d * 0.69)); ctx.addLine(to: p(d * 0.74, y + d * 0.32))
        ctx.strokePath()
        ctx.restoreGState()
        // 2. In progress: heavy ring.
        let lw = d * 0.24
        ctx.setLineWidth(lw)
        ctx.strokeEllipse(in: CGRect(x: d + gap + lw / 2, y: y + lw / 2, width: d - lw, height: d - lw))
        // 3. To do: two interlocking thin rings.
        let t = d * 0.09, x3 = 2 * (d + gap)
        ctx.setLineWidth(t)
        ctx.strokeEllipse(in: CGRect(x: x3 + t / 2, y: y + d * 0.14, width: d * 0.72, height: d * 0.72))
        ctx.strokeEllipse(in: CGRect(x: x3 + d * 0.28 - t / 2, y: y + d * 0.14, width: d * 0.72, height: d * 0.72))
    }

    static func menuBarWidth(height h: CGFloat) -> CGFloat { 3 * (h - 2) + 4 }

    /// Menu bar template image (follows light/dark menu bar automatically).
    static let menuBarImage: NSImage = {
        let h: CGFloat = 16
        let img = NSImage(size: NSSize(width: menuBarWidth(height: h), height: h), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMenuBar(ctx, height: h)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
