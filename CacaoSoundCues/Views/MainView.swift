import CacaoSoundCuesCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    /// キーボードを表示するか（隠すと、割り当て済みキーの一覧を左に出す）
    @AppStorage("showKeyboard") private var showKeyboard = true
    /// 言語が変わったら画面全体を作り直す
    @AppStorage(LanguageManager.storageKey) private var language = LanguageManager.defaultCode
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar(showKeyboard: $showKeyboard)
                .background(model.showMode ? Color.red.opacity(0.22) : Theme.topBar)
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
                        // 仕切りの位置を覚えておく（キーボードを出しているときの2分割）
                        .background(SplitPersistence(key: "split.withKeyboard"))
                    rightPanel
                        .frame(minWidth: 480)
                }
            } else {
                HSplitView {
                    KeyListPanel()
                        .frame(minWidth: 260, idealWidth: 320)
                        .background(Theme.background)
                        // 仕切りの位置を覚えておく（キーボードを隠しているときの3分割）
                        .background(SplitPersistence(key: "split.keyList"))
                    SequencePanel()
                        .frame(minWidth: 380, idealWidth: 460)
                        .background(Theme.background)
                    rightPanel
                        .frame(minWidth: 460)
                }
            }
        }
        .background(Theme.background)
        .id(language)
        .navigationTitle((model.showMode ? L("● 本番モード — ") : "") + model.show.name + (model.dirty ? L(" — 未保存") : ""))
        // 文字を入れて Return したら入力を終え、キーをすぐ音出しに戻す
        .onSubmit { AppModel.endEditing() }
        .onAppear {
            // 起動直後に文字入力欄が選ばれていると、キーを押しても鳴らないため
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AppModel.endEditing() }
            #if DEBUG
            // 開発版だけ: マニュアルの画面写真用に設定画面を開く
            if UserDefaults.standard.bool(forKey: "debugSettings") { openSettings() }
            #endif
        }
        .alert(L("お知らせ"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

extension MainView {
    /// 右側: ふだんは設定画面、本番モードでは本番用の表示
    @ViewBuilder
    var rightPanel: some View {
        if model.showMode {
            ShowModePanel().background(Theme.panel)
        } else {
            InspectorView().background(Theme.panel)
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
            TextField(L("キューシート名"), text: $model.show.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .disabled(model.showMode)
            Button { model.openPanel() } label: { Label(L("開く…"), systemImage: "folder") }
                .disabled(model.showMode)
            Button { model.save() } label: { Label(L("保存"), systemImage: "square.and.arrow.down") }
            Button { model.toggleShowMode() } label: {
                Label(model.showMode ? L("本番モード中") : L("本番モード"), systemImage: model.showMode ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.showMode ? .red : .gray)
            .help(model.showMode ? L("本番モードを終了して、編集できるようにする") : L("編集を止めて、キー操作と再生だけにする"))
            Toggle(isOn: $showKeyboard) {
                Label(L("キーボード"), systemImage: "keyboard")
            }
            .toggleStyle(.button)
            .help(L("キーボードを隠すと、割り当てたキーだけを一覧で表示します"))
            Menu {
                Toggle(L("F キー（F1〜F12）の行を表示"), isOn: $showFunctionKeys)
                Toggle(L("テンキーを表示"), isOn: $showKeypad)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("キーボードに出すキーの設定（この Mac に保存）"))

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
                Label(L("全停止（Esc）"), systemImage: "stop.fill")
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .help(L("全部フェードアウト。1秒以内にもう一度 Esc でカット"))

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(AppModel.versionText) ・ \(model.output.deviceName)  \(String(format: "%.1f", model.sampleRate / 1000))kHz")
                Text(L("バッファ %d（%.1fms）・メモリ %dMB", Int(model.output.bufferFrames), model.output.latencyMilliseconds, model.memoryBytes / 1_048_576))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
