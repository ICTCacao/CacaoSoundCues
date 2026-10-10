import Foundation

/// フェードの形をベジエ曲線で表す（CSS の cubic-bezier と同じく、両端は固定で制御点2つ）。
/// 横（x）は時間の進み 0〜1、縦（y）は音量 0〜1。
/// フェードインは (0,0)→(1,1)、フェードアウトは (0,1)→(1,0) を結ぶ。
public struct FadeBezier: Codable, Hashable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// 決まった形（直線・等パワー・S字）に近いベジエ
    public static func preset(_ curve: FadeCurve, rising: Bool) -> FadeBezier {
        switch (curve, rising) {
        case (.linear, true): return FadeBezier(1.0 / 3, 1.0 / 3, 2.0 / 3, 2.0 / 3)
        case (.linear, false): return FadeBezier(1.0 / 3, 2.0 / 3, 2.0 / 3, 1.0 / 3)
        // 制御点の横は 1/3・2/3 に置き、縦は両端の傾きから決める（傾き × 1/3）
        case (.sCurve, true): return FadeBezier(1.0 / 3, 0, 2.0 / 3, 1)
        case (.sCurve, false): return FadeBezier(1.0 / 3, 1, 2.0 / 3, 0)
        case (_, true): return FadeBezier(1.0 / 3, Double.pi / 6, 2.0 / 3, 1)        // sin(p・π/2)
        case (_, false): return FadeBezier(1.0 / 3, 1, 2.0 / 3, 1 - Double.pi / 6)    // cos(p・π/2)
        }
    }

    /// 進み p（0〜1）のときの音量（0〜1）
    public func gain(at p: Double, rising: Bool) -> Double {
        Double(bezierGain(SIMD4(Float(x1), Float(y1), Float(x2), Float(y2)), rising: rising, at: Float(p)))
    }

    public var simd: SIMD4<Float> { SIMD4(Float(x1), Float(y1), Float(x2), Float(y2)) }
}

/// ベジエの音量（音声スレッドから呼ぶのでメモリ確保なし）。x(t) = p を二分法で解いて y(t) を返す
@inline(__always)
func bezierGain(_ b: SIMD4<Float>, rising: Bool, at p: Float) -> Float {
    let x = min(max(p, 0), 1)
    let y0: Float = rising ? 0 : 1
    let y3: Float = rising ? 1 : 0
    var lo: Float = 0, hi: Float = 1, t = x
    for _ in 0..<16 {
        let u = 1 - t
        let xt = 3 * u * u * t * b.x + 3 * u * t * t * b.z + t * t * t
        if xt < x { lo = t } else { hi = t }
        t = (lo + hi) / 2
    }
    let u = 1 - t
    let y = u * u * u * y0 + 3 * u * u * t * b.y + 3 * u * t * t * b.w + t * t * t * y3
    return min(max(y, 0), 1)
}
