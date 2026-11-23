// Renders the AppIcon.iconset PNGs (and a preview of the menu bar glyph) from Sources/UI/Logo.swift.
// Usage: scripts/make_icon.sh
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ w: Int, _ h: Int, to url: URL, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}

for pt in [16, 32, 128, 256, 512] {
    for s in [1, 2] {
        let px = pt * s
        png(px, px, to: out.appendingPathComponent("icon_\(pt)x\(pt)\(s == 2 ? "@2x" : "").png")) { Logo.drawIcon($0, size: CGFloat(px)) }
    }
}
// Menu bar glyph at 4×, y-down like AppKit's flipped image.
let scale: CGFloat = 4, h: CGFloat = 16
png(Int(Logo.menuBarWidth(height: h) * scale), Int(h * scale), to: out.appendingPathComponent("menubar_preview.png")) { ctx in
    ctx.translateBy(x: 0, y: h * scale); ctx.scaleBy(x: scale, y: -scale)
    Logo.drawMenuBar(ctx, height: h)
}
