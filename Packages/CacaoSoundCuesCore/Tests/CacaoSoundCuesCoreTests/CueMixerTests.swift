import XCTest
@testable import CacaoSoundCuesCore

/// サンプルレート 1000 で計算しやすくしてミキサーを検証する（カット時の 2ms = 2 フレーム）
final class CueMixerTests: XCTestCase {
    private var allocations: [UnsafeMutablePointer<Float>] = []

    override func tearDown() {
        allocations.forEach { $0.deallocate() }
        allocations = []
    }

    private func buffer(_ values: [Float]) -> UnsafePointer<Float> {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: values.count)
        p.initialize(from: values, count: values.count)
        allocations.append(p)
        return UnsafePointer(p)
    }

    private func spec(_ token: UInt64, _ buf: UnsafePointer<Float>, start: Int, end: Int,
                      owner: UUID = UUID(), loop: Bool = false, loopCount: Int = 0, fadeIn: Int = 0, fadeOut: Int = 0,
                      fadeOutAtEnd: Bool = false, curve: FadeCurve = .linear,
                      follow: UInt64 = 0, gap: Int = 0) -> CueVoiceSpec {
        CueVoiceSpec(token: token, owner: owner, tag: owner, left: buf, right: buf, startFrame: start, endFrame: end,
                  loop: loop, loopCount: loopCount, fadeInFrames: fadeIn, fadeOutFrames: fadeOut, fadeOutAtEnd: fadeOutAtEnd,
                  curve: curve, follow: follow, gapFrames: gap)
    }

    /// chunk フレームずつ total フレーム分レンダリングして左チャンネルを返す
    private func render(_ m: CueMixer, total: Int, chunk: Int? = nil) -> [Float] {
        let c = chunk ?? total
        var out: [Float] = []
        let l = UnsafeMutablePointer<Float>.allocate(capacity: c)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: c)
        defer { l.deallocate(); r.deallocate() }
        var done = 0
        while done < total {
            let n = min(c, total - done)
            m.render(frames: n, left: l, right: r)
            out.append(contentsOf: UnsafeBufferPointer(start: l, count: n))
            done += n
        }
        return out
    }

    /// 出口（Pro 版の系統）ごとに書き分ける。出口の数を超えた出口の音はメインへ。
    /// 前の曲の終わりを待つ次の曲は、出口が違ってもぴったり続く
    func testBuses() {
        let m = CueMixer(sampleRate: 1000, buses: 2)
        let ones = buffer([Float](repeating: 1, count: 100))
        var a = spec(1, ones, start: 0, end: 10)
        a.bus = 1
        var b = spec(2, ones, start: 0, end: 10, follow: 1)
        b.bus = 0
        var c = spec(3, ones, start: 0, end: 5)
        c.bus = 7
        m.send(.play(a))
        m.send(.play(b))
        m.send(.play(c))
        let n = 30
        let ls = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: n) }
        let rs = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: n) }
        defer { (ls + rs).forEach { $0.deallocate() } }
        let pl = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        let pr = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer { pl.deallocate(); pr.deallocate() }
        for k in 0..<2 { pl[k] = ls[k]; pr[k] = rs[k] }
        m.render(frames: n, busLeft: pl, busRight: pr, buses: 2)
        // 鳴り始めはプツッと鳴らないよう 2 フレームでフェードするので、少しあとを見る
        // 出口 1: a だけ（0〜9）
        XCTAssertEqual(ls[1][5], 1, accuracy: 1e-6)
        XCTAssertEqual(ls[1][9], 1, accuracy: 1e-6)
        XCTAssertEqual(ls[1][10], 0, accuracy: 1e-6)
        // 出口 0: c（出口 7 はメインへ。0〜4）と、a の終わりを待った b（10〜19）
        XCTAssertEqual(ls[0][3], 1, accuracy: 1e-6)
        XCTAssertEqual(ls[0][5], 0, accuracy: 1e-6)
        XCTAssertEqual(ls[0][15], 1, accuracy: 1e-6)
        XCTAssertEqual(ls[0][19], 1, accuracy: 1e-6)
        XCTAssertEqual(ls[0][20], 0, accuracy: 1e-6)
    }

    func testFadeInLinear() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        m.send(.play(spec(1, ones, start: 0, end: 1000, fadeIn: 100)))
        let out = render(m, total: 200)
        XCTAssertEqual(out[0], 0, accuracy: 1e-6)
        XCTAssertEqual(out[50], 0.5, accuracy: 1e-6)
        XCTAssertEqual(out[150], 1, accuracy: 1e-6)
    }

    func testInOutPoints() {
        let m = CueMixer(sampleRate: 1000)
        let ramp = buffer((0..<100).map(Float.init))
        m.send(.play(spec(1, ramp, start: 10, end: 20)))
        let out = render(m, total: 30)
        XCTAssertEqual(out[5], 15, accuracy: 1e-6)
        XCTAssertEqual(out[9], 19, accuracy: 1e-6)
        XCTAssertEqual(out[10], 0, accuracy: 1e-6)
        XCTAssertTrue(m.snapshot().isEmpty)
    }

    func testLoop() {
        let m = CueMixer(sampleRate: 1000)
        let ramp = buffer((0..<100).map(Float.init))
        m.send(.play(spec(1, ramp, start: 0, end: 10, loop: true)))
        let out = render(m, total: 25, chunk: 8)
        XCTAssertEqual(out[12], 2, accuracy: 1e-6)
        XCTAssertEqual(out[24], 4, accuracy: 1e-6)
        XCTAssertEqual(m.snapshot().count, 1)
    }

    func testToggleStopsWithFadeOut() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        let owner = UUID()
        m.send(.toggle(spec(1, ones, start: 0, end: 1000, owner: owner, fadeOut: 10)))
        _ = render(m, total: 20)
        m.send(.toggle(spec(2, ones, start: 0, end: 1000, owner: owner, fadeOut: 10)))
        let out = render(m, total: 20)
        XCTAssertEqual(out[0], 1, accuracy: 1e-6)
        XCTAssertEqual(out[5], 0.5, accuracy: 1e-6)
        XCTAssertEqual(out[15], 0, accuracy: 1e-6)
        XCTAssertTrue(m.snapshot().isEmpty, "2回目の toggle は新しく鳴らさず止めるだけ")
    }

    func testFadeOutAtEnd() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        m.send(.play(spec(1, ones, start: 0, end: 100, fadeOut: 20, fadeOutAtEnd: true)))
        let out = render(m, total: 100)
        XCTAssertEqual(out[79], 1, accuracy: 1e-6)
        XCTAssertEqual(out[90], 0.5, accuracy: 1e-6)
    }

    func testFollowOverlapIsSampleAccurate() {
        let m = CueMixer(sampleRate: 1000)
        let zeros = buffer([Float](repeating: 0, count: 100))
        let ones = buffer([Float](repeating: 1, count: 100))
        m.send(.play(spec(1, zeros, start: 0, end: 20)))
        m.send(.play(spec(2, ones, start: 0, end: 100, follow: 1, gap: -5)))
        let out = render(m, total: 40)
        XCTAssertEqual(out[14], 0, accuracy: 1e-6)
        XCTAssertEqual(out[15], 0, accuracy: 1e-6)  // カット時の 2ms ランプの頭
        XCTAssertEqual(out[17], 1, accuracy: 1e-6)
    }

    func testFollowGapAcrossBuffers() {
        let m = CueMixer(sampleRate: 1000)
        let zeros = buffer([Float](repeating: 0, count: 100))
        let ones = buffer([Float](repeating: 1, count: 100))
        m.send(.play(spec(1, zeros, start: 0, end: 20)))
        m.send(.play(spec(2, ones, start: 0, end: 100, follow: 1, gap: 10)))
        let out = render(m, total: 48, chunk: 8)
        XCTAssertEqual(out[29], 0, accuracy: 1e-6)
        XCTAssertEqual(out[30], 0, accuracy: 1e-6)
        XCTAssertEqual(out[32], 1, accuracy: 1e-6)
    }

    func testStopOwnerCancelsArmed() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 100))
        let owner = UUID()
        m.send(.play(spec(1, ones, start: 0, end: 50, owner: owner)))
        m.send(.play(spec(2, ones, start: 0, end: 50, owner: owner, follow: 1)))
        _ = render(m, total: 10)
        m.send(.stopOwner(owner, fadeFrames: 4))
        _ = render(m, total: 100)
        XCTAssertTrue(m.snapshot().isEmpty)
    }

    func testEscapeTwiceCutsFadingVoice() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        m.send(.play(spec(1, ones, start: 0, end: 1000)))
        _ = render(m, total: 10)
        m.send(.stopAll(fadeFrames: 500))
        _ = render(m, total: 10)
        m.send(.stopAll(fadeFrames: 0))
        _ = render(m, total: 10)
        XCTAssertTrue(m.snapshot().isEmpty)
    }

    /// スペースで曲を途中で終えたとき: フェードアウトが終わってから次の曲が（間をあけて）鳴る
    func testFollowerStartsAfterLeaderStoppedEarly() {
        let m = CueMixer(sampleRate: 1000)
        let zeros = buffer([Float](repeating: 0, count: 1000))
        let ones = buffer([Float](repeating: 1, count: 1000))
        m.send(.play(spec(1, zeros, start: 0, end: 1000, fadeOut: 10)))
        m.send(.play(spec(2, ones, start: 0, end: 1000, follow: 1, gap: 5)))
        _ = render(m, total: 20, chunk: 4)
        m.send(.stopToken(1, fadeFrames: -1))
        let out = render(m, total: 40, chunk: 4)
        XCTAssertEqual(out[10], 0, accuracy: 1e-6, "フェードアウト中は鳴らない")
        XCTAssertEqual(out.last!, 1, accuracy: 1e-6, "その後、次の曲が鳴る")
        XCTAssertEqual(m.snapshot().count, 1)
    }

    /// 再生中に位置を移すと、その位置から鳴る（範囲の外は範囲の中に収める）
    func testSeek() {
        let m = CueMixer(sampleRate: 1000)
        let ramp = buffer((0..<1000).map(Float.init))
        m.send(.play(spec(1, ramp, start: 100, end: 900)))
        _ = render(m, total: 10)
        m.send(.seek(1, frame: 500))
        let out = render(m, total: 10)
        XCTAssertEqual(out[5], 505, accuracy: 1e-3)
        m.send(.seek(1, frame: 0))
        XCTAssertEqual(render(m, total: 10)[5], 105, accuracy: 1e-3)
    }

    /// 回数を指定したリピートは、その回数だけ鳴って止まる。次の曲もその後につながる
    func testLoopCount() {
        let m = CueMixer(sampleRate: 1000)
        let ramp = buffer((0..<100).map(Float.init))
        let ones = buffer([Float](repeating: 1, count: 100))
        m.send(.play(spec(1, ramp, start: 0, end: 10, loop: true, loopCount: 3)))
        m.send(.play(spec(2, ones, start: 0, end: 100, follow: 1)))
        let out = render(m, total: 40, chunk: 8)
        XCTAssertEqual(out[25], 5, accuracy: 1e-6, "3回目")
        XCTAssertEqual(out[29], 9, accuracy: 1e-6)
        XCTAssertEqual(out[35], 1, accuracy: 1e-6, "3回鳴った後に次の曲")
    }

    /// 重ねるとクロスフェード: 先の曲は重なりの長さで消え、次の曲は重なりの頭から鳴る
    func testCrossfade() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 100))
        let zeros = buffer([Float](repeating: 0, count: 100))
        m.send(.play(spec(1, ones, start: 0, end: 40, curve: .linear)))
        var next = spec(2, zeros, start: 0, end: 100, follow: 1, gap: -20)
        next.crossfade = true
        m.send(.play(next))
        let out = render(m, total: 50, chunk: 8)
        XCTAssertEqual(out[19], 1, accuracy: 1e-6, "重なる前は先の曲がそのまま")
        XCTAssertEqual(out[30], 0.5, accuracy: 1e-6, "重なりの真ん中で半分")
        XCTAssertEqual(out[39], 0.05, accuracy: 1e-6)
    }

    /// n 秒待ってから鳴る。待っている間に次の曲を「後に続く」で待たせても、先に鳴り出さない。startNow で待たずに鳴る
    func testDelayedStart() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 100))
        let zeros = buffer([Float](repeating: 0, count: 100))
        var first = spec(1, ones, start: 0, end: 20)
        first.delayFrames = 30
        m.send(.play(first))
        m.send(.play(spec(2, zeros, start: 0, end: 50, follow: 1)))
        let out = render(m, total: 64, chunk: 8)
        XCTAssertEqual(out[29], 0, accuracy: 1e-6, "30 フレームは鳴らない")
        XCTAssertEqual(out[35], 1, accuracy: 1e-6)
        XCTAssertEqual(out[52], 0, accuracy: 1e-6, "次の曲は先の曲の後")

        let m2 = CueMixer(sampleRate: 1000)
        var late = spec(3, ones, start: 0, end: 100)
        late.delayFrames = 10_000
        m2.send(.play(late))
        _ = render(m2, total: 8)
        m2.send(.startNow(3))
        XCTAssertEqual(render(m2, total: 8)[5], 1, accuracy: 1e-6)
    }

    /// 鳴っている途中で音量を変えると、次のサイクルから新しい音量になる（途中は滑らかに）
    func testLiveGainChange() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        let owner = UUID()
        m.send(.play(spec(1, ones, start: 0, end: 1000, owner: owner)))
        XCTAssertEqual(render(m, total: 16)[10], 1, accuracy: 1e-6)
        m.send(.setGain(owner, 0.5))
        let ramp = render(m, total: 16)
        XCTAssertLessThan(ramp[15], 1)
        XCTAssertEqual(ramp[15], 0.5, accuracy: 0.05, "サイクルの終わりには新しい音量")
        XCTAssertEqual(render(m, total: 16)[8], 0.5, accuracy: 1e-6)
    }

    /// 音量ライン: 0 フレームで 0dB、100 フレームで -20dB（直線）なら、50 で約 -10dB、100 以降は 0.1 倍
    func testVolumeLine() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        var s = spec(1, ones, start: 0, end: 1000)
        s.envelope = VolumeEnvelope(points: [
            VolumePoint(time: 0, db: 0, shape: FadeBezier.preset(.linear, rising: true)),
            VolumePoint(time: 0.1, db: -20),
        ], sampleRate: 1000)
        m.send(.play(s))
        let out = render(m, total: 200, chunk: 16)
        XCTAssertEqual(out[50], powf(10, -10.0 / 20), accuracy: 0.02)
        XCTAssertEqual(out[150], 0.1, accuracy: 1e-4)
    }

    func testVolumeLineDBMatchesEnvelope() {
        let points = [VolumePoint(time: 1, db: -6), VolumePoint(time: 3, db: -18)]
        let env = VolumeEnvelope(points: points, sampleRate: 1000)
        for t in [0.0, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0] {
            let db = volumeLineDB(points, at: t)
            XCTAssertEqual(Double(env.gain(at: Int(t * 1000))), pow(10, db / 20), accuracy: 0.01, "t=\(t)")
        }
    }

    /// 左右: 右いっぱいにすると左は鳴らず、右はそのまま
    func testPan() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        var s = spec(1, ones, start: 0, end: 1000)
        s.pan = 1
        m.send(.play(s))
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        defer { l.deallocate(); r.deallocate() }
        m.render(frames: 16, left: l, right: r)
        XCTAssertEqual(l[10], 0, accuracy: 1e-4)
        XCTAssertEqual(r[10], 1, accuracy: 1e-4)
    }

    /// 記録した細かい点は、直線に乗る点が消えて、曲がり角だけ残る
    func testSimplifyVolumePoints() {
        let linear = FadeBezier.preset(.linear, rising: true)
        var pts: [VolumePoint] = []
        for i in 0...20 { pts.append(VolumePoint(time: Double(i) * 0.1, db: -Double(i), shape: linear)) }   // 0〜2秒で 0→-20
        for i in 1...20 { pts.append(VolumePoint(time: 2 + Double(i) * 0.1, db: -20, shape: linear)) }      // 2〜4秒は -20 のまま
        let out = simplifyVolumePoints(pts)
        XCTAssertEqual(out.map(\.time), [0, 2, 4], "始め・曲がり角・終わりだけ残る")
        let many = (0..<200).map { VolumePoint(time: Double($0) * 0.1, db: $0 % 2 == 0 ? 0 : -10, shape: linear) }
        XCTAssertLessThanOrEqual(simplifyVolumePoints(many).count, 64)
    }

    /// PANライン: 右いっぱい（1）の線なら、左は鳴らず右はそのまま
    func testPanLine() {
        let m = CueMixer(sampleRate: 1000)
        let ones = buffer([Float](repeating: 1, count: 1000))
        var s = spec(1, ones, start: 0, end: 1000)
        s.panEnvelope = VolumeEnvelope(points: [VolumePoint(time: 0, db: 1)], sampleRate: 1000)
        m.send(.play(s))
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        defer { l.deallocate(); r.deallocate() }
        m.render(frames: 64, left: l, right: r)
        XCTAssertEqual(l[40], 0, accuracy: 1e-3)
        XCTAssertEqual(r[40], 1, accuracy: 1e-3)
        XCTAssertEqual(m.snapshot().first?.panNow ?? 0, 1, accuracy: 1e-3)
    }
}
