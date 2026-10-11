import CacaoSoundCuesCore
import SwiftUI

/// 選んだキーの音、またはリストの曲の設定
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch model.selection {
                case .key(let code):
                    keyInspector(code)
                case let .step(seqID, stepID):
                    if let step = model.stepBinding(sequence: seqID, step: stepID) {
                        StepInspector(step: step)
                    } else {
                        placeholder
                    }
                case .none:
                    placeholder
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func keyInspector(_ code: UInt16) -> some View {
        if let cue = model.cueBinding(code) {
            KeyCueInspector(cue: cue)
        } else if let seq = model.sequence(forKey: code) {
            Text(L("キー「%@」: リスト「%@」の開始／停止", KeyboardLayout.label(code), seq.name)).font(.headline)
        } else {
            Text(L("キー「%@」", KeyboardLayout.label(code))).font(.headline)
            Text(L("音ファイルをこのキーにドラッグすると割り当てられます。")).foregroundStyle(.secondary)
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("使い方")).font(.headline)
            Text(L("・音ファイル（wav / aiff / mp3 / m4a など）をキーにドラッグして割り当てる"))
            Text(L("・キーを押すと鳴る。鳴っている間にもう一度押すとフェードアウト（0秒ならカットアウト）"))
            Text(L("・キーをクリックすると、ここで再生範囲・フェード・リピートを設定できる"))
            Text(L("・リスト（幕間 BGM など）は1つずつ鳴る。Return で次の曲へ進む（鳴っていなければ選んでいるリストを開始）"))
            Text(L("・リストの曲をダブルクリックすると、その曲が「次」になる。Return で鳴る"))
            Text(L("・スペースでリストの今の曲を途中で終える（次の曲はその曲のタイミング設定どおりに続く）"))
            Text(L("・Esc で全部フェードアウト、続けてもう一度 Esc でカット"))
        }
        .foregroundStyle(.secondary)
    }
}

private struct KeyCueInspector: View {
    @Environment(AppModel.self) private var model
    @Binding var cue: KeyCue

    var body: some View {
        HStack {
            Text(KeyboardLayout.label(cue.keyCode))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(AppModel.colors[cue.colorIndex % AppModel.colors.count].opacity(0.5)))
            TextField(L("名前"), text: $cue.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            ForEach(AppModel.colors.indices, id: \.self) { i in
                Circle()
                    .fill(AppModel.colors[i])
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.primary, lineWidth: cue.colorIndex == i ? 2 : 0))
                    .onTapGesture { cue.colorIndex = i }
            }
        }
        HStack {
            Text(L("鳴っている間にもう一度押したら")).fixedSize()
            Picker(L("鳴っている間にもう一度押したら"), selection: $cue.retrigger) {
                ForEach(RetriggerMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        PlaySettingsEditor(settings: $cue.play, owner: cue.id)
    }
}

private struct StepInspector: View {
    @Environment(AppModel.self) private var model
    @Binding var step: SequenceStep

    var body: some View {
        TextField(L("曲名"), text: $step.name)
            .textFieldStyle(.roundedBorder)
            .font(.title3)
        GroupBox(L("この曲を鳴らし始めるタイミング")) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $step.start) {
                    ForEach(StepStart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                HStack {
                    Text(step.start == .overlap ? L("重ねる長さ") : step.start == .returnKey ? L("Return を押してから") : L("前の曲との間")).fixedSize()
                    Slider(value: $step.startSeconds.rounded(0.1), in: 0...30)
                    SecondsField(value: $step.startSeconds).frame(width: 60)
                    Text(step.start == .returnKey ? L("秒待って鳴らす") : L("秒")).fixedSize()
                }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        }
        PlaySettingsEditor(settings: $step.play, owner: step.id)
    }

    private var hint: String {
        let common = L("どのタイミングでも、再生中に Return を押すとすぐこの曲へ進みます（前の曲はその曲のフェードアウトで止まります）。リストの最初の曲は開始キーで鳴ります。")
        switch step.start {
        case .afterPrevious:
            return L("前の曲が終わったら自動で鳴ります。") + common
        case .overlap:
            return L("前の曲の終わりに重ねて鳴ります（クロスフェード）。前の曲は重ねる長さで自動的にフェードアウトし、この曲は重ねる長さでフェードインします。前の曲の「終了位置に向けて自動でフェードアウト」や、この曲の「フェードイン」を設定してあれば、そちらが優先されます。") + common
        case .returnKey:
            return L("自動では鳴りません。前の曲が終わってもリストは待機したままで、Return を押すと鳴ります（待機中に開始／停止キーを押すとリストは止まります）。秒数を入れると、Return を押してからその秒数だけ待って鳴ります（前の曲は Return を押したときに止まります）。待っている間にもう一度 Return を押すと、すぐ鳴ります。")
        }
    }
}

/// キーの音とリストの曲で共通の設定
struct PlaySettingsEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: PlaySettings
    let owner: UUID
    /// 編集中の線（音量ラインか PANライン。波形の操作をその線に切り替える）
    enum LineMode { case none, volume, pan }
    @State private var lineMode: LineMode = .none
    private var editingLine: Bool { lineMode != .none }
    @State private var selectedPoint: UUID?
    @State private var selectedSegment: Int?
    /// 右のつまみで書き込み中の値（dB）と、最後に点を書いた時刻（秒）
    @State private var writingDB: Double?
    @State private var lastWriteTime: Double?
    @State private var dragStartDB: Double = 0
    /// 右の PAN スライダーで書き込み中の値と、最後に点を書いた時刻
    @State private var writingPan: Double?
    @State private var lastPanWriteTime: Double?
    @State private var dragStartPan: Double = 0

    var body: some View {
        let sound = model.sound(settings.soundID)
        let buffer = model.buffers[settings.soundID]
        let duration = buffer?.duration ?? sound?.duration ?? 0
        let previewing = model.playing(owner: AppModel.previewOwner)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform")
                Text(sound.map(originalFileName) ?? L("（音なし）")).lineLimit(1).truncationMode(.middle)
                Text(duration.timeText).monospacedDigit().foregroundStyle(.secondary)
                if case .failed(let reason) = model.loadStates[settings.soundID] {
                    Text(reason).foregroundStyle(.red)
                }
                Spacer()
                Button {
                    model.preview(settings)
                } label: {
                    Label(previewing != nil ? L("試聴を止める") : L("試聴"), systemImage: previewing != nil ? "stop.fill" : "play.fill")
                }
                .disabled(buffer == nil)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    // 左: PAN と基本の音量 ／ 真ん中: 波形と音量ライン ／ 右: いまの音量（音量ラインに合わせて自動で動く）
                    HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        PanSlider(pan: $settings.pan, onChange: { model.livePan(owner, pan: $0) })
                        Text(String(format: "%+.1f", settings.volumeDB)).font(.caption.monospacedDigit())
                        FaderView(db: $settings.volumeDB, onChange: { model.liveVolume(owner, db: $0) })
                    }
                    .frame(width: 58, height: waveHeight)
                    .help(L("左右（PAN）と、この音の基本の音量。ダブルクリックで中央／0dB に戻す"))
                    WaveformView(peaks: buffer?.peaks ?? [], duration: duration,
                                 inPoint: $settings.inPoint, outPoint: $settings.outPoint,
                                 playhead: playhead(buffer: buffer),
                                 activeFade: activeFade(buffer: buffer),
                                 fadeIn: $settings.fadeIn,
                                 fadeOut: $settings.fadeOut,
                                 fadeOutAtEnd: settings.fadeOutAtEnd && settings.plays != nil,
                                 curve: $settings.curve,
                                 fadeInBezier: $settings.fadeInBezier,
                                 fadeOutBezier: $settings.fadeOutBezier,
                                 onSeek: { seconds in
                                     if let v = playingVoice { model.seek(token: v.token, to: seconds) }
                                 })
                        // PANライン（ピンク）と音量ライン（水色）。編集中の線が操作を受け取る
                        .overlay {
                            ZStack {
                                VolumeLineView(kind: .pan, points: $settings.panPoints, selectedPoint: $selectedPoint,
                                               selectedSegment: $selectedSegment, duration: duration, editing: lineMode == .pan,
                                               playhead: playhead(buffer: buffer),
                                               liveValue: playingVoice.map { Double($0.panNow) - settings.pan })
                                    .allowsHitTesting(lineMode == .pan)
                                    .zIndex(lineMode == .pan ? 1 : 0)
                                VolumeLineView(kind: .volume, points: $settings.volumePoints, selectedPoint: $selectedPoint,
                                               selectedSegment: $selectedSegment, duration: duration, editing: lineMode == .volume,
                                               playhead: playhead(buffer: buffer),
                                               liveValue: playingVoice.map { 20 * log10(Double(max($0.lineGain, 0.0001))) })
                                    .allowsHitTesting(lineMode == .volume)
                            }
                        }
                        .frame(height: waveHeight)
                    VStack(spacing: 4) {
                        // いまの左右。再生中はPANラインに合わせて動き、ドラッグするとPANラインを書き込む
                        PanSlider(pan: Binding(get: { rightPan }, set: { rightPanChanged($0) }),
                                  tint: livePan != nil || writingPan != nil ? .yellow : .accentColor,
                                  onBegin: { beginPanWriting() }, onEnd: { endPanWriting() })
                        Text(String(format: "%+.1f", rightDB)).font(.caption.monospacedDigit())
                            .foregroundStyle(liveDB != nil || writingDB != nil ? Color.yellow : .primary)
                        // 再生中にドラッグすると、その位置の音量ラインを書き込む。止まっているときは音量ライン全体を上下する
                        FaderView(db: Binding(get: { rightDB }, set: { rightFaderChanged($0) }),
                                  tint: .yellow,
                                  onBegin: { beginWriting() },
                                  onEnd: { endWriting() })
                    }
                    .frame(width: 58, height: waveHeight)
                    .help(L("いまの左右と音量（基本 ＋ PANライン・音量ライン）。再生中はラインに合わせて動き、ドラッグするとその場のラインを書き込む。止まっているときはライン全体を動かす"))
                    }
                    if editingLine { volumeLineControls }
                    HStack {
                        Text(L("開始")).fixedSize()
                        SecondsField(value: Binding(get: { settings.inPoint },
                                                    set: { settings.inPoint = min(max(0, $0), (settings.outPoint ?? duration) - 0.01) }))
                            .frame(width: 80)
                        Text(settings.inPoint.timeText).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        Spacer(minLength: 4)
                        Text(L("終了")).fixedSize()
                        SecondsField(value: Binding(get: { settings.outPoint ?? duration },
                                                    set: { v in
                                                        let c = min(max(v, settings.inPoint + 0.01), duration)
                                                        settings.outPoint = c >= duration ? nil : c
                                                    }))
                            .frame(width: 80)
                        Text((settings.outPoint ?? duration).timeText).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        Button {
                            settings.inPoint = 0
                            settings.outPoint = nil
                        } label: { Label(L("全体に戻す"), systemImage: "arrow.left.and.right") }
                    }
                    Text(L("緑（開始）と赤（終了）の線をドラッグして範囲を、上の端のオレンジの丸をドラッグしてフェードの長さを、白い四角をドラッグしてフェードの形（ベジエ曲線）を決めます（点線は止めたときのフェードアウト）。再生中は波形をクリックするとその位置へ移ります。長さ %@", ((settings.outPoint ?? duration) - settings.inPoint).timeText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            } label: {
                HStack {
                    Text(L("再生範囲"))
                    Spacer()
                    Toggle(isOn: Binding(get: { lineMode == .volume }, set: { setLineMode($0 ? .volume : .none) })) {
                        Label(L("音量ライン"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .toggleStyle(.button)
                    .help(L("曲の中で音量を変える線を、波形の上で編集します"))
                    Toggle(isOn: Binding(get: { lineMode == .pan }, set: { setLineMode($0 ? .pan : .none) })) {
                        Label(L("PANライン"), systemImage: "arrow.left.arrow.right")
                    }
                    .toggleStyle(.button)
                    .help(L("曲の中で左右を変える線を、波形の上で編集します"))
                }
            }
            // 選んだマークを delete キーで消せるようにする
            .onChange(of: selectedPoint) { _, id in
                model.deleteKeyAction = id == nil ? nil : { deleteSelectedPoint() }
            }
            .onDisappear { model.deleteKeyAction = nil }
            // 右のつまみを押さえている間は、動かさなくても再生位置に書き続ける（DAW の「タッチ」）
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                if let w = writingDB, playingVoice != nil { rightFaderChanged(w) }
                if let p = writingPan, playingVoice != nil { rightPanChanged(p) }
            }
            // 音量ラインを動かしたら、鳴っている音にもすぐ効かせる
            .onChange(of: settings.volumePoints) { _, points in model.liveVolumeLine(owner, points: points) }
            .onChange(of: settings.panPoints) { _, points in model.livePanLine(owner, points: points) }

            GroupBox(L("フェード（0秒 = カット）")) {
                VStack(alignment: .leading, spacing: 6) {
                    FadeRow(label: L("フェードイン"), value: $settings.fadeIn)
                    FadeRow(label: L("フェードアウト"), value: $settings.fadeOut)
                    Toggle(L("終了位置に向けて自動でフェードアウトする（長さは上と同じ）"), isOn: $settings.fadeOutAtEnd)
                        .disabled(settings.plays == nil)
                    // ラベルとボタンを別にして、幅が足りなくてもラベルが縦に折れないようにする
                    HStack {
                        Text(L("カーブ")).fixedSize()
                        Picker(L("カーブ"), selection: $settings.curve) {
                            ForEach(FadeCurve.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .padding(4)
            }

            // 幅が狭くても文字が縦に折れないよう、リピートと音量は別の行にする
            HStack(spacing: 12) {
                Toggle(L("リピート（開始〜終了をくり返す）"), isOn: $settings.loop)
                    .fixedSize()
                if settings.loop {
                    Picker(L("回数"), selection: Binding(
                        get: { settings.loopCount > 0 },
                        set: { settings.loopCount = $0 ? max(2, settings.loopCount) : 0 })) {
                        Text(L("止めるまで")).tag(false)
                        Text(L("回数を指定")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if settings.loopCount > 0 {
                        Stepper(value: $settings.loopCount, in: 2...99) {
                            Text(L("%d 回鳴らす", settings.loopCount)).monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }

    /// キューシートに保存したファイル名から、先頭の「ID-」を除いた元の名前
    private func originalFileName(_ s: SoundRef) -> String {
        let prefix = s.id.uuidString + "-"
        return s.fileName.hasPrefix(prefix) ? String(s.fileName.dropFirst(prefix.count)) : s.fileName
    }

    /// 右のつまみに出す値（書き込み中はつまみの値）
    private var rightDB: Double { writingDB ?? currentDB }

    private func beginWriting() {
        dragStartDB = currentDB
        lastWriteTime = nil
        writingDB = currentDB
    }

    /// 右のつまみを動かした。再生中は再生位置に音量ラインの点を書き込む（DAW の「タッチ」のように）。
    /// 止まっているときは、音量ライン全体（無ければ基本の音量）を同じだけ上下する
    private func rightFaderChanged(_ newDB: Double) {
        writingDB = newDB
        if let v = playingVoice, let buffer = model.buffers[settings.soundID] {
            let t = (Double(v.position) / buffer.sampleRate * 100).rounded() / 100
            let lineDB = min(max(newDB - settings.volumeDB, VolumePoint.minDB), VolumePoint.maxDB)
            settings.volumePoints = writeLinePoint(settings.volumePoints, value: (lineDB * 10).rounded() / 10,
                                                   at: t, after: lastWriteTime)
            lastWriteTime = t
        } else {
            let delta = newDB - dragStartDB
            dragStartDB = newDB
            if settings.volumePoints.isEmpty {
                settings.volumeDB = min(max(settings.volumeDB + delta, FaderView.range.lowerBound), FaderView.range.upperBound)
                model.liveVolume(owner, db: settings.volumeDB)
            } else {
                for i in settings.volumePoints.indices {
                    settings.volumePoints[i].db = min(max(settings.volumePoints[i].db + delta, VolumePoint.minDB), VolumePoint.maxDB)
                }
            }
        }
    }

    private func setLineMode(_ mode: LineMode) {
        lineMode = mode
        selectedPoint = nil
        selectedSegment = nil
    }

    // MARK: - PANライン（右の PAN スライダー）

    /// 再生中のいまの左右（PANラインがあるときだけ）
    private var livePan: Double? {
        guard !settings.panPoints.isEmpty, let v = playingVoice else { return nil }
        return Double(v.panNow)
    }

    /// 右の PAN スライダーに出す値
    private var rightPan: Double {
        writingPan ?? livePan ?? min(max(settings.pan + volumeLineDB(settings.panPoints, at: settings.inPoint), -1), 1)
    }

    private func beginPanWriting() {
        dragStartPan = rightPan
        lastPanWriteTime = nil
        writingPan = rightPan
    }

    /// 右の PAN スライダーを動かした。再生中は再生位置に PANライン の点を書き込む。
    /// 止まっているときは、PANライン全体（無ければ基本の PAN）を同じだけ動かす
    private func rightPanChanged(_ newPan: Double) {
        writingPan = newPan
        if let v = playingVoice, let buffer = model.buffers[settings.soundID] {
            let t = (Double(v.position) / buffer.sampleRate * 100).rounded() / 100
            let value = min(max(newPan - settings.pan, -1), 1)
            settings.panPoints = writeLinePoint(settings.panPoints, value: (value * 100).rounded() / 100,
                                                at: t, after: lastPanWriteTime)
            lastPanWriteTime = t
        } else {
            let delta = newPan - dragStartPan
            dragStartPan = newPan
            if settings.panPoints.isEmpty {
                settings.pan = min(max(settings.pan + delta, -1), 1)
                model.livePan(owner, pan: settings.pan)
            } else {
                for i in settings.panPoints.indices {
                    settings.panPoints[i].db = min(max(settings.panPoints[i].db + delta, -1), 1)
                }
            }
        }
    }

    private func endPanWriting() {
        if lastPanWriteTime != nil {
            settings.panPoints = simplifyVolumePoints(settings.panPoints, tolerance: 0.02)
        }
        writingPan = nil
        lastPanWriteTime = nil
    }

    /// 線に、時刻 t の点を書き込む。前に書いた時刻から t までの点は上書きする。
    /// 最初の書き込みなら、それまでの値が変わらないよう始まりの点も置く
    private func writeLinePoint(_ points: [VolumePoint], value: Double, at t: Double, after from: Double?) -> [VolumePoint] {
        var pts = points
        let linear = FadeBezier.preset(.linear, rising: true)
        if pts.isEmpty, t > settings.inPoint + 0.05 {
            pts.append(VolumePoint(time: settings.inPoint, db: 0, shape: linear))
        }
        if let from {
            pts.removeAll { $0.time > from + 0.001 && $0.time <= t + 0.001 }
        } else {
            pts.removeAll { abs($0.time - t) < 0.001 }
        }
        pts.append(VolumePoint(time: t, db: value, shape: linear))
        pts.sort { $0.time < $1.time }
        return pts
    }

    private func deleteSelectedPoint() {
        guard let id = selectedPoint else { return }
        settings.volumePoints.removeAll { $0.id == id }
        settings.panPoints.removeAll { $0.id == id }
        selectedPoint = nil
        selectedSegment = nil
    }

    /// 書き込みを終えたら、細かく記録した点を必要なものだけに減らす
    private func endWriting() {
        if lastWriteTime != nil {
            settings.volumePoints = simplifyVolumePoints(settings.volumePoints)
        }
        writingDB = nil
        lastWriteTime = nil
    }

    /// 波形の高さ（ラインを編集していないときも、編集するときと同じ高さ）
    private var waveHeight: CGFloat { 220 }

    /// 右のつまみに出す音量。再生中は今の値、止まっていれば開始位置での値
    private var currentDB: Double {
        liveDB ?? settings.volumeDB + volumeLineDB(settings.volumePoints, at: settings.inPoint)
    }

    /// 再生中のいまの音量（音の音量 ＋ 音量ライン、dB）。音量ラインが無いときや止まっているときは nil
    private var liveDB: Double? {
        guard !settings.volumePoints.isEmpty, let v = playingVoice else { return nil }
        return settings.volumeDB + 20 * log10(Double(max(v.lineGain, 0.00001)))
    }

    /// 音量ラインの編集中に、波形の下に出す説明と操作
    @ViewBuilder
    private var volumeLineControls: some View {
        let pan = lineMode == .pan
        let points = pan ? $settings.panPoints : $settings.volumePoints
        HStack(spacing: 10) {
            if let id = selectedPoint, let i = points.wrappedValue.firstIndex(where: { $0.id == id }) {
                let p = points.wrappedValue[i]
                Text(pan ? L("マーク %@ ／ %@", p.time.timeText, PanSlider.label(p.db))
                         : L("マーク %@ ／ %@ dB", p.time.timeText, String(format: "%+.1f", p.db)))
                    .monospacedDigit()
                Button(role: .destructive) {
                    deleteSelectedPoint()
                } label: { Label(L("このマークを消す"), systemImage: "minus.circle") }
                .help(L("delete キーでも消せます"))
            }
            Spacer()
            Button(role: .destructive) {
                points.wrappedValue = []
                selectedPoint = nil
                selectedSegment = nil
            } label: { Label(pan ? L("PANラインを消す") : L("音量ラインを消す"), systemImage: "trash") }
            .disabled(points.wrappedValue.isEmpty)
        }
        Text(pan ? L("ピンクの線が左右です（上が L、下が R、真ん中が中央）。左の PAN に足し合わせます。線をクリックでマークを足す、マークをドラッグで動かす、⌥クリックか delete キーで消す。マークとマークの間をクリックすると、白い四角でつなぎの形を変えられます。")
                 : L("水色の線が音量です。線をクリックでマークを足す、マークをドラッグで動かす、⌥クリックか delete キーで消す。マークとマークの間をクリックすると、白い四角でつなぎの形（ベジエ曲線）を変えられます。フェードインは、最初のマークの音量まで上がります。"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 試聴中か、この持ち主で鳴っている位置（秒）
    private func playhead(buffer: SampleBuffer?) -> Double? {
        guard let buffer else { return nil }
        return playingVoice.map { Double($0.position) / buffer.sampleRate }
    }

    /// いま進んでいるフェード（2ms のクリック防止は出さない）
    private func activeFade(buffer: SampleBuffer?) -> ActiveFade? {
        guard let buffer, let v = playingVoice, v.fading, v.fadeLength > Int(buffer.sampleRate * 0.05) else { return nil }
        let sr = buffer.sampleRate
        let now = Double(v.position) / sr
        return ActiveFade(start: now - Double(v.fadeElapsed) / sr, length: Double(v.fadeLength) / sr,
                          from: Double(v.fadeFrom), to: Double(v.fadeTo), level: Double(v.level))
    }

    /// この音で鳴っているもの（試聴、キー、リストの曲）
    private var playingVoice: VoiceStatus? {
        model.playing(owner: AppModel.previewOwner) ?? model.playing(owner: owner) ?? model.playing(tag: owner)
    }
}

private struct FadeRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label).frame(width: 190, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Slider(value: $value.rounded(0.1), in: 0...20)
            SecondsField(value: $value).frame(width: 60)
            Text(L("秒"))
            Text(value == 0 ? L("カット") : "").foregroundStyle(.orange).frame(width: 40, alignment: .leading)
        }
    }
}

/// 秒の入力欄（Return で確定）
struct SecondsField: View {
    @Binding var value: Double

    var body: some View {
        TextField("", value: Binding(get: { value }, set: { value = max(0, $0) }),
                  format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

extension Binding where Value == Double {
    /// スライダー用: 値を unit 刻みに丸める（Slider の step: を使うと目盛りの点線が出るため）
    func rounded(_ unit: Double) -> Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = ($0 / unit).rounded() * unit })
    }
}
