import AppKit
import CacaoSoundCuesCore
import SwiftUI

/// 音量ライン（曲の中で音量を変える線）。波形の上に重ねる。
/// 編集中は、線をクリックで点を足す・点をドラッグで動かす・⌥クリックで点を消す・
/// 点と点の間をクリックしてその区間を選ぶと、白い四角でつなぎの形（ベジエ曲線）を変えられる
struct VolumeLineView: View {
    @Binding var points: [VolumePoint]
    @Binding var selectedPoint: UUID?
    @Binding var selectedSegment: Int?
    let duration: Double
    let editing: Bool
    /// 再生中の位置（秒）と、いまの音量ラインの倍率
    var playhead: Double?
    var lineGain: Float?

    private enum Target { case point(Int), handle(segment: Int, second: Bool) }
    @State private var target: Target?
    @State private var moved = false
    private let grab: CGFloat = 10
    private static let lineColor = Color(red: 0.35, green: 0.78, blue: 0.98)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, size in
                draw(ctx, size)
            }
            .contentShape(Rectangle())
            .gesture(editing ? dragGesture(size) : nil)
        }
    }

    // MARK: - 座標

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat { duration > 0 ? CGFloat(t / duration) * w : 0 }
    private func t(_ x: CGFloat, _ w: CGFloat) -> Double { min(max(0, Double(x / max(1, w)) * duration), duration) }
    private func y(_ db: Double, _ h: CGFloat) -> CGFloat {
        CGFloat((VolumePoint.maxDB - db) / (VolumePoint.maxDB - VolumePoint.minDB)) * h
    }
    private func db(_ y: CGFloat, _ h: CGFloat) -> Double {
        let v = VolumePoint.maxDB - Double(y / max(1, h)) * (VolumePoint.maxDB - VolumePoint.minDB)
        return (min(max(v, VolumePoint.minDB), VolumePoint.maxDB) * 10).rounded() / 10
    }

    /// 区間 k（点 k → 点 k+1）の、ベジエの制御点の画面上の位置
    private func handles(_ k: Int, _ size: CGSize) -> (CGPoint, CGPoint, CGPoint, CGPoint)? {
        guard k >= 0, k + 1 < points.count else { return nil }
        let a = points[k], b = points[k + 1]
        let s = a.shape ?? VolumePoint.defaultShape
        let ax = x(a.time, size.width), bx = x(b.time, size.width)
        let ay = y(a.db, size.height), by = y(b.db, size.height)
        func p(_ u: Double, _ v: Double) -> CGPoint { CGPoint(x: ax + CGFloat(u) * (bx - ax), y: ay + CGFloat(v) * (by - ay)) }
        return (CGPoint(x: ax, y: ay), p(s.x1, s.y1), p(s.x2, s.y2), CGPoint(x: bx, y: by))
    }

    // MARK: - 描画

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        guard duration > 0, w > 0 else { return }
        // 0 dB の目安
        if editing {
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0, h)))
            zero.addLine(to: CGPoint(x: w, y: y(0, h)))
            ctx.stroke(zero, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        guard editing || !points.isEmpty else { return }

        // 線（1 ピクセルごとに音量ラインの値を取る）
        var line = Path()
        let cols = max(2, Int(w))
        for c in 0...cols {
            let px = CGFloat(c) * w / CGFloat(cols)
            let py = y(volumeLineDB(points, at: t(px, w)), h)
            if c == 0 { line.move(to: CGPoint(x: px, y: py)) } else { line.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.stroke(line, with: .color(Self.lineColor.opacity(editing ? 1 : 0.7)),
                   style: StrokeStyle(lineWidth: editing ? 2.5 : 1.5, lineJoin: .round))

        // 選んだ区間のつなぎの形（白い四角と腕）
        if editing, let k = selectedSegment, let (p0, c1, c2, p3) = handles(k, size),
           points[k].db != points[k + 1].db {
            var arms = Path()
            arms.move(to: p0); arms.addLine(to: c1)
            arms.move(to: p3); arms.addLine(to: c2)
            ctx.stroke(arms, with: .color(.white.opacity(0.75)), lineWidth: 1)
            for c in [c1, c2] {
                let r = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                ctx.fill(Path(r), with: .color(.white))
                ctx.stroke(Path(r), with: .color(Self.lineColor), lineWidth: 1.5)
            }
        }

        // 点
        for p in points {
            let selected = p.id == selectedPoint
            let r: CGFloat = selected ? 7 : 5
            let rect = CGRect(x: x(p.time, w) - r, y: y(p.db, h) - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(selected ? .white : Self.lineColor))
            ctx.stroke(Path(ellipseIn: rect), with: .color(selected ? Self.lineColor : .white), lineWidth: 1.5)
        }

        // 再生中の位置の音量
        if let playhead, let lineGain, !points.isEmpty {
            let dbNow = 20 * log10(Double(max(lineGain, 0.0001)))
            let c = CGPoint(x: x(playhead, w), y: y(dbNow, h))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.yellow))
        }
    }

    // MARK: - 操作

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                AppModel.endEditing()
                if target == nil && !moved { pick(g.startLocation, size) }
                if hypot(g.translation.width, g.translation.height) > 3 { moved = true }
                guard moved, let target else { return }
                switch target {
                case .point(let i): movePoint(i, to: g.location, size)
                case let .handle(k, second): moveHandle(k, second: second, to: g.location, size)
                }
            }
            .onEnded { g in
                if !moved { click(g.location, size) }
                target = nil
                moved = false
            }
    }

    private func pick(_ loc: CGPoint, _ size: CGSize) {
        if let k = selectedSegment, let (_, c1, c2, _) = handles(k, size) {
            if hypot(loc.x - c1.x, loc.y - c1.y) <= grab { target = .handle(segment: k, second: false); return }
            if hypot(loc.x - c2.x, loc.y - c2.y) <= grab { target = .handle(segment: k, second: true); return }
        }
        if let i = nearestPoint(loc, size) {
            target = .point(i)
            selectedPoint = points[i].id
        }
    }

    private func nearestPoint(_ loc: CGPoint, _ size: CGSize) -> Int? {
        var best: (Int, CGFloat)?
        for (i, p) in points.enumerated() {
            let d = hypot(loc.x - x(p.time, size.width), loc.y - y(p.db, size.height))
            if d <= grab, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func movePoint(_ i: Int, to loc: CGPoint, _ size: CGSize) {
        guard points.indices.contains(i) else { return }
        let lo = i > 0 ? points[i - 1].time + 0.01 : 0
        let hi = i + 1 < points.count ? points[i + 1].time - 0.01 : duration
        points[i].time = (min(max(t(loc.x, size.width), lo), hi) * 100).rounded() / 100
        points[i].db = db(loc.y, size.height)
    }

    private func moveHandle(_ k: Int, second: Bool, to loc: CGPoint, _ size: CGSize) {
        guard k + 1 < points.count else { return }
        let a = points[k], b = points[k + 1]
        let ax = x(a.time, size.width), bx = x(b.time, size.width)
        let ay = y(a.db, size.height), by = y(b.db, size.height)
        guard bx - ax > 1, abs(by - ay) > 1 else { return }
        let u = Double(min(max((loc.x - ax) / (bx - ax), 0), 1))
        let v = Double(min(max((loc.y - ay) / (by - ay), 0), 1))
        var s = a.shape ?? VolumePoint.defaultShape
        if second { s.x2 = u; s.y2 = v } else { s.x1 = u; s.y1 = v }
        points[k].shape = s
    }

    private func click(_ loc: CGPoint, _ size: CGSize) {
        let w = size.width, h = size.height
        // ⌥クリックで点を消す
        if NSEvent.modifierFlags.contains(.option) {
            if let i = nearestPoint(loc, size) {
                points.remove(at: i)
                selectedPoint = nil
                selectedSegment = nil
            }
            return
        }
        if let i = nearestPoint(loc, size) {
            selectedPoint = points[i].id
            return
        }
        let time = t(loc.x, w)
        let lineY = y(volumeLineDB(points, at: time), h)
        if abs(loc.y - lineY) <= 14 || points.isEmpty {
            // 線の上（または最初の1点）なら点を足す
            let p = VolumePoint(time: (time * 100).rounded() / 100, db: points.isEmpty ? db(loc.y, h) : volumeLineDB(points, at: time))
            points.append(p)
            points.sort { $0.time < $1.time }
            selectedPoint = p.id
            selectedSegment = nil
        } else {
            // 点と点の間をクリック → その区間を選ぶ（白い四角でつなぎの形を変えられる）
            selectedSegment = points.lastIndex { $0.time <= time }.flatMap { $0 + 1 < points.count ? $0 : nil }
            selectedPoint = nil
        }
    }
}
