import CacaoSoundCuesCore
import SwiftUI

/// 波形と再生範囲（開始＝緑、終了＝赤）。線の近くをドラッグして動かす。
/// 上の端のオレンジの丸をドラッグするとフェードの長さが変わる。
/// 再生中に線から離れた所をクリックすると、その位置へ移る
struct WaveformView: View {
    let peaks: [Float]
    let duration: Double
    @Binding var inPoint: Double
    @Binding var outPoint: Double?
    var playhead: Double?
    /// いま進んでいるフェード（秒で、始まり・長さ・始まりと終わりの音量）。その形を明るく描き、点が上を動く
    var activeFade: ActiveFade?
    /// 設定したフェードの形を波形に重ねて表示し、ドラッグで変える（秒）
    @Binding var fadeIn: Double
    @Binding var fadeOut: Double
    /// 終了位置へ向けて自動でフェードアウトする（OFF のときフェードアウトは止めたときだけなので点線で示す）
    var fadeOutAtEnd: Bool
    /// フェードの形。制御点（白い四角）をドラッグするとカスタム（ベジエ）になる
    @Binding var curve: FadeCurve
    @Binding var fadeInBezier: FadeBezier?
    @Binding var fadeOutBezier: FadeBezier?
    /// 再生中に波形をクリックしたとき（秒）
    var onSeek: ((Double) -> Void)?
    /// 表示だけ（Pro 版の台本パネルの「鳴っている音」）。つまみ・制御点を描かず、操作も受けない
    var readOnly = false

    private enum Marker { case start, end, fadeIn, fadeOut, bezier(rising: Bool, second: Bool), seek }
    /// フェードの丸をつかめる上端の高さ
    private let handleBand: CGFloat = 24
    /// 線をつかめる距離（ポイント）
    private let grabDistance: CGFloat = 10
    @State private var dragging: Marker?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let xIn = x(inPoint, w)
            let xOut = x(outPoint ?? duration, w)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    guard !peaks.isEmpty, size.width > 0 else { return }
                    let mid = size.height / 2
                    var path = Path()
                    let cols = Int(size.width)
                    for c in 0..<cols {
                        let a = c * peaks.count / cols
                        let b = max(a + 1, (c + 1) * peaks.count / cols)
                        var m: Float = 0
                        for k in a..<min(b, peaks.count) { m = max(m, peaks[k]) }
                        let hh = max(0.5, CGFloat(min(1, m)) * mid)
                        path.addRect(CGRect(x: CGFloat(c), y: mid - hh, width: 1, height: hh * 2))
                    }
                    ctx.fill(path, with: .color(.white.opacity(0.92)))
                }

                Rectangle().fill(.black.opacity(0.5))
                    .frame(width: max(0, xIn), height: h)
                Rectangle().fill(.black.opacity(0.5))
                    .frame(width: max(0, w - xOut), height: h)
                    .offset(x: xOut)

                // フェードの形（音量のカーブ）。線より上の、音量が下がっている所をうすく塗る
                Canvas { ctx, size in
                    let (curvePath, shade) = envelope(size: size, xIn: xIn, xOut: xOut)
                    ctx.fill(shade, with: .color(.orange.opacity(0.28)))
                    ctx.stroke(curvePath, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    // 自動フェードアウトが OFF のときは、止めたときのフェードアウトの長さを点線で示す
                    if !fadeOutAtEnd, fadeOut > 0 {
                        ctx.stroke(stopFadePath(size: size, xIn: xIn, xOut: xOut), with: .color(.orange.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    // ベジエの制御点（白い四角）と、端点から伸びる腕
                    for rising in [true, false] where !readOnly {
                        guard let g = bezierGeometry(rising: rising, xIn: xIn, xOut: xOut, size: size) else { continue }
                        var arms = Path()
                        arms.move(to: g.p0); arms.addLine(to: g.c1)
                        arms.move(to: g.p3); arms.addLine(to: g.c2)
                        ctx.stroke(arms, with: .color(.white.opacity(0.7)), lineWidth: 1)
                        for c in [g.c1, g.c2] {
                            let r = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                            ctx.fill(Path(r), with: .color(.white))
                            ctx.stroke(Path(r), with: .color(.orange), lineWidth: 1.5)
                        }
                    }
                    // フェードの長さを変える丸（上端）
                    for hx in [handleX(fadeIn: true, xIn: xIn, xOut: xOut, w: size.width),
                               handleX(fadeIn: false, xIn: xIn, xOut: xOut, w: size.width)] where !readOnly {
                        let r = CGRect(x: hx - 7, y: 1, width: 14, height: 14)
                        ctx.fill(Path(ellipseIn: r), with: .color(.orange))
                        ctx.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: 1.5)
                    }
                }
                .allowsHitTesting(false)

                marker(at: xIn, color: .green, h: h)
                marker(at: xOut, color: .red, h: h)

                if let fade = activeFade, let playhead {
                    let dot = CGPoint(x: x(playhead, w), y: h * (1 - CGFloat(min(max(fade.level, 0), 1))))
                    Canvas { ctx, size in
                        ctx.stroke(activeFadePath(fade, size: size), with: .color(.yellow),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        let r = CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)
                        ctx.fill(Path(ellipseIn: r), with: .color(.yellow))
                        ctx.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: 2)
                    }
                    .shadow(color: .yellow.opacity(0.7), radius: 4)
                    .allowsHitTesting(false)
                    Text(fade.rising ? L("フェードイン ↑") : L("フェードアウト ↓"))
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.yellow))
                        .fixedSize()
                        .offset(x: min(dot.x + 10, w - 110), y: min(max(dot.y - 24, 2), h - 20))
                        .allowsHitTesting(false)
                }
                if let playhead {
                    Rectangle().fill(.yellow).frame(width: 2, height: h).offset(x: x(playhead, w) - 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(readOnly ? nil :
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard duration > 0, w > 0 else { return }
                        if dragging == nil { AppModel.endEditing() }
                        if dragging == nil, g.startLocation.y <= handleBand {
                            // 上端ではフェードの丸を優先してつかむ
                            let hIn = abs(g.startLocation.x - handleX(fadeIn: true, xIn: xIn, xOut: xOut, w: w))
                            let hOut = abs(g.startLocation.x - handleX(fadeIn: false, xIn: xIn, xOut: xOut, w: w))
                            if min(hIn, hOut) <= grabDistance + 4 {
                                dragging = hIn <= hOut ? .fadeIn : .fadeOut
                            }
                        }
                        if dragging == nil {
                            // ベジエの制御点
                            let size = CGSize(width: w, height: h)
                            var best: (Marker, CGFloat)?
                            for rising in [true, false] {
                                guard let geo = bezierGeometry(rising: rising, xIn: xIn, xOut: xOut, size: size) else { continue }
                                for (second, c) in [(false, geo.c1), (true, geo.c2)] {
                                    let d = hypot(g.startLocation.x - c.x, g.startLocation.y - c.y)
                                    if d <= grabDistance, d < (best?.1 ?? .infinity) {
                                        best = (.bezier(rising: rising, second: second), d)
                                    }
                                }
                            }
                            if let best {
                                dragging = best.0
                                // 決まった形からカスタムに切り替えるときは、今の形から始める
                                if curve != .custom {
                                    fadeInBezier = FadeBezier.preset(curve, rising: true)
                                    fadeOutBezier = FadeBezier.preset(curve, rising: false)
                                    curve = .custom
                                }
                            }
                        }
                        if dragging == nil {
                            let dIn = abs(g.startLocation.x - xIn)
                            let dOut = abs(g.startLocation.x - xOut)
                            if min(dIn, dOut) <= grabDistance {
                                dragging = dIn <= dOut ? .start : .end
                            } else {
                                dragging = .seek
                            }
                        }
                        let t = min(max(0, Double(g.location.x / w) * duration), duration)
                        switch dragging {
                        case .start: inPoint = min(t, (outPoint ?? duration) - 0.01)
                        case .end:
                            let v = max(t, inPoint + 0.01)
                            outPoint = v >= duration - 0.005 ? nil : v
                        case .fadeIn:
                            let len = (outPoint ?? duration) - inPoint
                            fadeIn = ((min(max(0, t - inPoint), len)) * 10).rounded() / 10
                        case .fadeOut:
                            let end = outPoint ?? duration
                            fadeOut = ((min(max(0, end - t), end - inPoint)) * 10).rounded() / 10
                        case let .bezier(rising, second):
                            guard let geo = bezierGeometry(rising: rising, xIn: xIn, xOut: xOut, size: CGSize(width: w, height: h))
                            else { break }
                            let nx = Double(min(max((g.location.x - geo.rect.minX) / max(1, geo.rect.width), 0), 1))
                            let ny = Double(min(max((h - g.location.y) / h, 0), 1))
                            var b = (rising ? fadeInBezier : fadeOutBezier) ?? FadeBezier.preset(.equalPower, rising: rising)
                            if second { b.x2 = nx; b.y2 = ny } else { b.x1 = nx; b.y1 = ny }
                            if rising { fadeInBezier = b } else { fadeOutBezier = b }
                        case .seek, nil: break
                        }
                    }
                    .onEnded { g in
                        if case .seek = dragging, playhead != nil, duration > 0, w > 0 {
                            onSeek?(min(max(0, Double(g.location.x / w) * duration), duration))
                        }
                        dragging = nil
                    }
            )
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Self.cacao))
    }

    /// 波形の背景（カカオ色）
    static let cacao = Color(red: 0x6B / 255, green: 0x44 / 255, blue: 0x30 / 255)

    /// 開始〜終了の間の音量カーブ（下端 = 0、上端 = 1）と、その上側の塗り
    private func envelope(size: CGSize, xIn: CGFloat, xOut: CGFloat) -> (Path, Path) {
        let w = size.width, h = size.height
        let start = inPoint, end = outPoint ?? duration
        let len = max(0.001, end - start)
        let fi = min(fadeIn, len), fo = fadeOutAtEnd ? min(fadeOut, len) : 0
        func gain(_ t: Double) -> Double {
            var g = 1.0
            if fi > 0, t < start + fi { g = min(g, shape((t - start) / fi, rising: true)) }
            if fo > 0, t > end - fo { g = min(g, shape((t - (end - fo)) / fo, rising: false)) }
            return g
        }
        var line = Path()
        var shade = Path()
        let steps = max(2, Int(xOut - xIn))
        shade.move(to: CGPoint(x: xIn, y: 0))
        for i in 0...steps {
            let px = xIn + (xOut - xIn) * CGFloat(i) / CGFloat(steps)
            let t = Double(px / w) * duration
            let y = h * (1 - CGFloat(gain(t)))
            if i == 0 { line.move(to: CGPoint(x: px, y: y)) } else { line.addLine(to: CGPoint(x: px, y: y)) }
            shade.addLine(to: CGPoint(x: px, y: y))
        }
        shade.addLine(to: CGPoint(x: xOut, y: 0))
        shade.closeSubpath()
        return (line, shade)
    }

    /// いま進んでいるフェードの形（始まりの位置から長さぶん。止めたときのフェードアウトは止めた位置から）
    private func activeFadePath(_ f: ActiveFade, size: CGSize) -> Path {
        var p = Path()
        let steps = 60
        for i in 0...steps {
            let q = Double(i) / Double(steps)
            let s = f.rising ? shape(q, rising: true) : 1 - shape(q, rising: false)
            let g = f.from + (f.to - f.from) * s
            let pt = CGPoint(x: x(f.start + f.length * q, size.width), y: size.height * (1 - CGFloat(min(max(g, 0), 1))))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// 実際に使うフェードの形
    private func bezier(rising: Bool) -> FadeBezier {
        if curve == .custom, let b = rising ? fadeInBezier : fadeOutBezier { return b }
        return FadeBezier.preset(curve == .custom ? .equalPower : curve, rising: rising)
    }

    /// フェードの区間（四角）と、ベジエの端点・制御点の画面上の位置。区間が狭すぎるときは nil
    private func bezierGeometry(rising: Bool, xIn: CGFloat, xOut: CGFloat, size: CGSize)
        -> (rect: CGRect, p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint)? {
        guard duration > 0 else { return nil }
        let len = (outPoint ?? duration) - inPoint
        let secs = min(rising ? fadeIn : fadeOut, len)
        let fw = CGFloat(secs / duration) * size.width
        guard fw >= 24 else { return nil }
        let h = size.height
        let rect = CGRect(x: rising ? xIn : xOut - fw, y: 0, width: fw, height: h)
        let b = bezier(rising: rising)
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + CGFloat(x) * fw, y: h * (1 - CGFloat(y))) }
        return (rect, pt(0, rising ? 0 : 1), pt(b.x1, b.y1), pt(b.x2, b.y2), pt(1, rising ? 1 : 0))
    }

    /// フェードの丸の位置（フェードインは開始から、フェードアウトは終了から、それぞれの長さだけ内側）
    private func handleX(fadeIn isIn: Bool, xIn: CGFloat, xOut: CGFloat, w: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let len = (outPoint ?? duration) - inPoint
        let px = CGFloat(min(isIn ? fadeIn : fadeOut, len) / duration) * w
        return isIn ? xIn + px : xOut - px
    }

    /// 止めたときのフェードアウトの形（終了位置の手前に置いた見本）
    private func stopFadePath(size: CGSize, xIn: CGFloat, xOut: CGFloat) -> Path {
        let h = size.height
        let len = (outPoint ?? duration) - inPoint
        let fo = min(fadeOut, len)
        let x0 = xOut - CGFloat(fo / duration) * size.width
        var p = Path()
        let steps = max(2, Int(xOut - x0))
        for i in 0...steps {
            let px = x0 + (xOut - x0) * CGFloat(i) / CGFloat(steps)
            let y = h * (1 - CGFloat(shape(Double(i) / Double(steps), rising: false)))
            if i == 0 { p.move(to: CGPoint(x: px, y: y)) } else { p.addLine(to: CGPoint(x: px, y: y)) }
        }
        return p
    }

    /// ミキサーと同じフェードの音量（p: 0〜1 の進み具合）。rising はフェードイン、false はフェードアウト
    private func shape(_ p: Double, rising: Bool) -> Double {
        let p = min(max(p, 0), 1)
        switch curve {
        case .linear: return rising ? p : 1 - p
        case .equalPower: return rising ? sin(p * .pi / 2) : cos(p * .pi / 2)
        case .sCurve: return rising ? 0.5 - 0.5 * cos(p * .pi) : 0.5 + 0.5 * cos(p * .pi)
        case .custom: return bezier(rising: rising).gain(at: p, rising: rising)
        }
    }

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(t / duration) * w : 0
    }

    private func marker(at x: CGFloat, color: Color, h: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: 2, height: h).offset(x: x - 1)
    }
}

/// 波形に描く、いま進んでいるフェード
struct ActiveFade {
    var start: Double
    var length: Double
    var from: Double
    var to: Double
    var level: Double
    var rising: Bool { to > from }
}
