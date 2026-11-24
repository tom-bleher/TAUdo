// Renders the AppIcon.iconset PNGs, the README lockup and a menu bar preview from Sources/UI/Logo.swift.
// Usage: scripts/make_icon.sh
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ w: Int, _ h: Int, to name: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

for pt in [16, 32, 128, 256, 512] {
    for s in [1, 2] {
        let px = pt * s
        png(px, px, to: "icon_\(pt)x\(pt)\(s == 2 ? "@2x" : "").png") { Logo.drawIcon($0, size: CGFloat(px)) }
    }
}
// README logo: the menu bar glyph, as it looks in a light and a dark menu bar.
let scale: CGFloat = 4
func glyph(_ h: CGFloat, to name: String, color: CGColor) {
    // Half a point of margin each side so antialiased ring edges aren't clipped.
    png(Int((Logo.menuBarWidth(height: h) + 1) * scale), Int(h * scale), to: name) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0.5, y: 0)
        Logo.drawMenuBar(ctx, height: h, color: color)
    }
}
glyph(60, to: "logo.png", color: CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
glyph(60, to: "logo-dark.png", color: .white)
glyph(16, to: "menubar_preview.png", color: .black)
