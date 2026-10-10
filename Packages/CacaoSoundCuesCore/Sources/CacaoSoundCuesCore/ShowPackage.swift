import Foundation

public enum ShowPackageError: LocalizedError {
    case missingAudio(String)

    public var errorDescription: String? {
        switch self {
        case .missingAudio(let name): return "音ファイルが見つかりません: \(name)"
        }
    }
}

/// .ccsc パッケージ（フォルダ）: show.json と Audio/ に音ファイルのコピー。
/// フォルダごと USB で持ち運べば別の Mac でもそのまま開ける。
public enum ShowPackage {
    public static let fileExtension = "ccsc"
    public static let audioFolder = "Audio"
    public static let showFile = "show.json"

    public static func load(from url: URL) throws -> Show {
        let data = try Data(contentsOf: url.appendingPathComponent(showFile))
        return try JSONDecoder().decode(Show.self, from: data)
    }

    public static func audioURL(for sound: SoundRef, in package: URL) -> URL {
        package.appendingPathComponent(audioFolder, isDirectory: true).appendingPathComponent(sound.fileName)
    }

    /// 保存する。まだパッケージに無い音は source から Audio/ にコピーし、使っていない音ファイルは消す。
    /// fileName を書き換えた Show を返す。
    public static func save(_ show: Show, to url: URL, source: (SoundRef) -> URL?) throws -> Show {
        let fm = FileManager.default
        var out = show
        let audioDir = url.appendingPathComponent(audioFolder, isDirectory: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)

        var keep = Set<String>()
        for i in out.sounds.indices {
            let s = out.sounds[i]
            let prefix = s.id.uuidString + "-"
            let name = s.fileName.hasPrefix(prefix) ? s.fileName : prefix + s.fileName
            let dest = audioDir.appendingPathComponent(name)
            if !fm.fileExists(atPath: dest.path) {
                guard let src = source(s), fm.fileExists(atPath: src.path) else {
                    throw ShowPackageError.missingAudio(s.displayName)
                }
                try fm.copyItem(at: src, to: dest)
            }
            out.sounds[i].fileName = name
            keep.insert(name)
        }

        for name in (try? fm.contentsOfDirectory(atPath: audioDir.path)) ?? [] where !keep.contains(name) {
            try? fm.removeItem(at: audioDir.appendingPathComponent(name))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(out).write(to: url.appendingPathComponent(showFile), options: .atomic)
        return out
    }
}
