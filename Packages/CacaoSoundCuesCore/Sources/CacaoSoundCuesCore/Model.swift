import Foundation

/// フェードのカーブ
public enum FadeCurve: String, Codable, CaseIterable, Sendable {
    case linear       // 直線
    case equalPower   // 等パワー（自然に聞こえる）
    case sCurve       // S字
    case custom       // ベジエ曲線で自由に（波形の上で制御点をドラッグ）

    public var label: String {
        switch self {
        case .linear: return "直線"
        case .equalPower: return "等パワー"
        case .sCurve: return "S字"
        case .custom: return "カスタム"
        }
    }
}

/// 再生中にもう一度キーを押したときの動作
public enum RetriggerMode: String, Codable, CaseIterable, Sendable {
    case fadeOut   // フェードアウトして止める（フェード 0 秒ならカットアウト）
    case restart   // 頭から鳴らし直す
    case layer     // 重ねて鳴らす
    case ignore    // 何もしない

    public var label: String {
        switch self {
        case .fadeOut: return "止める（フェードアウト）"
        case .restart: return "頭から鳴らし直す"
        case .layer: return "重ねて鳴らす"
        case .ignore: return "何もしない"
        }
    }
}

/// 音の鳴らし方。キーの音とリストの曲で共通。
public struct PlaySettings: Codable, Hashable, Sendable {
    public var soundID: UUID
    /// 再生開始位置（秒）
    public var inPoint: Double = 0
    /// 再生終了位置（秒）。nil なら最後まで
    public var outPoint: Double? = nil
    /// フェードイン（秒）。0 ならカットイン
    public var fadeIn: Double = 0
    /// 止めるときのフェードアウト（秒）。0 ならカットアウト（音を追加したときは 0）
    public var fadeOut: Double = 0
    /// 終了位置に向けて自動でフェードアウトする
    public var fadeOutAtEnd: Bool = false
    /// in〜out をリピートする
    public var loop: Bool = false
    /// リピートするときの再生回数（2 なら2回鳴る）。0 は止めるまでくり返す
    public var loopCount: Int = 0
    public var volumeDB: Double = 0
    public var curve: FadeCurve = .equalPower
    /// curve が custom のときのフェードイン・フェードアウトの形
    public var fadeInBezier: FadeBezier? = nil
    public var fadeOutBezier: FadeBezier? = nil

    public init(soundID: UUID) {
        self.soundID = soundID
    }

    private enum CodingKeys: String, CodingKey {
        case soundID, inPoint, outPoint, fadeIn, fadeOut, fadeOutAtEnd, loop, loopCount, volumeDB, curve
        case fadeInBezier, fadeOutBezier
    }

    /// 項目が足りない古いキューシートも開けるように、無い項目は既定値にする
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundID = try c.decode(UUID.self, forKey: .soundID)
        inPoint = try c.decodeIfPresent(Double.self, forKey: .inPoint) ?? 0
        outPoint = try c.decodeIfPresent(Double.self, forKey: .outPoint)
        fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 2
        fadeOutAtEnd = try c.decodeIfPresent(Bool.self, forKey: .fadeOutAtEnd) ?? false
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        loopCount = try c.decodeIfPresent(Int.self, forKey: .loopCount) ?? 0
        volumeDB = try c.decodeIfPresent(Double.self, forKey: .volumeDB) ?? 0
        curve = try c.decodeIfPresent(FadeCurve.self, forKey: .curve) ?? .equalPower
        fadeInBezier = try c.decodeIfPresent(FadeBezier.self, forKey: .fadeInBezier)
        fadeOutBezier = try c.decodeIfPresent(FadeBezier.self, forKey: .fadeOutBezier)
    }

    /// 実際に使うフェードの形（custom 以外は決まった形のベジエ）
    public func bezier(rising: Bool) -> FadeBezier {
        if curve == .custom, let b = rising ? fadeInBezier : fadeOutBezier { return b }
        return FadeBezier.preset(curve == .custom ? .equalPower : curve, rising: rising)
    }

    /// 何回鳴るか。nil は止めるまでくり返す
    public var plays: Int? {
        guard loop else { return 1 }
        return loopCount > 0 ? loopCount : nil
    }
}

/// キューシートに取り込んだ音ファイル（実体は .ccsc パッケージの Audio/ にコピーする）
public struct SoundRef: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var fileName: String
    public var displayName: String
    public var duration: Double

    public init(id: UUID = UUID(), fileName: String, displayName: String, duration: Double) {
        self.id = id
        self.fileName = fileName
        self.displayName = displayName
        self.duration = duration
    }
}

/// キーに割り当てた音
public struct KeyCue: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// ハードウェアのキーコード（配列が JIS/US でも同じ物理キー）
    public var keyCode: UInt16
    public var name: String
    public var colorIndex: Int = 0
    public var retrigger: RetriggerMode = .fadeOut
    public var play: PlaySettings
    /// キー一覧での所属グループ（nil は「未分類」）
    public var groupID: UUID? = nil

    public init(keyCode: UInt16, name: String, play: PlaySettings) {
        self.keyCode = keyCode
        self.name = name
        self.play = play
    }
}

/// リストの曲をいつ鳴らし始めるか（前の曲に対して）
public enum StepStart: String, Codable, CaseIterable, Sendable {
    /// 前の曲が終わったら（start.seconds 秒あけて）
    case afterPrevious
    /// 前の曲の終わりに start.seconds 秒重ねる（クロスフェード）
    case overlap
    /// 自動再生しない。前の曲が終わってもリストは待機したまま。Return で鳴らす
    case returnKey

    public var label: String {
        switch self {
        case .afterPrevious: return "前の曲が終わったとき"
        case .overlap: return "前の曲に重ねる"
        case .returnKey: return "Return キーを押したとき（自動再生しない）"
        }
    }
}

/// リストの1曲
public struct SequenceStep: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var play: PlaySettings
    /// この曲を鳴らし始めるタイミング（曲を追加したときは「Return キーを押したとき」）
    public var start: StepStart = .returnKey
    /// afterPrevious なら間の秒数、overlap なら重ねる秒数、returnKey なら Return を押してから鳴るまでの秒数
    public var startSeconds: Double = 0

    public init(name: String, play: PlaySettings) {
        self.name = name
        self.play = play
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, play, start, startSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        play = try c.decode(PlaySettings.self, forKey: .play)
        // 以前の "manual"（自動再生しない）は Return 待ちにまとめた
        let raw = try c.decodeIfPresent(String.self, forKey: .start)
        start = raw == "manual" ? .returnKey : raw.flatMap(StepStart.init(rawValue:)) ?? .afterPrevious
        startSeconds = try c.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
    }
}

/// シーケンシャル再生のリスト（幕間 BGM など）
public struct CueSequence: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    /// 開始／停止を切り替えるキー
    public var toggleKey: UInt16? = nil
    public var steps: [SequenceStep] = []
    /// 最後の曲が終わったら先頭に戻る
    public var loop: Bool = false
    /// 停止キーを押したときのフェードアウト（秒）
    public var stopFade: Double = 3

    public init(name: String) {
        self.name = name
    }
}

/// キー一覧（キーボードを隠したときの表示）のグループ
public struct KeyGroup: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct Show: Codable, Hashable, Sendable {
    public var formatVersion = 1
    public var name: String
    public var sounds: [SoundRef] = []
    /// 並び順はキー一覧の表示順
    public var keyCues: [KeyCue] = []
    public var keyGroups: [KeyGroup] = []
    public var sequences: [CueSequence] = []
    public var masterVolumeDB: Double = 0
    /// Esc（全停止）のフェードアウト（秒）。続けてもう一度押すとカット
    public var panicFade: Double = 2

    public init(name: String) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, name, sounds, keyCues, keyGroups, sequences, masterVolumeDB, panicFade
    }

    /// 項目が足りない古いキューシートも開けるように、無い項目は既定値にする
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        name = try c.decode(String.self, forKey: .name)
        sounds = try c.decodeIfPresent([SoundRef].self, forKey: .sounds) ?? []
        keyCues = try c.decodeIfPresent([KeyCue].self, forKey: .keyCues) ?? []
        keyGroups = try c.decodeIfPresent([KeyGroup].self, forKey: .keyGroups) ?? []
        sequences = try c.decodeIfPresent([CueSequence].self, forKey: .sequences) ?? []
        masterVolumeDB = try c.decodeIfPresent(Double.self, forKey: .masterVolumeDB) ?? 0
        panicFade = try c.decodeIfPresent(Double.self, forKey: .panicFade) ?? 2
    }
}

public extension Double {
    /// 秒を 1:23.4 の形に
    var timeText: String {
        guard isFinite else { return "--:--" }
        let t = Swift.max(0, self)
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }
}
