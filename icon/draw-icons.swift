import AppKit
import CoreGraphics

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
    draw(ctx)
    return ctx.makeImage()!
}
func save(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// CacaoTrans と同じ色（ICTCacao ロゴのブラウン）
let cacaoTop: UInt32 = 0x8B523A      // rgb(139, 82, 58)
let cacaoBottom: UInt32 = 0x5C3222   // rgb(92, 50, 34)
let cream: UInt32 = 0xF6E9DC         // rgb(246, 233, 220)

/// カカオ豆（濃いチョコレート色の楕円）と、豆からはみ出す波形（山が3つ）
/// overflow: 波形を豆の外まではみ出させる（地が明るい書類アイコンでは見えなくなるので false）
func bean(_ ctx: CGContext, center: CGPoint, length: CGFloat, shadow: Bool = true, overflow: Bool = true) {
    let w = length, h = length * 0.64
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let path = CGPath(ellipseIn: rect, transform: nil)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -length * 0.035), blur: length * 0.07, color: rgb(0x1E0F08, 0.5))
        ctx.addPath(path); ctx.setFillColor(rgb(0x4A2717)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    linear(ctx, [rgb(0x6E3C25), rgb(0x4A2717), rgb(0x2E170D)], from: CGPoint(x: 0, y: h / 2), to: CGPoint(x: 0, y: -h / 2))
    ctx.setFillColor(rgb(0xFFFFFF, 0.10))   // 豆のつや
    ctx.fillEllipse(in: CGRect(x: -w * 0.30, y: h * 0.10, width: w * 0.46, height: h * 0.26))
    ctx.restoreGState()

    // 波形: 山を3つ（左・中央・右）。豆の外まではみ出してよい
    let bars = 25
    let span = w * (overflow ? 1.12 : 0.84)
    let scale: CGFloat = overflow ? 1.25 : 0.78
    if !overflow { ctx.addPath(path); ctx.clip() }
    let barW = span / CGFloat(bars) * 0.52
    let jitter: [CGFloat] = [0.8, 1.0, 0.85, 1.0, 0.9, 1.0, 0.82, 1.0, 0.92, 0.86, 1.0, 0.9, 1.0,
                             0.88, 1.0, 0.9, 0.84, 1.0, 0.9, 1.0, 0.86, 1.0, 0.9, 0.82, 1.0]
    func hump(_ x: CGFloat, _ c: CGFloat, _ a: CGFloat) -> CGFloat { a * exp(-pow((x - c) / 0.17, 2)) }
    ctx.setFillColor(rgb(cream))
    for i in 0..<bars {
        let u = (CGFloat(i) + 0.5) / CGFloat(bars) * 2 - 1          // -1 … 1
        let env = max(hump(u, -0.56, 0.72), hump(u, 0, 1.0), hump(u, 0.56, 0.78))
        let bh = max(h * 0.08, h * scale * env * jitter[i])
        let x = u * span / 2
        let r = CGRect(x: x - barW / 2, y: -bh / 2, width: barW, height: bh)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    }
    ctx.fillPath()
    ctx.restoreGState()
}

// ---------- アプリアイコン ----------
let app = canvas { ctx in
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.30))
    ctx.addPath(squircle); ctx.setFillColor(rgb(cacaoBottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    linear(ctx, [rgb(cacaoTop), rgb(cacaoBottom)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // CacaoTrans と同じ、上からのうすい光
    linear(ctx, [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 560))
    ctx.restoreGState()
    bean(ctx, center: CGPoint(x: 512, y: 512), length: 600)
}
save(app, CommandLine.arguments[1] + "/AppIcon1024.png")

// ---------- 書類アイコン（キューシート .ccsc）----------
let doc = canvas { ctx in
    let page = CGMutablePath()
    let L: CGFloat = 196, R: CGFloat = 828, B: CGFloat = 92, T: CGFloat = 932, fold: CGFloat = 150
    page.move(to: CGPoint(x: L + 24, y: B))
    page.addLine(to: CGPoint(x: R - 24, y: B)); page.addQuadCurve(to: CGPoint(x: R, y: B + 24), control: CGPoint(x: R, y: B))
    page.addLine(to: CGPoint(x: R, y: T - fold))
    page.addLine(to: CGPoint(x: R - fold, y: T))
    page.addLine(to: CGPoint(x: L + 24, y: T)); page.addQuadCurve(to: CGPoint(x: L, y: T - 24), control: CGPoint(x: L, y: T))
    page.addLine(to: CGPoint(x: L, y: B + 24)); page.addQuadCurve(to: CGPoint(x: L + 24, y: B), control: CGPoint(x: L, y: B))
    page.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.3))
    ctx.addPath(page); ctx.setFillColor(rgb(0xFBF5EC)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(page); ctx.clip()
    linear(ctx, [rgb(0xFDF9F3), rgb(0xF1E3D2)], from: CGPoint(x: 512, y: T), to: CGPoint(x: 512, y: B))
    // 見出しの帯（カカオ色）
    linear(ctx, [rgb(cacaoTop), rgb(cacaoBottom)], from: CGPoint(x: 512, y: T - 90), to: CGPoint(x: 512, y: T - 210))
    ctx.setFillColor(rgb(0xFDF9F3)); ctx.fill(CGRect(x: L, y: B, width: R - L, height: T - 210 - B))
    linear(ctx, [rgb(0xFDF9F3, 0), rgb(0xF1E3D2, 0.9)], from: CGPoint(x: 512, y: T - 210), to: CGPoint(x: 512, y: B))
    ctx.setFillColor(rgb(0xFDF9F3)); ctx.fill(CGRect(x: L, y: T - 90, width: R - L, height: 90))
    ctx.restoreGState()
    // 折り返し
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: R - fold, y: T)); flap.addLine(to: CGPoint(x: R - fold, y: T - fold + 18))
    flap.addQuadCurve(to: CGPoint(x: R - fold + 18, y: T - fold), control: CGPoint(x: R - fold, y: T - fold))
    flap.addLine(to: CGPoint(x: R, y: T - fold)); flap.closeSubpath()
    ctx.addPath(flap); ctx.setFillColor(rgb(0xDCC3AA)); ctx.fillPath()
    // キューの行（キーの印 + 線）
    let rows: [(UInt32, CGFloat)] = [(0xE89A8E, 0.78), (0x9CC79A, 0.62), (0x9DBDE0, 0.70), (0xE9C878, 0.5)]
    for (i, row) in rows.enumerated() {
        let y = T - 290 - CGFloat(i) * 92
        let key = CGRect(x: L + 60, y: y - 30, width: 64, height: 60)
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(rgb(row.0)); ctx.fillPath()
        let line = CGRect(x: L + 150, y: y - 11, width: (R - L - 220) * row.1, height: 22)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.setFillColor(rgb(0xC9AE95)); ctx.fillPath()
    }
    bean(ctx, center: CGPoint(x: 512, y: 215), length: 250, shadow: false, overflow: false)
}
save(doc, CommandLine.arguments[1] + "/DocIcon1024.png")

// 並べた確認用
let preview = NSImage(size: NSSize(width: 1100, height: 560))
preview.lockFocus()
NSColor(srgbRed: 0.94, green: 0.89, blue: 0.83, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1100, height: 560).fill()
NSImage(cgImage: app, size: .zero).draw(in: NSRect(x: 20, y: 30, width: 500, height: 500))
NSImage(cgImage: doc, size: .zero).draw(in: NSRect(x: 580, y: 30, width: 500, height: 500))
preview.unlockFocus()
try! NSBitmapImageRep(data: preview.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/preview.png"))
