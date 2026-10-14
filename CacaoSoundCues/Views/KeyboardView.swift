import CacaoSoundCuesCore
import SwiftUI
import UniformTypeIdentifiers

/// キーをドラッグして別のキーへ移すときの印（文字列で渡す）
private let keyDragPrefix = "cacaosoundcues-key:"

struct KeyboardView: View {
    static let maxKeyWidth: CGFloat = 78
    static let keyHeight: CGFloat = 66
    static let functionKeyHeight: CGFloat = 40
    static let spacing: CGFloat = 5
    /// メインのキーとテンキーの間
    static let keypadGap: CGFloat = 22

    @AppStorage("showFunctionKeys") private var showFunctionKeys = false
    @AppStorage("showKeypad") private var showKeypad = false
    /// キーボードの大きさ（1 = いちばん大きい。設定のメニューで 大・中・小）
    @AppStorage("keyboardScale") private var scale = 1.0

    private var keyHeight: CGFloat { (Self.keyHeight * scale).rounded() }
    private var fnHeight: CGFloat { (Self.functionKeyHeight * scale).rounded() }

    private var mainHeight: CGFloat { keyHeight * 4 + Self.spacing * 3 }
    private var showFnHint: Bool { showFunctionKeys && !KeyboardLayout.functionKeysAreStandard }
    private var totalHeight: CGFloat {
        mainHeight
            + (showFunctionKeys ? fnHeight + Self.spacing * 2 : 0)
            + (showFnHint ? 20 : 0)
    }

    var body: some View {
        GeometryReader { geo in
            // 横幅に収まるようにキーの大きさを決める（メイン 13 キー分 + テンキー 4 キー分）
            let columns: CGFloat = 13 + (showKeypad ? 4 : 0)
            let fixed = Self.spacing * (columns - 1) + (showKeypad ? Self.keypadGap : 0) + 40
            let kw = min(Self.maxKeyWidth * scale, max(44 * min(scale, 1), (geo.size.width - fixed) / columns))
            VStack(spacing: Self.spacing) {
                if showFunctionKeys {
                    HStack(spacing: Self.spacing) {
                        ForEach(KeyboardLayout.functionRow, id: \.self) {
                            KeyCapView(code: $0, width: kw, height: fnHeight)
                        }
                    }
                    .padding(.bottom, Self.spacing)
                }
                HStack(alignment: .top, spacing: Self.keypadGap) {
                    mainKeys(kw)
                    if showKeypad { keypad(kw) }
                }
                if showFnHint {
                    Text(L("F キーは fn を押しながら押します。「システム設定 → キーボード → キーボードショートカット → ファンクションキー」で「F1、F2 などのキーを標準のファンクションキーとして使用」を ON にすると、F キーだけで鳴らせます。"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: totalHeight)
    }

    private func mainKeys(_ kw: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row, id: \.self) { KeyCapView(code: $0, width: kw, height: keyHeight) }
                }
                .padding(.leading, KeyboardLayout.rowIndent[index] * kw)
            }
        }
    }

    /// テンキー（5段をメインの4段と同じ高さに収める）
    private func keypad(_ kw: CGFloat) -> some View {
        let h = (mainHeight - Self.spacing * 4) / 5
        return VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(KeyboardLayout.keypadTopRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row, id: \.self) { KeyCapView(code: $0, width: kw, height: h) }
                }
            }
            HStack(alignment: .top, spacing: Self.spacing) {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    HStack(spacing: Self.spacing) {
                        ForEach(KeyboardLayout.keypadRow123, id: \.self) { KeyCapView(code: $0, width: kw, height: h) }
                    }
                    HStack(spacing: Self.spacing) {
                        KeyCapView(code: KeyboardLayout.keypadZero, width: kw * 2 + Self.spacing, height: h)
                        KeyCapView(code: KeyboardLayout.keypadDecimal, width: kw, height: h)
                    }
                }
                KeypadEnterView(width: kw, height: h * 2 + Self.spacing)
            }
        }
    }
}

/// テンキーの enter: Return と同じ「リストの次の曲へ」（割り当て不可）
struct KeypadEnterView: View {
    @Environment(AppModel.self) private var model
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(Color.indigo.opacity(0.18))
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.keyBorder, lineWidth: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("enter").font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(L("次の曲へ")).font(.system(size: 10))
            }
            .padding(5)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .help(L("テンキーの enter は Return と同じ「リストの次の曲へ」です（割り当てはできません）"))
    }
}

struct KeyCapView: View {
    @Environment(AppModel.self) private var model
    let code: UInt16
    var width: CGFloat = KeyboardView.maxKeyWidth
    var height: CGFloat = KeyboardView.keyHeight
    @State private var targeted = false

    var body: some View {
        let cue = model.cue(forKey: code)
        let seq = model.sequence(forKey: code)
        let voice = cue.flatMap { model.playing(owner: $0.id) }
        let seqRunning = seq.map { model.isRunning($0.id) } ?? false
        let lit = voice != nil || seqRunning
        let selected = model.selection == .key(code)
        let base: Color = cue.map { AppModel.colors[$0.colorIndex % AppModel.colors.count] }
            ?? (seq != nil ? .indigo : Theme.keyEmpty)
        let state = cue.flatMap { model.loadStates[$0.play.soundID] }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(cue == nil && seq == nil ? base : base.opacity(lit ? 0.95 : 0.35))
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(targeted ? Color.accentColor : (selected ? Color.primary : Theme.keyBorder),
                              lineWidth: targeted || selected ? 2.5 : 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(KeyboardLayout.label(code))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Spacer(minLength: 0)
                    if case .failed = state {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    } else if state == .loading {
                        ProgressView().controlSize(.mini)
                    }
                    if cue?.play.loop == true { Image(systemName: "repeat").font(.caption2) }
                }
                Text(cue?.name ?? seq.map { "≡ " + $0.name } ?? "")
                    .font(.system(size: 10))
                    .lineLimit(height < 56 ? 1 : 2)
                Spacer(minLength: 0)
                if let voice {
                    ProgressView(value: progress(voice))
                        .progressViewStyle(.linear)
                        .tint(voice.stopping ? .orange : .white)
                    Text(voice.loop ? "∞" : remaining(voice))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                } else if seqRunning {
                    Text(model.run?.isWaiting == true ? L("Return 待ち") : L("再生中"))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(5)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            AppModel.endEditing()
            model.selection = .key(code)
            if let seq { model.selectedSequenceID = seq.id }
        }
        // 割り当て済みのキーは、別のキーへドラッグして移せる（移り先も割り当て済みなら入れ替え）。option を押しながらでコピー
        .onDrag {
            guard cue != nil || seq != nil, !model.showMode else { return NSItemProvider() }
            return NSItemProvider(object: (keyDragPrefix + String(code)) as NSString)
        }
        // 音ファイルのドロップ（割り当て）と、キーのドロップ（移動・入れ替え）
        .onDrop(of: [.fileURL, .plainText], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
        .contextMenu {
            if let cue {
                Button { model.trigger(cue) } label: { Label(L("鳴らす／止める"), systemImage: "playpause") }
                if !model.showMode {
                    Button(role: .destructive) { model.removeCue(atKey: code) } label: { Label(L("割り当てを外す"), systemImage: "xmark.circle") }
                }
            }
        }
        .help(cue.map { L("%@（%@）", $0.name, model.sound($0.play.soundID)?.fileName ?? "") }
              ?? L("音ファイルをドラッグして割り当て。割り当て済みのキーはドラッグで別のキーへ移せます（option を押しながらでコピー）"))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if model.showMode { return false }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.assign([url], toKey: code) }
            }
            return true
        }
        if let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
            _ = p.loadObject(ofClass: NSString.self) { text, _ in
                guard let text = text as? String, text.hasPrefix(keyDragPrefix),
                      let from = UInt16(text.dropFirst(keyDragPrefix.count)) else { return }
                // option を押しながらドロップしたらコピー（同じ音を、音量などを変えて別のキーでも使う）
                let copy = NSEvent.modifierFlags.contains(.option)
                DispatchQueue.main.async { copy ? model.copyKey(from: from, to: code) : model.moveKey(from: from, to: code) }
            }
            return true
        }
        return false
    }

    private func progress(_ v: VoiceStatus) -> Double {
        let len = max(1, v.endFrame - v.startFrame)
        return min(1, max(0, Double(v.position - v.startFrame) / Double(len)))
    }

    private func remaining(_ v: VoiceStatus) -> String {
        "-" + (Double(v.remainingFrames) / model.sampleRate).timeText
    }
}
