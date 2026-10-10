import CacaoSoundCuesCore
import SwiftUI

/// 設定（⌘,）: 音を追加したときの最初の設定
struct SettingsView: View {
    @AppStorage(NewSoundDefaults.keyFadeIn) private var keyFadeIn = 0.0
    @AppStorage(NewSoundDefaults.keyFadeOut) private var keyFadeOut = 0.0
    @AppStorage(NewSoundDefaults.keyRetrigger) private var keyRetrigger = RetriggerMode.fadeOut
    @AppStorage(NewSoundDefaults.stepFadeIn) private var stepFadeIn = 0.0
    @AppStorage(NewSoundDefaults.stepFadeOut) private var stepFadeOut = 0.0
    @AppStorage(NewSoundDefaults.stepFadeOutAtEnd) private var stepFadeOutAtEnd = false
    @AppStorage(NewSoundDefaults.stepStart) private var stepStart = StepStart.returnKey
    @AppStorage(NewSoundDefaults.stepStartSeconds) private var stepStartSeconds = 0.0
    @AppStorage(NewSoundDefaults.curve) private var curve = FadeCurve.equalPower
    @AppStorage(LanguageManager.storageKey) private var language = LanguageManager.defaultCode
    @State private var languages = LanguageManager.available()

    var body: some View {
        Form {
            Section(L("言語") + " / Language") {
                // 先に言葉を切り替えてから値を変える（画面を描き直すときに新しい言葉を使うため）
                Picker(L("画面の言語"), selection: Binding(
                    get: { language },
                    set: { code in
                        guard code != language else { return }
                        LanguageManager.apply(code)
                        language = code
                        DispatchQueue.main.async { LanguageManager.change(to: code) }
                    })) {
                    ForEach(languages) { Text($0.name).tag($0.code) }
                }
                Text(L("ほかの言語は、翻訳用のひな形（英語）を書き出し、英語の部分を置き換えて言語のフォルダに置くと選べるようになります。訳の無い言葉は英語で表示されます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button { LanguageManager.exportTemplate(); languages = LanguageManager.available() } label: {
                        Label(L("翻訳用のひな形を書き出す…"), systemImage: "square.and.arrow.up")
                    }
                    Button { LanguageManager.openFolder() } label: {
                        Label(L("言語のフォルダを開く"), systemImage: "folder")
                    }
                    Button { languages = LanguageManager.available() } label: {
                        Label(L("読み込み直す"), systemImage: "arrow.clockwise")
                    }
                }
            }

            Text(L("音を追加したときの最初の設定です。追加したあとは、音ごとに変えられます。"))
                .foregroundStyle(.secondary)

            Section(L("キーに割り当てる音")) {
                SettingsSeconds(label: L("フェードイン"), value: $keyFadeIn)
                SettingsSeconds(label: L("フェードアウト"), value: $keyFadeOut)
                Picker(L("鳴っている間にもう一度押したら"), selection: $keyRetrigger) {
                    ForEach(RetriggerMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section(L("リストに追加する曲")) {
                Picker(L("鳴らし始めるタイミング"), selection: $stepStart) {
                    ForEach(StepStart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                SettingsSeconds(label: stepStart == .overlap ? L("重ねる長さ")
                                    : stepStart == .returnKey ? L("Return を押してから待つ時間") : L("前の曲との間"),
                                value: $stepStartSeconds)
                SettingsSeconds(label: L("フェードイン"), value: $stepFadeIn)
                SettingsSeconds(label: L("フェードアウト"), value: $stepFadeOut)
                Toggle(L("終了位置に向けて自動でフェードアウトする"), isOn: $stepFadeOutAtEnd)
            }

            Section(L("共通")) {
                Picker(L("フェードのカーブ"), selection: $curve) {
                    ForEach(FadeCurve.allCases.filter { $0 != .custom }, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button { reset() } label: { Label(L("最初の状態に戻す"), systemImage: "arrow.counterclockwise") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func reset() {
        keyFadeIn = 0
        keyFadeOut = 0
        keyRetrigger = .fadeOut
        stepFadeIn = 0
        stepFadeOut = 0
        stepFadeOutAtEnd = false
        stepStart = .returnKey
        stepStartSeconds = 0
        curve = .equalPower
    }
}

private struct SettingsSeconds: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(label) {
            HStack {
                SecondsField(value: $value).frame(width: 70)
                Text(L("秒"))
                Text(value == 0 ? L("カット") : " ").foregroundStyle(.orange).frame(width: 40, alignment: .leading)
            }
        }
    }
}
