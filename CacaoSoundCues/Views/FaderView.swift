import CacaoSoundCuesCore
import SwiftUI

/// 縦の音量つまみ（シンプルなもの）。目盛りは +6・0・-10・-20・-40 だけ。
/// value が Binding なら動かせる（ダブルクリックで 0dB）。readOnly のときは表示だけ（自動で動く）
struct FaderView: View {
    @Binding var db: Double
    var readOnly = false
    var tint: Color = .accentColor
    var onChange: ((Double) -> Void)?
    /// ドラッグを始めたとき・終えたとき（右のつまみで音量ラインを記録するため）
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    @State private var dragging = false

    static let range: ClosedRange<Double> = -40...10
    private static let marks: [Double] = [6, 0, -10, -20, -40]

    /// dB → 下からの割合（0〜1）。下の方ほど目盛りが詰まるよう、ゆるやかな曲線にする
    static func fraction(_ db: Double) -> Double {
        let d = min(max(db, range.lowerBound), range.upperBound)
        let lin = (d - range.lowerBound) / (range.upperBound - range.lowerBound)
        return pow(lin, 1.6)
    }

    static func db(fraction f: Double) -> Double {
        let lin = pow(min(max(f, 0), 1), 1 / 1.6)
        return ((range.lowerBound + lin * (range.upperBound - range.lowerBound)) * 10).rounded() / 10
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let pad: CGFloat = 8
            let track = h - pad * 2
            let y = pad + track * CGFloat(1 - Self.fraction(db))
            ZStack(alignment: .topLeading) {
                // 目盛り
                ForEach(Self.marks, id: \.self) { m in
                    let my = pad + track * CGFloat(1 - Self.fraction(m))
                    Text(m > 0 ? "+\(Int(m))" : "\(Int(m))")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: 10, y: my)
                    Rectangle().fill(Color.secondary.opacity(m == 0 ? 0.8 : 0.4))
                        .frame(width: m == 0 ? 10 : 6, height: 1)
                        .position(x: geo.size.width / 2 + 10, y: my)
                }
                // 溝
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 4, height: track)
                    .position(x: geo.size.width / 2 + 4, y: h / 2)
                // つまみ
                RoundedRectangle(cornerRadius: 3)
                    .fill(readOnly ? tint : Color(nsColor: .controlColor))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(tint, lineWidth: readOnly ? 0 : 1.5))
                    .overlay(Rectangle().fill(readOnly ? Color.black.opacity(0.4) : tint).frame(height: 1.5))
                    .frame(width: 22, height: 12)
                    .shadow(radius: 1, y: 1)
                    .position(x: geo.size.width / 2 + 4, y: y)
            }
            .contentShape(Rectangle())
            .gesture(readOnly ? nil : DragGesture(minimumDistance: 0)
                .onChanged { g in
                    AppModel.endEditing()
                    if !dragging {
                        dragging = true
                        onBegin?()
                    }
                    let f = 1 - Double((g.location.y - pad) / max(1, track))
                    db = Self.db(fraction: f)
                    onChange?(db)
                }
                .onEnded { _ in
                    dragging = false
                    onEnd?()
                })
            .onTapGesture(count: 2) {
                guard !readOnly else { return }
                db = 0
                onChange?(0)
            }
        }
    }
}

/// 左右（PAN）の小さな横スライダー。ダブルクリックで中央
struct PanSlider: View {
    @Binding var pan: Double
    var tint: Color = .accentColor
    var onChange: ((Double) -> Void)?
    /// ドラッグを始めたとき・終えたとき（右の PAN スライダーで PANライン を記録するため）
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 1) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat((pan + 1) / 2) * (w - 10) + 5
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.3)).frame(height: 4)
                    Rectangle().fill(Color.secondary.opacity(0.7)).frame(width: 1, height: 8).position(x: w / 2, y: 6)
                    Circle().fill(tint).frame(width: 10, height: 10).position(x: x, y: 6)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in
                    dragging = false
                    onEnd?()
                }.onChanged { g in
                    AppModel.endEditing()
                    if !dragging {
                        dragging = true
                        onBegin?()
                    }
                    var v = Double((g.location.x - 5) / max(1, w - 10)) * 2 - 1
                    v = (min(max(v, -1), 1) * 20).rounded() / 20
                    if abs(v) < 0.05 { v = 0 }   // 中央に吸い付く
                    pan = v
                    onChange?(v)
                })
                .onTapGesture(count: 2) {
                    pan = 0
                    onChange?(0)
                }
            }
            .frame(height: 12)
            Text(Self.label(pan))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    static func label(_ pan: Double) -> String {
        if abs(pan) < 0.01 { return "C" }
        return pan < 0 ? "L\(Int((-pan * 100).rounded()))" : "R\(Int((pan * 100).rounded()))"
    }
}
