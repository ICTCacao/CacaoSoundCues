import Foundation
import os

/// 1回の再生の指定。メインスレッドで作り、コマンドで音声スレッドへ渡す。
public struct CueVoiceSpec: @unchecked Sendable {
    public var token: UInt64
    /// 持ち主（キーの音なら KeyCue.id、リストなら CueSequence.id）
    public var owner: UUID
    /// 表示用の印（リストなら SequenceStep.id）
    public var tag: UUID
    public var left: UnsafePointer<Float>
    public var right: UnsafePointer<Float>
    public var startFrame: Int
    public var endFrame: Int
    public var loop: Bool
    /// loop のときの再生回数。0 は止めるまでくり返す
    public var loopCount: Int
    public var gain: Float
    public var fadeInFrames: Int
    public var fadeOutFrames: Int
    public var fadeOutAtEnd: Bool
    public var curve: FadeCurve
    /// curve が custom のときのフェードイン／フェードアウトの形（ベジエの制御点 x1,y1,x2,y2）
    public var fadeInBezier: SIMD4<Float>
    public var fadeOutBezier: SIMD4<Float>
    /// 音量ライン（曲の中で音量を変える）。空なら変えない
    public var envelope = VolumeEnvelope()
    /// 左右（-1〜1）。0 なら中央
    public var pan: Float = 0
    /// PANライン（値は -1〜1）。pan に足し合わせる。空なら変えない
    public var panEnvelope = VolumeEnvelope()
    /// 0 以外なら、この token の音の終わりを待ってから鳴らす（リストの次の曲）
    public var follow: UInt64
    /// follow のとき、先の音の終わりからの間隔（フレーム）。マイナスなら重ねる
    public var gapFrames: Int
    /// 重ねるとき（gapFrames < 0）、先の音を重なりの長さで自動フェードアウトさせる
    public var crossfade: Bool
    /// follow が 0 のとき、このフレーム数だけ待ってから鳴らす（Return を押してから n 秒）
    public var delayFrames: Int = 0

    public init(token: UInt64, owner: UUID, tag: UUID,
                left: UnsafePointer<Float>, right: UnsafePointer<Float>,
                startFrame: Int, endFrame: Int, loop: Bool = false, loopCount: Int = 0, gain: Float = 1,
                fadeInFrames: Int = 0, fadeOutFrames: Int = 0, fadeOutAtEnd: Bool = false,
                curve: FadeCurve = .equalPower, follow: UInt64 = 0, gapFrames: Int = 0, crossfade: Bool = false) {
        self.token = token
        self.owner = owner
        self.tag = tag
        self.left = left
        self.right = right
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.loop = loop
        self.loopCount = loopCount
        self.gain = gain
        self.fadeInFrames = fadeInFrames
        self.fadeOutFrames = fadeOutFrames
        self.fadeOutAtEnd = fadeOutAtEnd
        self.curve = curve
        self.fadeInBezier = FadeBezier.preset(.equalPower, rising: true).simd
        self.fadeOutBezier = FadeBezier.preset(.equalPower, rising: false).simd
        self.follow = follow
        self.gapFrames = gapFrames
        self.crossfade = crossfade
    }
}

public enum MixerCommand: @unchecked Sendable {
    /// 鳴らす（重ねる）
    case play(CueVoiceSpec)
    /// 同じ持ち主が鳴っていればフェードアウトで止め、鳴っていなければ鳴らす
    case toggle(CueVoiceSpec)
    /// 同じ持ち主の音を止めて頭から鳴らし直す
    case restart(CueVoiceSpec)
    /// 同じ持ち主が鳴っていなければ鳴らす
    case playIfIdle(CueVoiceSpec)
    /// 持ち主の音を止める（待機中の次の曲も取り消す）。fadeFrames < 0 なら各音のフェードアウト設定を使う
    case stopOwner(UUID, fadeFrames: Int)
    case stopToken(UInt64, fadeFrames: Int)
    case stopAll(fadeFrames: Int)
    case setMasterGain(Float)
    /// 鳴っている音の再生位置を移す（再生範囲の中に収める）
    case seek(UInt64, frame: Int)
    /// 待っている音（delayFrames）を、待たずにすぐ鳴らす
    case startNow(UInt64)
    /// 鳴っている音の音量を変える（持ち主か印が id の音すべて）。急に変わらないよう少しずつ近づける
    case setGain(UUID, Float)
    /// 鳴っている音の音量ラインを差し替える（持ち主か印が id の音すべて）
    case setEnvelope(UUID, VolumeEnvelope)
    /// 鳴っている音の左右を変える（持ち主か印が id の音すべて）
    case setPan(UUID, Float)
    /// 鳴っている音の PANライン を差し替える
    case setPanEnvelope(UUID, VolumeEnvelope)
}

public struct VoiceStatus: Sendable, Hashable {
    public var token: UInt64
    public var owner: UUID
    public var tag: UUID
    public var position: Int
    public var startFrame: Int
    public var endFrame: Int
    /// 前の曲の終わりを待っている
    public var armed: Bool
    /// 止めるためにフェードアウト中
    public var stopping: Bool
    /// 止めるまでくり返す（残り時間が決まらない）
    public var loop: Bool
    /// 鳴り終わるまでの残り（リピートの残り回数を含む）
    public var remainingFrames: Int
    /// 今のフェードの音量（0〜1）
    public var level: Float
    /// フェードイン／フェードアウトの最中
    public var fading: Bool
    /// フェードアウト（音量が下がっていく）
    public var fadingDown: Bool
    /// 今のフェードの、始まってからのフレーム数・全体の長さ・始まりと終わりの音量
    public var fadeElapsed: Int
    public var fadeLength: Int
    public var fadeFrom: Float
    public var fadeTo: Float
    /// 待っている音が鳴り始めるまでの残りフレーム（待っていなければ -1）
    public var startsIn: Int
    /// 音量ラインのいまの倍率（表示用）
    public var lineGain: Float
    /// いまの左右（PANライン込み、表示用）
    public var panNow: Float
}

private let silentSample: UnsafeMutablePointer<Float> = {
    let p = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    p.initialize(to: 0)
    return p
}()

struct Voice {
    var inUse = false
    var armed = false
    var spec: CueVoiceSpec
    var pos = 0
    var env: Float = 0
    var envFrom: Float = 0
    var envTo: Float = 0
    var envPos = 0
    var envLen = 0
    var stopping = false
    var endFading = false
    /// 次の曲が重なってくるとき、終わりのこの長さで自動フェードアウトする（クロスフェード）
    var crossfadeFrames = 0
    /// いまの音量（spec.gain へ少しずつ近づける。再生中に音量を変えたときのプツッを防ぐ）
    var gainNow: Float = 1
    /// 左右それぞれのいまの倍率（pan へ少しずつ近づける）
    var panLNow: Float = 1
    var panRNow: Float = 1
    /// いまの左右（PANライン込み）と、次に PANライン を計算するまでのフレーム数
    var panNow: Float = 0
    var panBlock = 0
    /// 音量ラインのいまの倍率と、次の区切りまでの1フレームあたりの変化（8 フレームごとに計算して、その間は直線でつなぐ）
    var lineGain: Float = 1
    var lineSlope: Float = 0
    var lineBlock = 0
    /// 残りのくり返し回数。-1 は止めるまで
    var repeatsLeft = 0
    /// armed のとき、先の音が消えた後に鳴り始めるまでの残りフレーム
    var countdown = Int.min
    /// このサイクルで書き始める位置（途中から鳴り始める音のため）
    var renderFrom = 0

    static let empty = Voice(spec: CueVoiceSpec(token: 0, owner: UUID(), tag: UUID(),
                                             left: UnsafePointer(silentSample), right: UnsafePointer(silentSample),
                                             startFrame: 0, endFrame: 0))
}

/// 自前のミキサー。render は音声スレッドから呼ばれ、メモリ確保もロック待ちもしない。
/// メインスレッドとは send()/snapshot() でやりとりする（音声スレッド側は trylock のみ）。
public final class CueMixer: @unchecked Sendable {
    public static let maxVoices = 32

    public let sampleRate: Double
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pending: [MixerCommand] = []
    private var published: [VoiceStatus] = []
    private let voices: UnsafeMutablePointer<Voice>
    private var masterTarget: Float = 1
    private var masterCurrent: Float = 1
    /// カット時のクリック防止（2ms）
    private let minFade: Int

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        pending.reserveCapacity(1024)
        published.reserveCapacity(Self.maxVoices)
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: .empty, count: Self.maxVoices)
        minFade = max(1, Int(sampleRate * 0.002))
    }

    deinit {
        voices.deinitialize(count: Self.maxVoices)
        voices.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: - メインスレッド側

    public func send(_ command: MixerCommand) {
        os_unfair_lock_lock(lock)
        pending.append(command)
        os_unfair_lock_unlock(lock)
    }

    public func snapshot() -> [VoiceStatus] {
        os_unfair_lock_lock(lock)
        // map で新しい配列にする（published のバッファを共有すると音声スレッド側でコピーが起きる）
        let copy = published.map { $0 }
        os_unfair_lock_unlock(lock)
        return copy
    }

    // MARK: - 音声スレッド側

    public func render(frames n: Int, left L: UnsafeMutablePointer<Float>, right R: UnsafeMutablePointer<Float>) {
        if os_unfair_lock_trylock(lock) {
            for i in 0..<pending.count { apply(pending[i]) }
            pending.removeAll(keepingCapacity: true)
            os_unfair_lock_unlock(lock)
        }

        L.update(repeating: 0, count: n)
        R.update(repeating: 0, count: n)

        activateArmed(frames: n)
        for i in 0..<Self.maxVoices where voices[i].inUse && !voices[i].armed {
            renderVoice(i, frames: n, L, R)
        }

        let step = (masterTarget - masterCurrent) / Float(n)
        for f in 0..<n {
            masterCurrent += step
            L[f] *= masterCurrent
            R[f] *= masterCurrent
        }
        masterCurrent = masterTarget

        if os_unfair_lock_trylock(lock) {
            publish()
            os_unfair_lock_unlock(lock)
        }
    }

    private func apply(_ command: MixerCommand) {
        switch command {
        case .play(let s):
            start(s)
        case .toggle(let s):
            var stopped = false
            for i in 0..<Self.maxVoices where isSounding(i, owner: s.owner) {
                beginStop(i, fade: -1)
                stopped = true
            }
            if !stopped { start(s) }
        case .restart(let s):
            for i in 0..<Self.maxVoices where isSounding(i, owner: s.owner) {
                beginStop(i, fade: minFade)
            }
            start(s)
        case .playIfIdle(let s):
            for i in 0..<Self.maxVoices where isSounding(i, owner: s.owner) { return }
            start(s)
        case .stopOwner(let owner, let fade):
            for i in 0..<Self.maxVoices where voices[i].inUse && voices[i].spec.owner == owner {
                if voices[i].armed { voices[i].inUse = false } else { beginStop(i, fade: fade) }
            }
        case .stopToken(let token, let fade):
            for i in 0..<Self.maxVoices where voices[i].inUse && voices[i].spec.token == token {
                if voices[i].armed { voices[i].inUse = false } else { beginStop(i, fade: fade) }
            }
        case .stopAll(let fade):
            for i in 0..<Self.maxVoices where voices[i].inUse {
                if voices[i].armed { voices[i].inUse = false } else { beginStop(i, fade: fade) }
            }
        case .setMasterGain(let g):
            masterTarget = g
        case .setPanEnvelope(let id, let envelope):
            for i in 0..<Self.maxVoices where voices[i].inUse && (voices[i].spec.owner == id || voices[i].spec.tag == id) {
                voices[i].spec.panEnvelope = envelope
                voices[i].panBlock = 0
            }
        case .setPan(let id, let pan):
            for i in 0..<Self.maxVoices where voices[i].inUse && (voices[i].spec.owner == id || voices[i].spec.tag == id) {
                voices[i].spec.pan = pan
            }
        case .setEnvelope(let id, let envelope):
            for i in 0..<Self.maxVoices where voices[i].inUse && (voices[i].spec.owner == id || voices[i].spec.tag == id) {
                voices[i].spec.envelope = envelope
                voices[i].lineBlock = 0
            }
        case .setGain(let id, let gain):
            for i in 0..<Self.maxVoices where voices[i].inUse && (voices[i].spec.owner == id || voices[i].spec.tag == id) {
                voices[i].spec.gain = gain
            }
        case .startNow(let token):
            for i in 0..<Self.maxVoices where voices[i].inUse && voices[i].armed && voices[i].spec.token == token {
                voices[i].countdown = 0
            }
        case .seek(let token, let frame):
            for i in 0..<Self.maxVoices where voices[i].inUse && !voices[i].armed && voices[i].spec.token == token {
                var v = voices[i]
                v.pos = min(max(frame, v.spec.startFrame), v.spec.endFrame - 1)
                v.lineGain = v.spec.envelope.gain(at: v.pos)
                v.lineBlock = 0
                v.endFading = false
                // 飛んだ瞬間のプツッを防ぐため、2ms で立ち上げ直す（止めている途中ならそのまま）
                if !v.stopping {
                    v.env = 0
                    setEnv(&v, to: 1, len: minFade)
                }
                voices[i] = v
            }
        }
    }

    private func isSounding(_ i: Int, owner: UUID) -> Bool {
        let v = voices[i]
        return v.inUse && !v.armed && !v.stopping && v.spec.owner == owner
    }

    private func start(_ s: CueVoiceSpec) {
        guard s.endFrame > s.startFrame else { return }
        guard let slot = (0..<Self.maxVoices).first(where: { !voices[$0].inUse }) else { return }
        var v = Voice.empty
        v.inUse = true
        v.spec = s
        v.pos = s.startFrame
        v.repeatsLeft = s.loop ? (s.loopCount > 0 ? s.loopCount - 1 : -1) : 0
        v.gainNow = s.gain
        v.panNow = min(max(s.pan + s.panEnvelope.value(at: s.startFrame), -1), 1)
        (v.panLNow, v.panRNow) = panGains(v.panNow)
        v.lineGain = s.envelope.gain(at: s.startFrame)
        if s.follow != 0 {
            v.armed = true
        } else if s.delayFrames > 0 {
            v.armed = true
            v.countdown = s.delayFrames
        } else {
            setEnv(&v, to: 1, len: max(minFade, s.fadeInFrames))
        }
        voices[slot] = v
    }

    private func beginStop(_ i: Int, fade: Int) {
        var v = voices[i]
        let len = max(minFade, fade < 0 ? v.spec.fadeOutFrames : fade)
        // すでに止めている途中なら、より短い方を採る（Esc 2度押しでカットするため）
        if v.stopping && v.envLen - v.envPos <= len { return }
        setEnv(&v, to: 0, len: len)
        v.stopping = true
        voices[i] = v
    }

    private func setEnv(_ v: inout Voice, to target: Float, len: Int) {
        v.envFrom = v.env
        v.envTo = target
        v.envPos = 0
        v.envLen = len
    }

    /// 前の曲の残りフレームから、次の曲を鳴らし始める位置を決める（サンプル単位で正確）
    private func activateArmed(frames n: Int) {
        for i in 0..<Self.maxVoices where voices[i].inUse && voices[i].armed {
            let follow = voices[i].spec.follow
            let gap = voices[i].spec.gapFrames
            var startIn: Int
            // 先の音もまだ待っている（Return から n 秒待ちの曲）なら、それが鳴り始めるまで待つ
            if follow != 0, (0..<Self.maxVoices).contains(where: {
                voices[$0].inUse && voices[$0].armed && voices[$0].spec.token == follow
            }) {
                continue
            }
            if let j = (0..<Self.maxVoices).first(where: {
                voices[$0].inUse && !voices[$0].armed && voices[$0].spec.token == follow
            }) {
                // クロスフェード: 先の曲に「終わりで自動フェードアウト」が無ければ、重なりの長さで消えていくようにする
                if voices[i].spec.crossfade && gap < 0 && !voices[j].spec.fadeOutAtEnd {
                    voices[j].crossfadeFrames = -gap
                }
                let leader = voices[j]
                if leader.stopping || leader.repeatsLeft < 0 {
                    // ループ中は終わらないので待つ。止めている途中なら消えてから数える
                    voices[i].countdown = Int.min
                    continue
                }
                startIn = remainingFrames(leader) + gap
            } else {
                startIn = voices[i].countdown == Int.min ? max(0, gap) : voices[i].countdown
            }
            if startIn < n {
                var v = voices[i]
                v.armed = false
                v.renderFrom = max(0, startIn)
                setEnv(&v, to: 1, len: max(minFade, v.spec.fadeInFrames))
                voices[i] = v
            } else {
                voices[i].countdown = startIn - n
            }
        }
    }

    private func renderVoice(_ i: Int, frames n: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        var v = voices[i]
        let srcL = v.spec.left
        let srcR = v.spec.right
        let gainTarget = v.spec.gain
        // PANラインが無ければ、このサイクルのあいだに pan へ滑らかに近づける。あれば 8 フレームごとに計算する
        let hasPanLine = !v.spec.panEnvelope.isEmpty
        let (panLTarget, panRTarget) = panGains(v.spec.pan)
        let panFrames = Float(max(1, n - v.renderFrom))
        var panLStep = hasPanLine ? 0 : (panLTarget - v.panLNow) / panFrames
        var panRStep = hasPanLine ? 0 : (panRTarget - v.panRNow) / panFrames
        if !hasPanLine { v.panNow = v.spec.pan }
        // 音量が変わったら、このサイクルのあいだに滑らかに近づける
        let gainStep = (gainTarget - v.gainNow) / Float(max(1, n - v.renderFrom))
        let curve = v.spec.curve
        let bIn = v.spec.fadeInBezier
        let bOut = v.spec.fadeOutBezier
        var f = v.renderFrom
        v.renderFrom = 0
        while f < n {
            if v.pos >= v.spec.endFrame {
                if v.repeatsLeft != 0 {
                    v.pos = v.spec.startFrame
                    v.lineGain = v.spec.envelope.gain(at: v.pos)
                    v.lineBlock = 0
                    if v.repeatsLeft > 0 { v.repeatsLeft -= 1 }
                } else {
                    v.inUse = false
                    break
                }
            }
            // 自動フェードアウトはくり返しの最後の回だけ（自分の設定が優先、無ければクロスフェード）
            let endFade = v.spec.fadeOutAtEnd ? v.spec.fadeOutFrames : v.crossfadeFrames
            if endFade > 0 && v.repeatsLeft == 0 && !v.stopping && !v.endFading {
                let remain = v.spec.endFrame - v.pos
                if remain <= endFade {
                    setEnv(&v, to: 0, len: remain)
                    v.endFading = true
                }
            }
            var g = v.envTo
            if v.envPos < v.envLen {
                let p = Float(v.envPos) / Float(v.envLen)
                let rising = v.envTo > v.envFrom
                let s = curve == .custom
                    ? (rising ? bezierGain(bIn, rising: true, at: p) : 1 - bezierGain(bOut, rising: false, at: p))
                    : shape(p, rising: rising, curve)
                g = v.envFrom + (v.envTo - v.envFrom) * s
                v.envPos += 1
            } else if v.stopping {
                v.inUse = false
                break
            }
            v.env = g
            v.gainNow += gainStep
            if !v.spec.envelope.isEmpty {
                if v.lineBlock == 0 {
                    let target = v.spec.envelope.gain(at: v.pos + 8)
                    v.lineSlope = (target - v.lineGain) / 8
                    v.lineBlock = 8
                }
                v.lineGain += v.lineSlope
                v.lineBlock -= 1
            }
            let a = g * v.gainNow * v.lineGain
            if hasPanLine {
                if v.panBlock == 0 {
                    let p = min(max(v.spec.pan + v.spec.panEnvelope.value(at: v.pos + 8), -1), 1)
                    let (tl, tr) = panGains(p)
                    panLStep = (tl - v.panLNow) / 8
                    panRStep = (tr - v.panRNow) / 8
                    v.panNow = p
                    v.panBlock = 8
                }
                v.panBlock -= 1
            }
            v.panLNow += panLStep
            v.panRNow += panRStep
            L[f] += srcL[v.pos] * a * v.panLNow
            R[f] += srcR[v.pos] * a * v.panRNow
            v.pos += 1
            f += 1
        }
        v.gainNow = gainTarget
        if !hasPanLine {
            v.panLNow = panLTarget
            v.panRNow = panRTarget
        }
        voices[i] = v
    }

    /// 左右の釣り合い（バランス）。中央は左右とも 1、片側に寄せると反対側が下がる（パワーが一定の曲線）
    @inline(__always)
    private func panGains(_ pan: Float) -> (Float, Float) {
        let p = min(max(pan, -1), 1)
        let l: Float = p <= 0 ? 1 : cosf(p * .pi / 2)
        let r: Float = p >= 0 ? 1 : cosf(-p * .pi / 2)
        return (l, r)
    }

    private func remainingFrames(_ v: Voice) -> Int {
        (v.spec.endFrame - v.pos) + max(0, v.repeatsLeft) * (v.spec.endFrame - v.spec.startFrame)
    }

    @inline(__always)
    private func shape(_ p: Float, rising: Bool, _ curve: FadeCurve) -> Float {
        switch curve {
        case .linear: return p
        case .equalPower: return rising ? sinf(p * .pi / 2) : 1 - cosf(p * .pi / 2)
        case .sCurve: return 0.5 - 0.5 * cosf(p * .pi)
        case .custom: return p
        }
    }

    private func publish() {
        published.removeAll(keepingCapacity: true)
        for i in 0..<Self.maxVoices where voices[i].inUse {
            let v = voices[i]
            published.append(VoiceStatus(token: v.spec.token, owner: v.spec.owner, tag: v.spec.tag,
                                         position: v.pos, startFrame: v.spec.startFrame, endFrame: v.spec.endFrame,
                                         armed: v.armed, stopping: v.stopping, loop: v.repeatsLeft < 0,
                                         remainingFrames: remainingFrames(v),
                                         level: v.env, fading: v.envPos < v.envLen, fadingDown: v.envTo < v.envFrom,
                                         fadeElapsed: v.envPos, fadeLength: v.envLen, fadeFrom: v.envFrom, fadeTo: v.envTo,
                                         startsIn: v.armed && v.countdown != Int.min ? v.countdown : -1,
                                         lineGain: v.lineGain, panNow: v.panNow))
        }
    }
}
