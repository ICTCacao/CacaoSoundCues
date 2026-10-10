import AVFoundation
import AudioToolbox
import CoreAudio

/// AVAudioEngine に自前ミキサー（CueMixer）を1つだけつないで鳴らす
public final class AudioOutput {
    public private(set) var mixer: CueMixer
    public private(set) var sampleRate: Double
    /// 実際に設定されたハードウェアのバッファサイズ（フレーム）
    public private(set) var bufferFrames: UInt32 = 0
    public private(set) var deviceName = ""
    /// 出力先が変わってエンジンを作り直したとき。サンプルレートが変わったら true（音を読み直す必要がある）
    public var onRestart: ((_ sampleRateChanged: Bool) -> Void)?

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var preferredBufferFrames: UInt32 = 128
    private var observer: NSObjectProtocol?

    public init() {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = sr > 0 ? sr : 48000
        mixer = CueMixer(sampleRate: sampleRate)
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
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
        if let source { engine.detach(source) }
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

    private func handleConfigurationChange() {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let changed = sr > 0 && sr != sampleRate
        engine.stop()
        if changed {
            sampleRate = sr
            mixer = CueMixer(sampleRate: sr)
        }
        try? start(preferredBufferFrames: preferredBufferFrames)
        onRestart?(changed)
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
