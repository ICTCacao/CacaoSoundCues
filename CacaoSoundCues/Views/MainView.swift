import CacaoSoundCuesCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    /// キーボードを表示するか（隠すと、割り当て済みキーの一覧を左に出す）
    @AppStorage("showKeyboard") private var showKeyboard = true
    /// 右側の音源設定（本番モードでは本番用の表示）を出すか
    @AppStorage("showInspector") private var showInspector = true
    /// 言語が変わったら画面全体を作り直す
    @AppStorage(LanguageManager.storageKey) private var language = LanguageManager.defaultCode
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar(showKeyboard: $showKeyboard, showInspector: $showInspector)
                .background(model.showMode ? Color.red.opacity(0.22) : Theme.topBar)
            ThemeDivider()
            VStack(spacing: 0) {
            // リストの欄は、リストがあるとき（か「リスト」ボタンで出したとき）だけ
            let list = model.listVisible
            if showKeyboard {
                KeyboardView()
                    .padding(.vertical, 12)
                    .background(Theme.background)
                ThemeDivider()
                // 音源設定・リストを出す・隠すで分割の数が変わるので、別々の分割画面にして仕切りの位置も別に覚える
                if showInspector && list {
                    HSplitView {
                        SequencePanel()
                            .frame(minWidth: 400, idealWidth: 480)
                            .background(Theme.background)
                            // 仕切りの位置を覚えておく（キーボードを出しているときの2分割）
                            .background(SplitPersistence(key: "split.withKeyboard"))
                        rightPanel
                            .frame(minWidth: 480)
                    }
                } else if showInspector {
                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if list {
                    SequencePanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                } else {
                    Theme.background
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if showInspector && list {
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
            } else if showInspector {
                HSplitView {
                    KeyListPanel()
                        .frame(minWidth: 260, idealWidth: 320)
                        .background(Theme.background)
                        // 仕切りの位置を覚えておく（キーの一覧と音源設定の2分割）
                        .background(SplitPersistence(key: "split.keyList.noList"))
                    rightPanel
                        .frame(minWidth: 460)
                }
            } else if list {
                HSplitView {
                    KeyListPanel()
                        .frame(minWidth: 260, idealWidth: 320)
                        .background(Theme.background)
                        // 仕切りの位置を覚えておく（キーボードと音源設定を隠しているときの2分割）
                        .background(SplitPersistence(key: "split.keyList.noInspector"))
                    SequencePanel()
                        .frame(minWidth: 380, idealWidth: 460)
                        .background(Theme.background)
                }
            } else {
                KeyListPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
            }
            // Pro 版だけ: 台本のパネルを横に出す
            .proScriptPanel()
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
    @Binding var showInspector: Bool
    @AppStorage("showFunctionKeys") private var showFunctionKeys = false
    @AppStorage("showKeypad") private var showKeypad = false
    @AppStorage("keyboardScale") private var keyboardScale = 1.0

    var body: some View {
        // 窓が狭い（ノートの画面など）ときは、ボタンを絵だけにし、それでも入らなければ右端の機器の表示を省く
        ViewThatFits(in: .horizontal) {
            bar(compact: false, info: true)
            bar(compact: true, info: true)
            bar(compact: true, info: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func bar(compact: Bool, info: Bool) -> some View {
        @Bindable var model = model
        return HStack(spacing: compact ? 8 : 14) {
            TextField(L("キューシート名"), text: $model.show.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 160 : 220)
                .disabled(model.showMode)
            Group {
            Button { model.openPanel() } label: { Label(L("開く…"), systemImage: "folder") }
                .disabled(model.showMode)
                .help(L("開く…"))
            Button { model.save() } label: { Label(L("保存"), systemImage: "square.and.arrow.down") }
                .help(L("保存"))
            Button { model.toggleShowMode() } label: {
                Label(model.showMode ? L("本番モード中") : L("本番モード"), systemImage: model.showMode ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.showMode ? .red : .gray)
            .help(model.showMode ? L("本番モードを終了して、編集できるようにする") : L("編集を止めて、キー操作と再生だけにする"))
            // 並びは 台本（Pro 版だけ）・キーボード・リスト・音源設定
            #if PRO
            ProTopBarItems()
            #endif
            Toggle(isOn: $showKeyboard) {
                Label(L("キーボード"), systemImage: "keyboard")
            }
            .toggleStyle(.button)
            .help(L("キーボードを隠すと、割り当てたキーだけを一覧で表示します"))
            // リストの欄（リストが無いときは隠れる。押すと「リストを作る」の欄が出る）
            Toggle(isOn: Binding(get: { model.listVisible }, set: { model.setListVisible($0) })) {
                Label(L("リスト"), systemImage: "music.note.list")
            }
            .toggleStyle(.button)
            .help(L("リスト（曲を順番に流す）の欄を出す・隠す。リストが 1 つも無いときは隠れます"))
            Toggle(isOn: $showInspector) {
                Label(L("音源設定"), systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .help(L("右側の音源設定（本番モードでは本番用の表示）を出す・隠す"))
            Menu {
                Toggle(L("F キー（F1〜F12）の行を表示"), isOn: $showFunctionKeys)
                Toggle(L("テンキーを表示"), isOn: $showKeypad)
                Picker(L("キーボードの大きさ"), selection: $keyboardScale) {
                    Text(L("大")).tag(1.0)
                    Text(L("中")).tag(0.85)
                    Text(L("小")).tag(0.7)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("キーボードに出すキーの設定（この Mac に保存）"))
            }
            .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))

            Spacer(minLength: 8)

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
                Label(compact ? L("全停止") : L("全停止（Esc）"), systemImage: "stop.fill")
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .help(L("全部の音をすぐ止める（フェードなし）"))

            if info {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(AppModel.versionText) ・ \(model.output.deviceName)  \(String(format: "%.1f", model.sampleRate / 1000))kHz")
                Text(L("バッファ %d（%.1fms）・メモリ %dMB", Int(model.output.bufferFrames), model.output.latencyMilliseconds, model.memoryBytes / 1_048_576))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            }
        }
    }
}

/// ラベルの出し方を、狭いときと広いときで切り替える
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

extension View {
    /// Pro 版だけ: 台本のパネルを横に並べる（Simple 版ではそのまま）
    @ViewBuilder
    func proScriptPanel() -> some View {
        #if PRO
        ProScriptSplit { self }
        #else
        self
        #endif
    }
}
