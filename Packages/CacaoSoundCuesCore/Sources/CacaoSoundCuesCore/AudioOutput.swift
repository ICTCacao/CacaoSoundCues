import AVFoundation
import AudioToolbox
import CoreAudio

/// AVAudioEngine に自前ミキサー（CueMixer）を1つだけつないで鳴らす。
/// ふだん（Simple 版）は Mac の出力（システムの設定）に左右 2ch で出す。
/// Pro 版は route() で機器と、出口（系統）ごとの左右のチャンネルを決める（多チャンネルの機器や、まとめた機器セット）
public final class AudioOutput {
    /// 出口ごとの、機器の左右のチャンネル（0 始まり）
    public struct BusChannels: Equatable, Sendable {
        public var left: Int
        public var right: Int
        public init(left: Int, right: Int) {
            self.left = left
            self.right = right
        }
    }

    /// 出力の機器と、出口ごとのチャンネル。nil ならシステムの出力に左右 2ch
    public struct Routing: Equatable, Sendable {
        public var device: AudioDeviceID
        public var buses: [BusChannels]
        public init(device: AudioDeviceID, buses: [BusChannels]) {
            self.device = device
            self.buses = buses
        }
    }

    public private(set) var mixer: CueMixer
    public private(set) var sampleRate: Double
    /// 実際に設定されたハードウェアのバッファサイズ（フレーム）
    public private(set) var bufferFrames: UInt32 = 0
    public private(set) var deviceName = ""
    /// 出力先が変わってエンジンを作り直したとき。サンプルレートが変わったら true（音を読み直す必要がある）
    public var onRestart: ((_ sampleRateChanged: Bool) -> Void)?

    private var engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var preferredBufferFrames: UInt32 = 128
    private var observer: NSObjectProtocol?
    public private(set) var routing: Routing?
    /// 出口ごとの作業用の音（音声スレッドでメモリを確保しないよう、先に用意しておく）
    private static let scratchFrames = 4096
    private var scratchL: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    private var scratchR: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    private var scratchCount = 0
    /// 出力の機器のチャンネル数（route したとき）
    public private(set) var deviceChannels = 2

    public init() {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = sr > 0 ? sr : 48000
        mixer = CueMixer(sampleRate: sampleRate)
        observe()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        freeScratch()
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    /// 出力の機器と出口を決め直す（Pro 版）。nil ならシステムの出力に戻す。
    /// 鳴っている音は止まる（ミキサーを作り直すため）。サンプルレートが変わったら onRestart(true) で音を読み直してもらう
    public func route(_ newRouting: Routing?) {
        guard newRouting != routing else { return }
        routing = newRouting
        engine.stop()
        if let source, source.engine === engine { engine.detach(source) }
        source = nil
        // 機器を変えるときは、エンジンを作り直す（前の機器の設定が残らないように）
        engine = AVAudioEngine()
        observe()
        let changed = applyDeviceAndRate()
        mixer = CueMixer(sampleRate: sampleRate, buses: max(1, routing?.buses.count ?? 1))
        do {
            try start(preferredBufferFrames: preferredBufferFrames)
            lastError = nil
        } catch {
            // 決めた機器で始められなければ、システムの出力に戻す（無音にしない）
            lastError = error.localizedDescription
            if routing != nil {
                routing = nil
                engine.stop()
                engine = AVAudioEngine()
                observe()
                source = nil
                applyDeviceAndRate()
                mixer = CueMixer(sampleRate: sampleRate)
                try? start(preferredBufferFrames: preferredBufferFrames)
                onRestart?(true)
                return
            }
        }
        onRestart?(changed)
    }

    /// 出力を始められなかったときの理由
    public private(set) var lastError: String?

    /// 機器を出力に設定し、サンプルレートを読み直す。変わったら true
    @discardableResult
    private func applyDeviceAndRate() -> Bool {
        if let routing, let au = engine.outputNode.audioUnit {
            var dev = routing.device
            let status = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { self.routing = nil }
        }
        // 機器を決めたときは、サンプルレートも機器から直接読む（AVAudioEngine が前の機器の値を返すことがある）
        let deviceRate = routing.map { Self.nominalSampleRate($0.device) } ?? 0
        let sr = deviceRate > 0 ? deviceRate : engine.outputNode.outputFormat(forBus: 0).sampleRate
        // 機器セットでは AVAudioEngine が 2ch と答えることがあるので、機器から直接読む
        deviceChannels = max(Int(engine.outputNode.outputFormat(forBus: 0).channelCount),
                             routing.map { Self.outputChannels($0.device) } ?? 0)
        let changed = sr > 0 && sr != sampleRate
        if sr > 0 { sampleRate = sr }
        return changed
    }

    private func allocScratch(_ count: Int) {
        freeScratch()
        let l = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: count)
        let r = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: count)
        for k in 0..<count {
            (l + k).initialize(to: .allocate(capacity: Self.scratchFrames))
            (r + k).initialize(to: .allocate(capacity: Self.scratchFrames))
        }
        scratchL = l
        scratchR = r
        scratchCount = count
    }

    private func freeScratch() {
        guard let l = scratchL, let r = scratchR else { return }
        for k in 0..<scratchCount {
            l[k].deallocate()
            r[k].deallocate()
        }
        l.deallocate()
        r.deallocate()
        scratchL = nil
        scratchR = nil
        scratchCount = 0
    }

    public var latencyMilliseconds: Double {
        Double(bufferFrames) / sampleRate * 1000
    }

    public func start(preferredBufferFrames: UInt32 = 128) throws {
        self.preferredBufferFrames = preferredBufferFrames
        attachSource()
        setDeviceBufferSize(preferredBufferFrames)
        engine.prepare()
        try engine.start()
    }

    private func attachSource() {
        // 今のエンジンにつないだものだけ外す（作り直した別のエンジンから外すと例外で落ちる）
        if let source, source.engine === engine { engine.detach(source) }
        source = nil
        if let routing {
            attachRoutedSource(routing)
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let m = mixer
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(ablPointer)
            guard let l = list[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = list.count > 1 ? (list[1].mData?.assumingMemoryBound(to: Float.self) ?? l) : l
            m.render(frames: Int(frameCount), left: l, right: r)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }

    /// 出口ごとに作った音を、機器のチャンネルへ割り当てて出す（多チャンネル。ミキサーを通さずに出力へ直接つなぐ）
    private func attachRoutedSource(_ routing: Routing) {
        let channels = max(2, deviceChannels)
        let busCount = max(1, routing.buses.count)
        if scratchCount != busCount { allocScratch(busCount) }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)),
              let sl = scratchL, let sr = scratchR else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
        let m = mixer
        let map = routing.buses
        let frameCap = Self.scratchFrames
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(ablPointer)
            let total = Int(frameCount)
            for b in list { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
            var done = 0
            // 作業用の長さを超えるときは分けて作る
            while done < total {
                let n = min(frameCap, total - done)
                m.render(frames: n, busLeft: sl, busRight: sr, buses: busCount)
                for k in 0..<busCount {
                    let ch = k < map.count ? map[k] : AudioOutput.BusChannels(left: 0, right: 1)
                    // 音声スレッドなので配列を作らない（メモリを確保しない）
                    if ch.left >= 0, ch.left < list.count, let dst = list[ch.left].mData?.assumingMemoryBound(to: Float.self) {
                        let d = dst + done, src = sl[k]
                        for f in 0..<n { d[f] += src[f] }
                    }
                    if ch.right >= 0, ch.right < list.count, let dst = list[ch.right].mData?.assumingMemoryBound(to: Float.self) {
                        let d = dst + done, src = sr[k]
                        for f in 0..<n { d[f] += src[f] }
                    }
                }
                done += n
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.outputNode, format: format)
        source = node
    }

    private func handleConfigurationChange() {
        engine.stop()
        // 決めた機器が無くなったら、システムの出力に戻す
        if let r = routing, !Self.deviceIsAlive(r.device) {
            routing = nil
            engine = AVAudioEngine()
            source = nil
            observe()
        }
        let before = sampleRate
        applyDeviceAndRate()
        let changed = sampleRate != before
        if changed || mixer.busCount != max(1, routing?.buses.count ?? 1) {
            mixer = CueMixer(sampleRate: sampleRate, buses: max(1, routing?.buses.count ?? 1))
        }
        try? start(preferredBufferFrames: preferredBufferFrames)
        onRestart?(changed)
    }

    /// 機器の出力のチャンネル数
    public static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// 音を出しているか（確かめる用）
    public var isRunning: Bool { engine.isRunning }

    public static func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var sr: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &sr) == noErr ? sr : 0
    }

    /// 出力へつないだ音のチャンネル数（確かめる用）
    public var connectedChannels: Int { Int(source?.outputFormat(forBus: 0).channelCount ?? 0) }

    private static func deviceIsAlive(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &alive) == noErr && alive != 0
    }

    private func setDeviceBufferSize(_ frames: UInt32) {
        guard let au = engine.outputNode.audioUnit else { return }
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &device, &size) == noErr else { return }

        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var wanted = frames
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wanted)
        var actual: UInt32 = 0
        var actualSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &actualSize, &actual) == noErr {
            bufferFrames = actual
        }

        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(device, &nameAddr, 0, nil, &nameSize, &name) == noErr, let name {
            deviceName = name.takeRetainedValue() as String
        }
    }
}
