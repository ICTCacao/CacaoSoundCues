import AVFoundation
import XCTest
@testable import CacaoSoundCuesCore

/// macOS 付属の効果音を、出力のサンプルレートに変換して読めるか
final class AudioDecoderTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")

    private func check(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try XCTUnwrap(AudioDecoder.duration(of: url))
        let b = try AudioDecoder.decode(url: url, sampleRate: 48000)
        XCTAssertEqual(b.sampleRate, 48000, file: file, line: line)
        XCTAssertEqual(b.duration, original, accuracy: 0.06, file: file, line: line)
        XCTAssertGreaterThan(b.peaks.max() ?? 0, 0.05, "無音になっていない", file: file, line: line)
    }

    func testAIFF() throws {
        try check(source)
    }

    func testConvertedFormats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // m4a(AAC) / 44.1kHz モノラル wav
        let jobs: [(String, [String])] = [
            ("a.m4a", ["-f", "m4af", "-d", "aac"]),
            ("b.wav", ["-f", "WAVE", "-d", "LEI16@44100", "-c", "1"]),
        ]
        for (name, args) in jobs {
            let out = dir.appendingPathComponent(name)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            p.arguments = args + [source.path, out.path]
            try p.run()
            p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0)
            try check(out)
        }
    }
}
