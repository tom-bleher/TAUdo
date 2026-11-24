import AppKit

/// The TAUdo logo: three circles as a checklist — done (a solid circle with a ✓), in progress (a heavy ring),
/// to do (interlocking rings). The rings are taken from Tel Aviv University's logo artwork (its trademark).
/// - Menu bar and README: the whole logo.
/// - App icon: the check circle on a white tile.
/// - DMG window: the rings with an empty slot for the check circle, which you fill by dragging the app in.
enum Logo {
    static let ink = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    /// Diameter of the check circle in the app icon, as a fraction of the icon (centred).
    static let iconCircle: CGFloat = 0.62

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// The check circle filling `b` (y-up context): the ✓ drawn in `check`, or knocked out when nil.
    static func drawCheckCircle(_ ctx: CGContext, in b: CGRect, color: CGColor, check: CGColor? = nil) {
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.fillEllipse(in: b)
        if let check { ctx.setStrokeColor(check) } else { ctx.setBlendMode(.clear); ctx.setStrokeColor(.black) }
        ctx.setLineWidth(b.width * 0.14); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: p(b.minX + b.width * 0.27, b.minY + b.height * 0.48))
        ctx.addLine(to: p(b.minX + b.width * 0.44, b.minY + b.height * 0.31))
        ctx.addLine(to: p(b.minX + b.width * 0.74, b.minY + b.height * 0.68))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The heavy ring and interlocking rings, placed for a check circle in `circle` (y-up context).
    static func drawRings(_ ctx: CGContext, beside circle: CGRect, color: CGColor) {
        let k = circle.width / tauCircle.width
        ctx.saveGState()
        ctx.translateBy(x: circle.minX - tauCircle.minX * k, y: circle.minY - tauCircle.minY * k)
        ctx.scaleBy(x: k, y: k)
        ctx.setFillColor(color)
        for path in ringPaths { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// The whole logo, `height` points tall, from x = 0 (y-up context).
    static func drawLogo(_ ctx: CGContext, height h: CGFloat, color: CGColor = .black) {
        let bounds = ringPaths.reduce(tauCircle) { $0.union($1.boundingBoxOfPath) }
        let k = (h - 1) / bounds.height
        let circle = CGRect(x: (tauCircle.minX - bounds.minX) * k, y: 0.5 + (tauCircle.minY - bounds.minY) * k,
                            width: tauCircle.width * k, height: tauCircle.height * k)
        drawCheckCircle(ctx, in: circle, color: color)
        drawRings(ctx, beside: circle, color: color)
    }

    static func logoWidth(height h: CGFloat) -> CGFloat {
        let bounds = ringPaths.reduce(tauCircle) { $0.union($1.boundingBoxOfPath) }
        return ceil(bounds.width * (h - 1) / bounds.height)
    }

    /// App icon: the check circle on a white macOS icon tile, into a `size`-point square (y-up context).
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
        let o = (1 - iconCircle) / 2
        drawCheckCircle(ctx, in: CGRect(x: o, y: o, width: iconCircle, height: iconCircle), color: ink, check: .white)
        ctx.restoreGState()
    }

    // MARK: TAU's ring shapes

    /// From TAU's logo artwork (PDF units, y up): the heavy ring and the three interlocking rings,
    /// plus the bounding circle of the check circle they sit next to.
    private static let tauCircle = CGRect(x: 496.1422 - 18.372, y: 85.699 - 35.894, width: 36.745, height: 35.894)
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

    private static let ringPaths = tauRings.map { svgPath($0.d, offset: p($0.dx, $0.dy)) }

    /// Menu bar template image (follows light/dark menu bar automatically).
    static let menuBarImage: NSImage = {
        let h: CGFloat = 16
        let img = NSImage(size: NSSize(width: logoWidth(height: h), height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawLogo(ctx, height: h)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
