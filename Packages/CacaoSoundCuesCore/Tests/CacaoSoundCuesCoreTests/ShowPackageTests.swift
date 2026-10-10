import XCTest
@testable import CacaoSoundCuesCore

/// 保存すると音ファイルの実体がキューシートの Audio/ にコピーされ、元のファイルが無くても開けるか
final class ShowPackageTests: XCTestCase {
    func testSaveCopiesAudioIntoPackage() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let original = dir.appendingPathComponent("ベル.aiff")
        try fm.copyItem(at: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), to: original)
        var show = Show(name: "テスト")
        let sound = SoundRef(fileName: "ベル.aiff", displayName: "ベル", duration: 1)
        show.sounds = [sound]
        show.keyCues = [KeyCue(keyCode: 18, name: "ベル", play: PlaySettings(soundID: sound.id))]

        let package = dir.appendingPathComponent("テスト.ccsc")
        let saved = try ShowPackage.save(show, to: package, source: { _ in original })

        // 元のファイルを消しても、キューシートの中のコピーだけで開ける
        try fm.removeItem(at: original)
        let loaded = try ShowPackage.load(from: package)
        let copy = ShowPackage.audioURL(for: loaded.sounds[0], in: package)
        XCTAssertEqual(saved.sounds[0].fileName, loaded.sounds[0].fileName)
        XCTAssertTrue(fm.fileExists(atPath: copy.path))
        XCTAssertTrue(copy.path.hasPrefix(package.path))
        XCTAssertNoThrow(try AudioDecoder.decode(url: copy, sampleRate: 48000))
    }

    func testOldShowWithoutGroupsDecodes() throws {
        let json = #"{"formatVersion":1,"name":"旧","sounds":[],"keyCues":[],"sequences":[],"masterVolumeDB":0,"panicFade":2}"#
        let show = try JSONDecoder().decode(Show.self, from: Data(json.utf8))
        XCTAssertEqual(show.name, "旧")
        XCTAssertTrue(show.keyGroups.isEmpty)
    }
}
