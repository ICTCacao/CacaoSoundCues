import Foundation

/// 音量ラインの点（音声スレッド用）。frame は音ファイルの頭からのフレーム、gainDB はその時点の音量
public struct EnvPoint: Sendable {
    public var frame: Int = 0
    public var gainDB: Float = 0
    /// 次の点までの形（ベジエの制御点 x1,y1,x2,y2）
    public var shape: SIMD4<Float> = SIMD4(0.42, 0, 0.58, 1)
    public init() {}
}

/// 音量ライン（音声スレッド用）。メモリ確保をしないよう、点は決まった数（64）までを値の中に持つ
public struct VolumeEnvelope: Sendable {
    public static let capacity = 64
    public private(set) var count = 0
    private var storage: (EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint, EnvPoint) = (EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint(), EnvPoint())

    public init() {}

    /// 点（時間の順）から作る。sampleRate で秒をフレームにする
    public init(points: [VolumePoint], sampleRate: Double) {
        for p in points.sorted(by: { $0.time < $1.time }).prefix(Self.capacity) {
            var e = EnvPoint()
            e.frame = Int(p.time * sampleRate)
            e.gainDB = Float(p.db)
            e.shape = (p.shape ?? VolumePoint.defaultShape).simd
            append(e)
        }
    }

    public var isEmpty: Bool { count == 0 }

    public subscript(i: Int) -> EnvPoint {
        withUnsafeBytes(of: storage) { $0.load(fromByteOffset: i * MemoryLayout<EnvPoint>.stride, as: EnvPoint.self) }
    }

    private mutating func append(_ p: EnvPoint) {
        guard count < Self.capacity else { return }
        let offset = count * MemoryLayout<EnvPoint>.stride
        withUnsafeMutableBytes(of: &storage) { $0.storeBytes(of: p, toByteOffset: offset, as: EnvPoint.self) }
        count += 1
    }

    /// あるフレームでの線の値（音量ラインなら dB、PANラインなら -1〜1）。点が無ければ 0
    @inline(__always)
    public func value(at frame: Int) -> Float {
        guard count > 0 else { return 0 }
        let first = self[0]
        if frame <= first.frame { return first.gainDB }
        var k = 0
        while k < count - 1 {
            let a = self[k], b = self[k + 1]
            if frame < b.frame {
                let p = Float(frame - a.frame) / Float(max(1, b.frame - a.frame))
                let s = bezierGain(a.shape, rising: true, at: p)
                return a.gainDB + (b.gainDB - a.gainDB) * s
            }
            k += 1
        }
        return self[count - 1].gainDB
    }

    /// あるフレームでの音量（倍率）。点が無ければ 1
    @inline(__always)
    public func gain(at frame: Int) -> Float {
        guard count > 0 else { return 1 }
        return dbToGain(value(at: frame))
    }

    @inline(__always)
    private func dbToGain(_ db: Float) -> Float { powf(10, db / 20) }
}
