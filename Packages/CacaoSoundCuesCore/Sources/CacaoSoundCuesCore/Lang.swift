import Foundation

/// 画面の言語。日本語の原文をキーにして、言語ファイル（JSON）の訳に置き換える。
/// 訳が無い言葉は、英語 → 日本語の原文の順に使う。
public enum Lang {
    /// いまの言語の訳（キー = 日本語の原文）
    public nonisolated(unsafe) static var table: [String: String] = [:]
    /// 英語の訳（ほかの言語で訳が無いときに使う）
    public nonisolated(unsafe) static var english: [String: String] = [:]

    public static func translate(_ ja: String) -> String {
        table[ja] ?? english[ja] ?? ja
    }
}

/// 画面に出す言葉。L("保存") のように日本語の原文で書く
public func L(_ ja: String) -> String {
    Lang.translate(ja)
}

/// 値を差し込む言葉。原文は "「%@」を開けません" のように書式で書く
public func L(_ ja: String, _ args: CVarArg...) -> String {
    String(format: Lang.translate(ja), arguments: args)
}
