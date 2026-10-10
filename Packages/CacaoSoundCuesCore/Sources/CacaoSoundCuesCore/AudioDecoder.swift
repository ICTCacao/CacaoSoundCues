import AVFoundation

/// メモリに展開済みの音（左右別の Float32、出力のサンプルレートに変換済み）
public final class SampleBuffer: @unchecked Sendable {
    public let left: UnsafeMutablePointer<Float>
    public let right: UnsafeMutablePointer<Float>
    public let frames: Int
    public let sampleRate: Double
    /// 波形表示用（区間ごとの最大振幅）
    public let peaks: [Float]

    init(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Double) {
        self.left = left
        self.right = right
        self.frames = frames
        self.sampleRate = sampleRate
        let bins = min(4000, max(1, frames))
        var peaks = [Float](repeating: 0, count: bins)
        let per = max(1, frames / bins)
        for b in 0..<bins {
            let s = b * per
            let e = b == bins - 1 ? frames : min(frames, s + per)
            var m: Float = 0
            var k = s
            while k < e {
                m = max(m, abs(left[k]), abs(right[k]))
                k += 1
            }
            peaks[b] = m
        }
        self.peaks = peaks
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    public var duration: Double { Double(frames) / sampleRate }
    public var byteSize: Int { frames * 2 * MemoryLayout<Float>.size }
}

public enum AudioDecodeError: LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let s): return "読み込めない形式です: \(s)"
        }
    }
}

public enum AudioDecoder {
    /// wav / aiff / mp3 / m4a など AVAudioFile が読めるものを全部メモリに展開する
    public static func decode(url: URL, sampleRate: Double) throws -> SampleBuffer {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        let outChannels: AVAudioChannelCount = src.channelCount == 1 ? 1 : 2
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                            channels: outChannels, interleaved: false),
              let converter = AVAudioConverter(from: src, to: outFormat) else {
            throw AudioDecodeError.unsupported(url.lastPathComponent)
        }
        converter.downmix = src.channelCount > 2

        let ratio = sampleRate / src.sampleRate
        let chunk: AVAudioFrameCount = 32768
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: chunk),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(chunk) * ratio) + 1024) else {
            throw AudioDecodeError.unsupported(url.lastPathComponent)
        }

        var capacity = Int(Double(file.length) * ratio) + 4096
        var left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        var right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        var written = 0
        var eof = false

        func grow(to needed: Int) {
            let newCap = max(needed, capacity * 2)
            let nl = UnsafeMutablePointer<Float>.allocate(capacity: newCap)
            let nr = UnsafeMutablePointer<Float>.allocate(capacity: newCap)
            nl.update(from: left, count: written)
            nr.update(from: right, count: written)
            left.deallocate()
            right.deallocate()
            left = nl
            right = nr
            capacity = newCap
        }

        do {
            while true {
                outBuf.frameLength = 0
                var convError: NSError?
                let status = converter.convert(to: outBuf, error: &convError) { _, inStatus in
                    if eof {
                        inStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try file.read(into: inBuf)
                    } catch {
                        eof = true
                        inStatus.pointee = .endOfStream
                        return nil
                    }
                    if inBuf.frameLength == 0 {
                        eof = true
                        inStatus.pointee = .endOfStream
                        return nil
                    }
                    inStatus.pointee = .haveData
                    return inBuf
                }
                if status == .error { throw convError ?? AudioDecodeError.unsupported(url.lastPathComponent) }
                let n = Int(outBuf.frameLength)
                if n > 0, let ch = outBuf.floatChannelData {
                    if written + n > capacity { grow(to: written + n) }
                    (left + written).update(from: ch[0], count: n)
                    (right + written).update(from: ch[outChannels == 1 ? 0 : 1], count: n)
                    written += n
                }
                if status == .endOfStream || (n == 0 && eof) { break }
            }
        } catch {
            left.deallocate()
            right.deallocate()
            throw error
        }
        return SampleBuffer(left: left, right: right, frames: written, sampleRate: sampleRate)
    }

    /// 長さ（秒）だけを読む
    public static func duration(of url: URL) -> Double? {
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        return Double(f.length) / f.processingFormat.sampleRate
    }
}
