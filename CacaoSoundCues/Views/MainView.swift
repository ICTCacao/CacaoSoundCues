import CacaoSoundCuesCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    /// キーボードを表示するか（隠すと、割り当て済みキーの一覧を左に出す）
    @AppStorage("showKeyboard") private var showKeyboard = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar(showKeyboard: $showKeyboard)
                .background(Theme.topBar)
            ThemeDivider()
            if showKeyboard {
                KeyboardView()
                    .padding(.vertical, 12)
                    .background(Theme.background)
                ThemeDivider()
                HSplitView {
                    SequencePanel()
                        .frame(minWidth: 400, idealWidth: 480)
                        .background(Theme.background)
                    InspectorView()
                        .frame(minWidth: 480)
                        .background(Theme.panel)
                }
            } else {
                HSplitView {
                    KeyListPanel()
                        .frame(minWidth: 260, idealWidth: 320)
                        .background(Theme.background)
                    SequencePanel()
                        .frame(minWidth: 380, idealWidth: 460)
                        .background(Theme.background)
                    InspectorView()
                        .frame(minWidth: 460)
                        .background(Theme.panel)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle(model.show.name + (model.dirty ? " — 未保存" : ""))
        // 文字を入れて Return したら入力を終え、キーをすぐ音出しに戻す
        .onSubmit { AppModel.endEditing() }
        .onAppear {
            // 起動直後に文字入力欄が選ばれていると、キーを押しても鳴らないため
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AppModel.endEditing() }
        }
        .alert("お知らせ", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showKeyboard: Bool
    @AppStorage("showFunctionKeys") private var showFunctionKeys = false
    @AppStorage("showKeypad") private var showKeypad = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 14) {
            TextField("キューシート名", text: $model.show.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button { model.openPanel() } label: { Label("開く…", systemImage: "folder") }
            Button { model.save() } label: { Label("保存", systemImage: "square.and.arrow.down") }
            Toggle(isOn: $showKeyboard) {
                Label("キーボード", systemImage: "keyboard")
            }
            .toggleStyle(.button)
            .help("キーボードを隠すと、割り当てたキーだけを一覧で表示します")
            Menu {
                Toggle("F キー（F1〜F12）の行を表示", isOn: $showFunctionKeys)
                Toggle("テンキーを表示", isOn: $showKeypad)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("キーボードに出すキーの設定（この Mac に保存）")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2")
                Slider(value: $model.show.masterVolumeDB, in: -40...6)
                    .frame(width: 140)
                    .onChange(of: model.show.masterVolumeDB) { model.applyMasterVolume() }
                Text(String(format: "%+.1f dB", model.show.masterVolumeDB))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .leading)
            }

            Button {
                model.panic()
            } label: {
                Label("全停止（Esc）", systemImage: "stop.fill")
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .help("全部フェードアウト。1秒以内にもう一度 Esc でカット")

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(AppModel.versionText) ・ \(model.output.deviceName)  \(String(format: "%.1f", model.sampleRate / 1000))kHz")
                Text("バッファ \(model.output.bufferFrames)（\(String(format: "%.1f", model.output.latencyMilliseconds))ms）・メモリ \(model.memoryBytes / 1_048_576)MB")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
