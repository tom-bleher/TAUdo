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
// README lockup: navy rings for light backgrounds, light rings for dark ones.
let lockup = CGRect(x: 0, y: 0, width: 1200, height: 380)
png(1200, 380, to: "logo.png") { Logo.drawLockup($0, in: lockup.insetBy(dx: 20, dy: 20)) }
png(1200, 380, to: "logo-dark.png") {
    Logo.drawLockup($0, in: lockup.insetBy(dx: 20, dy: 20), rings: CGColor(srgbRed: 0.78, green: 0.86, blue: 0.97, alpha: 1))
}
// Menu bar glyph at 4×.
let scale: CGFloat = 4, h: CGFloat = 16
png(Int(Logo.menuBarWidth(height: h) * scale), Int(h * scale), to: "menubar_preview.png") { ctx in
    ctx.scaleBy(x: scale, y: scale)
    Logo.drawMenuBar(ctx, height: h)
}
