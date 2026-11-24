import AppKit

/// TAUdo marks, after Tel Aviv University's logo with a to-do twist:
/// - Badge (app icon): the logo's solid circle with the torch emblem, whose bowl is a check mark.
/// - Lockup (README): the badge followed by the logo's heavy ring and interlocking rings, taken from TAU's logo artwork.
/// - Menu bar: the same three circles as a checklist — done (✓), in progress, to do.
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

    /// The badge: a navy circle with the white emblem, filling `rect` (y-up context).
    static func drawBadge(_ ctx: CGContext, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: rect.width, y: -rect.height)   // unit square, y down
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: 1, height: 1)); ctx.clip()
        ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [navyLight, navy] as CFArray, locations: [0, 1])!,
                               start: p(0.5, 0), end: p(0.5, 1), options: [])
        ctx.restoreGState()
        // White emblem centred in the circle (the stem sits on the centre line).
        let w: CGFloat = 0.56
        ctx.translateBy(x: 0.5 - stemX * w, y: 0.13); ctx.scaleBy(x: w, y: w)
        ctx.setFillColor(.white)
        ctx.addPath(emblem()); ctx.fillPath(using: .evenOdd)
        stemAndLetters(ctx)
        ctx.restoreGState()
    }

    /// App icon: the badge on a white macOS icon tile, into a `size`-point square (y-up context).
    static func drawIcon(_ ctx: CGContext, size: CGFloat) {
        ctx.saveGState()
        ctx.scaleBy(x: size, y: size)
        // macOS icon grid: 824/1024 tile.
        let m: CGFloat = 100 / 1024
        let tile = CGPath(roundedRect: CGRect(x: m, y: m, width: 1 - 2 * m, height: 1 - 2 * m), cornerWidth: 0.185, cornerHeight: 0.185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.012), blur: 0.03, color: CGColor(gray: 0, alpha: 0.3))
        ctx.addPath(tile); ctx.setFillColor(.white); ctx.fillPath()
        ctx.restoreGState()
        drawBadge(ctx, in: CGRect(x: 0.17, y: 0.17, width: 0.66, height: 0.66))
        ctx.restoreGState()
    }

    // MARK: TAU's ring shapes

    /// From TAU's logo artwork (PDF units, y up): the heavy ring and the three interlocking rings,
    /// plus the bounding circle of the left badge they sit next to.
    private static let tauBadge = CGRect(x: 496.1422 - 18.372, y: 85.699 - 35.894, width: 36.745, height: 35.894)
    private static let tauRings: [(dx: CGFloat, dy: CGFloat, d: String)] = [
        (553.7148, 70.1595, "m 0,0 c 0,8.568 -7.136,15.539 -15.908,15.539 -3.446,0 -6.705,-1.053 -9.459,-3.05 -6.724,-1.945 -11.378,-8.003 -11.378,-14.897 0,-6.894 4.655,-12.953 11.379,-14.898 2.753,-1.996 6.012,-3.048 9.458,-3.048 8.772,0 15.908,6.97 15.908,15.537 0,0.797 -0.065,1.605 -0.194,2.408 C -0.065,-1.605 0,-0.796 0,0 m -13.205,-11.258 c -0.836,-0.177 -1.69,-0.266 -2.548,-0.266 -5.617,0 -10.452,3.807 -11.668,9.115 1.216,5.31 6.051,9.117 11.668,9.117 0.858,0 1.712,-0.089 2.548,-0.266 2.648,-2.227 4.156,-5.424 4.156,-8.85 0,-3.426 -1.508,-6.623 -4.156,-8.85"),
        (589.4198, 66.2591, "m 0,0 c -2.765,-6.337 -10.378,-9.346 -17.005,-6.723 -6.627,2.624 -9.758,9.887 -6.994,16.224 2.765,6.337 10.378,9.347 17.006,6.723 C -0.367,13.6 2.765,6.337 0,0 m 2.154,-0.853 c 3.255,7.463 -0.445,16.047 -8.249,19.137 -7.805,3.09 -16.803,-0.468 -20.058,-7.93 -3.256,-7.462 0.445,-16.047 8.25,-19.137 7.804,-3.09 16.801,0.468 20.057,7.93"),
        (566.9156, 56.8448, "m 0,0 c -4.358,5.441 -3.262,13.236 2.445,17.412 5.709,4.176 13.867,3.151 18.224,-2.29 C 25.026,9.682 23.931,1.886 18.224,-2.29 12.516,-6.466 4.357,-5.44 0,0 M -1.855,-1.357 C 3.276,-7.764 12.918,-8.976 19.64,-4.058 26.362,0.859 27.655,10.073 22.524,16.479 17.394,22.886 7.751,24.098 1.029,19.18 -5.692,14.263 -6.986,5.05 -1.855,-1.357"),
        (569.6835, 80.1447, "m 0,0 c 7.122,0.896 13.639,-3.889 14.559,-10.689 0.919,-6.799 -4.108,-13.038 -11.23,-13.934 -7.121,-0.896 -13.639,3.89 -14.559,10.689 C -12.149,-7.134 -7.121,-0.896 0,0 m -0.299,2.21 c -8.386,-1.055 -14.329,-8.428 -13.246,-16.435 1.083,-8.008 8.787,-13.664 17.173,-12.608 8.386,1.055 14.328,8.428 13.246,16.436 C 15.791,-2.39 8.088,3.266 -0.299,2.21"),
    ]

    /// Minimal SVG path reader (M/m, L/l, H/h, V/v, C/c, Z/z) — enough for the shapes above.
    static func svgPath(_ d: String, offset: CGPoint = .zero) -> CGPath {
        var tokens: [String] = []
        var num = ""
        for ch in d {
            if ch.isLetter && ch != "e" { if !num.isEmpty { tokens.append(num); num = "" }; tokens.append(String(ch)) }
            else if ch == "," || ch == " " { if !num.isEmpty { tokens.append(num); num = "" } }
            else if ch == "-" && !num.isEmpty && num.last != "e" { tokens.append(num); num = "-" }
            else { num.append(ch) }
        }
        if !num.isEmpty { tokens.append(num) }
        let path = CGMutablePath()
        var cur = CGPoint.zero, start = CGPoint.zero, cmd = "M", i = 0
        func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func at(_ x: CGFloat, _ y: CGFloat, rel: Bool) -> CGPoint { rel ? p(cur.x + x, cur.y + y) : p(x + offset.x, y + offset.y) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = String(c); i += 1; if c == "z" || c == "Z" { path.closeSubpath(); cur = start; continue } }
            let rel = cmd == cmd.lowercased()
            switch cmd.lowercased() {
            case "m":
                cur = i == 1 && rel ? p(offset.x + n(), offset.y + n()) : at(n(), n(), rel: rel); start = cur; path.move(to: cur)
                cmd = rel ? "l" : "L"   // further pairs are line-tos
            case "l": cur = at(n(), n(), rel: rel); path.addLine(to: cur)
            case "h": let x = n(); cur = p(rel ? cur.x + x : x + offset.x, cur.y); path.addLine(to: cur)
            case "v": let y = n(); cur = p(cur.x, rel ? cur.y + y : y + offset.y); path.addLine(to: cur)
            case "c":
                let c1 = at(n(), n(), rel: rel), c2 = at(n(), n(), rel: rel), e = at(n(), n(), rel: rel)
                path.addCurve(to: e, control1: c1, control2: c2); cur = e
            default: i += 1
            }
        }
        return path
    }

    /// The lockup: badge, heavy ring, interlocking rings — scaled to fit `rect` (y-up context).
    static func drawLockup(_ ctx: CGContext, in rect: CGRect, rings: CGColor = navy) {
        let paths = tauRings.map { svgPath($0.d, offset: p($0.dx, $0.dy)) }
        let bounds = paths.reduce(tauBadge) { $0.union($1.boundingBoxOfPath) }
        let k = min(rect.width / bounds.width, rect.height / bounds.height)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX - bounds.midX * k, y: rect.midY - bounds.midY * k); ctx.scaleBy(x: k, y: k)
        drawBadge(ctx, in: tauBadge)
        ctx.setFillColor(rings)
        for path in paths { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Menu bar glyph (y-up context, `height` points): a solid circle with a knocked-out ✓, then TAU's two ring shapes.
    static func drawMenuBar(_ ctx: CGContext, height h: CGFloat) {
        let paths = tauRings.map { svgPath($0.d, offset: p($0.dx, $0.dy)) }
        let bounds = paths.reduce(tauBadge) { $0.union($1.boundingBoxOfPath) }
        let k = (h - 1) / bounds.height
        ctx.saveGState()
        ctx.translateBy(x: -bounds.minX * k, y: 0.5 - bounds.minY * k); ctx.scaleBy(x: k, y: k)
        ctx.setFillColor(.black)
        ctx.fillEllipse(in: tauBadge)
        for path in paths { ctx.addPath(path) }
        ctx.fillPath()
        // Knock a check mark out of the solid circle.
        let b = tauBadge
        ctx.setBlendMode(.clear); ctx.setStrokeColor(.black)
        ctx.setLineWidth(b.width * 0.14); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: p(b.minX + b.width * 0.27, b.minY + b.height * 0.48))
        ctx.addLine(to: p(b.minX + b.width * 0.44, b.minY + b.height * 0.31))
        ctx.addLine(to: p(b.minX + b.width * 0.74, b.minY + b.height * 0.68))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func menuBarWidth(height h: CGFloat) -> CGFloat {
        let bounds = tauRings.map { svgPath($0.d, offset: p($0.dx, $0.dy)).boundingBoxOfPath }.reduce(tauBadge) { $0.union($1) }
        return ceil(bounds.width * (h - 1) / bounds.height)
    }

    /// Menu bar template image (follows light/dark menu bar automatically).
    static let menuBarImage: NSImage = {
        let h: CGFloat = 16
        let img = NSImage(size: NSSize(width: menuBarWidth(height: h), height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMenuBar(ctx, height: h)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
