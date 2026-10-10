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

    var body: some View {
        Form {
            Text("音を追加したときの最初の設定です。追加したあとは、音ごとに変えられます。")
                .foregroundStyle(.secondary)

            Section("キーに割り当てる音") {
                SettingsSeconds(label: "フェードイン", value: $keyFadeIn)
                SettingsSeconds(label: "フェードアウト", value: $keyFadeOut)
                Picker("鳴っている間にもう一度押したら", selection: $keyRetrigger) {
                    ForEach(RetriggerMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section("リストに追加する曲") {
                Picker("鳴らし始めるタイミング", selection: $stepStart) {
                    ForEach(StepStart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                SettingsSeconds(label: stepStart == .overlap ? "重ねる長さ"
                                    : stepStart == .returnKey ? "Return を押してから待つ時間" : "前の曲との間",
                                value: $stepStartSeconds)
                SettingsSeconds(label: "フェードイン", value: $stepFadeIn)
                SettingsSeconds(label: "フェードアウト", value: $stepFadeOut)
                Toggle("終了位置に向けて自動でフェードアウトする", isOn: $stepFadeOutAtEnd)
            }

            Section("共通") {
                Picker("フェードのカーブ", selection: $curve) {
                    ForEach(FadeCurve.allCases.filter { $0 != .custom }, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button { reset() } label: { Label("最初の状態に戻す", systemImage: "arrow.counterclockwise") }
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
                Text("秒")
                Text(value == 0 ? "カット" : " ").foregroundStyle(.orange).frame(width: 40, alignment: .leading)
            }
        }
    }
}
