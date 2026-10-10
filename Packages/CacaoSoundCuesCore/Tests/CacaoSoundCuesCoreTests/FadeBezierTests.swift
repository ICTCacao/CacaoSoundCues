import XCTest
@testable import CacaoSoundCuesCore

/// 決まった形のベジエが元の式に近いか（カスタムに切り替えたとき形が急に変わらないように）
final class FadeBezierTests: XCTestCase {
    func testPresetsMatchFormulas() {
        let cases: [(FadeCurve, Bool, (Double) -> Double)] = [
            (.linear, true, { $0 }),
            (.linear, false, { 1 - $0 }),
            (.equalPower, true, { sin($0 * .pi / 2) }),
            (.equalPower, false, { cos($0 * .pi / 2) }),
            (.sCurve, true, { 0.5 - 0.5 * cos($0 * .pi) }),
            (.sCurve, false, { 0.5 + 0.5 * cos($0 * .pi) }),
        ]
        for (curve, rising, f) in cases {
            let b = FadeBezier.preset(curve, rising: rising)
            for i in 0...20 {
                let p = Double(i) / 20
                XCTAssertEqual(b.gain(at: p, rising: rising), f(p), accuracy: 0.03, "\(curve) \(rising) p=\(p)")
            }
        }
    }

    func testCustomCurveInMixer() {
        let m = CueMixer(sampleRate: 1000)
        let p = UnsafeMutablePointer<Float>.allocate(capacity: 1000)
        defer { p.deallocate() }
        p.initialize(repeating: 1, count: 1000)
        // 一気に上がってから平らになる形
        var spec = CueVoiceSpec(token: 1, owner: UUID(), tag: UUID(), left: UnsafePointer(p), right: UnsafePointer(p),
                                startFrame: 0, endFrame: 1000, fadeInFrames: 100, curve: .custom)
        spec.fadeInBezier = FadeBezier(0, 1, 0, 1).simd
        m.send(.play(spec))
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 100)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 100)
        defer { l.deallocate(); r.deallocate() }
        m.render(frames: 100, left: l, right: r)
        XCTAssertEqual(l[0], 0, accuracy: 1e-4)
        XCTAssertGreaterThan(l[20], 0.85, "直線（0.2）よりずっと早く上がる")
    }
}
