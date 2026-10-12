import AppKit
import CacaoSoundCuesCore
import Foundation

/// 言語の切り替え。日本語は原文、英語はアプリに同梱、そのほかの言語は
/// 「~/Library/Application Support/CacaoSoundCues/Languages」に置いた JSON を読む。
/// JSON の形: {"name": "Français", "code": "fr", "strings": {"保存": "Enregistrer", …}}
/// （英語の訳を書き出したひな形の、英語の部分を置き換えて作る。訳の無い言葉は英語で出る）
enum LanguageManager {
    static let storageKey = "language"

    struct Language: Identifiable, Hashable {
        var code: String
        var name: String
        var url: URL?
        var id: String { code }
    }

    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CacaoSoundCues/Languages", isDirectory: true)
    }

    /// Mac の言語が日本語なら日本語、それ以外は英語で始める
    static var defaultCode: String {
        (Locale.preferredLanguages.first ?? "ja").hasPrefix("ja") ? "ja" : "en"
    }

    static var currentCode: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultCode
    }

    private static var bundledEnglish: URL? { Bundle.main.url(forResource: "en", withExtension: "json") }

    static func available() -> [Language] {
        var list = [Language(code: "ja", name: "日本語", url: nil)]
        if let en = bundledEnglish { list.append(Language(code: "en", name: "English", url: en)) }
        let files = (try? FileManager.default.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let file = read(url), !list.contains(where: { $0.code == file.code }) else { continue }
            list.append(Language(code: file.code, name: file.name, url: url))
        }
        return list
    }

    /// 選んである言語を読み込んで、画面の言葉に使う
    static func apply(_ code: String = currentCode) {
        guard code != "ja" else {
            Lang.table = [:]
            Lang.english = [:]
            return
        }
        Lang.english = bundledEnglish.flatMap(read)?.strings ?? [:]
        #if PRO
        // Pro 版だけ: Pro の機能の言葉の英訳（en-pro.json）を重ねる
        if let pro = Bundle.main.url(forResource: "en-pro", withExtension: "json").flatMap(read)?.strings {
            Lang.english.merge(pro) { _, new in new }
        }
        #endif
        if code == "en" {
            Lang.table = Lang.english
        } else {
            Lang.table = available().first { $0.code == code }?.url.flatMap(read)?.strings ?? [:]
        }
    }

    /// 言語を変える。画面の言葉はすぐ変わる。メニューバーなど macOS が出す部分は、
    /// このアプリの言語（AppleLanguages）も変えて、起動し直したときに切り替わる
    static func change(to code: String) {
        apply(code)
        UserDefaults.standard.set(code, forKey: storageKey)
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        let alert = NSAlert()
        alert.messageText = L("メニューバーの言語は、アプリを起動し直すと切り替わります。")
        alert.informativeText = L("今すぐ起動し直しますか？")
        alert.addButton(withTitle: L("起動し直す"))
        alert.addButton(withTitle: L("あとで"))
        if alert.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    /// 終了してから、もう一度開く（終了の確認でキャンセルされたら、開き直しは前面に出るだけ）
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// 翻訳用のひな形（英語の訳）を書き出す。英語の部分を自分の言語に置き換えて、言語のフォルダに置く
    static func exportTemplate() {
        guard let en = bundledEnglish, let file = read(en) else { return }
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        let panel = NSSavePanel()
        panel.directoryURL = userFolder
        panel.nameFieldStringValue = "my-language.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let template = LanguageFile(name: "My Language", code: "xx", strings: file.strings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(template).write(to: url, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(userFolder)
    }

    private struct LanguageFile: Codable {
        var name: String
        var code: String
        var strings: [String: String]
    }

    private static func read(_ url: URL) -> LanguageFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LanguageFile.self, from: data)
    }
}
