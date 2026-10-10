import CacaoSoundCuesCore
import SwiftUI

/// シーケンシャル再生のリスト（幕間 BGM など）
struct SequencePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("リスト")).font(.headline)
                if !model.show.sequences.isEmpty {
                    Picker("", selection: $model.selectedSequenceID) {
                        ForEach(model.show.sequences) { seq in
                            Text(seq.name).tag(Optional(seq.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                if !model.showMode {
                    Button { model.addSequence() } label: { Image(systemName: "plus") }
                        .help(L("リストを追加"))
                    if let id = model.selectedSequenceID {
                        Button { model.removeSequence(id) } label: { Image(systemName: "minus") }
                            .help(L("このリストを削除"))
                    }
                }
                Spacer()
            }

            if let id = model.selectedSequenceID, let seq = model.sequenceBinding(id) {
                SequenceEditor(seq: seq)
            } else {
                VStack(spacing: 8) {
                    Text(L("幕間 BGM など、曲を順番に続けて再生するリストです。"))
                    Button { model.addSequence() } label: { Label(L("リストを作る"), systemImage: "music.note.list") }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }
}

private struct SequenceEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var seq: CueSequence
    @State private var targeted = false

    var body: some View {
        let running = model.isRunning(seq.id)
        VStack(alignment: .leading, spacing: 8) {
            // リスト名・ループ・キー・停止フェードは本番モードでは触れない
            Group {
            HStack {
                TextField(L("リスト名"), text: $seq.name).textFieldStyle(.roundedBorder)
                Toggle(L("最後まで行ったら先頭へ"), isOn: $seq.loop)
            }
            HStack {
                Text(L("開始／停止キー")).fixedSize()
                Button {
                    model.capturingSequenceKey = seq.id
                } label: {
                    Label(model.capturingSequenceKey == seq.id
                          ? L("キーを押してください…")
                          : (seq.toggleKey.map { KeyboardLayout.label($0) } ?? L("未設定")),
                          systemImage: "keyboard")
                        .font(.body.monospaced())
                }
                if seq.toggleKey != nil {
                    Button { seq.toggleKey = nil } label: { Label(L("解除"), systemImage: "xmark") }
                }
                Spacer()
                Text(L("停止フェード")).fixedSize()
                SecondsField(value: $seq.stopFade).frame(width: 60)
                Text(L("秒"))
            }
            }
            .disabled(model.showMode)

            ScrollViewReader { proxy in
            List(selection: selectionBinding) {
                ForEach(Array(seq.steps.enumerated()), id: \.element.id) { index, step in
                    StepRow(index: index, step: step, sequenceID: seq.id)
                        .tag(step.id)
                        // 選び直さない（同じ行の）クリックでも文字入力を終え、Return をリストに戻す
                        .simultaneousGesture(TapGesture().onEnded { AppModel.endEditing() })
                }
                .onMove { seq.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    offsets.map { seq.steps[$0].id }.forEach { model.removeStep($0, from: seq.id) }
                }
                .moveDisabled(model.showMode)
                .deleteDisabled(model.showMode)
            }
            // ダブルクリックで「次に鳴らす曲」をこの曲にする（鳴らすのは Return）
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let index = seq.steps.firstIndex(where: { $0.id == id }) {
                    Button { model.cueStep(seq.id, index: index) } label: { Label(L("次に鳴らす曲にする（Return で再生）"), systemImage: "return") }
                    if !model.showMode {
                        Button(role: .destructive) { model.removeStep(id, from: seq.id) } label: { Label(L("削除"), systemImage: "trash") }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let index = seq.steps.firstIndex(where: { $0.id == id }) {
                    model.cueStep(seq.id, index: index)
                }
            }
            .overlay {
                if seq.steps.isEmpty {
                    Text(L("曲のファイルをここにドラッグ")).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? Color.accentColor : Theme.keyBorder.opacity(0.6), lineWidth: targeted ? 2 : 1))
            .dropDestination(for: URL.self) { urls, _ in
                model.appendSteps(urls, to: seq.id)
                return true
            } isTargeted: { targeted = $0 }
            // 鳴り始めた曲の行が見えるようにスクロール
            .onChange(of: selectionBinding.wrappedValue) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
            }

            // 操作キーの説明（スペースは画面のキーボードに出さないため、ここで案内する）
            HStack(spacing: 14) {
                KeyHint(key: "space", text: L("今の曲を途中で終える"))
                KeyHint(key: "return", text: L("次の曲へ"))
                KeyHint(key: L("↑↓・ダブルクリック"), text: L("次に鳴らす曲を選ぶ"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    model.toggleSequence(seq.id)
                } label: {
                    Label(running ? L("停止") : L("開始"), systemImage: running ? "stop.fill" : "play.fill")
                        .frame(width: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(running ? .orange : .green)
                Button {
                    if running { model.advanceActiveSequence() } else { model.startSequence(seq.id) }
                } label: {
                    Label(L("次の曲へ（Return）"), systemImage: "return")
                }
                if let r = model.run, r.sequenceID == seq.id, r.isWaiting {
                    Text(L("Return 待ち"))
                        .font(.callout.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(L("%d 曲・%@", seq.steps.count, totalDuration.timeText))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: {
                if case let .step(s, step) = model.selection, s == seq.id { return step }
                return nil
            },
            set: { new in
                AppModel.endEditing()
                if let new { model.selection = .step(sequence: seq.id, step: new) }
            })
    }

    private var totalDuration: Double {
        seq.steps.reduce(0) { sum, step in
            let full = model.sound(step.play.soundID)?.duration ?? 0
            return sum + max(0, (step.play.outPoint ?? full) - step.play.inPoint) * Double(step.play.plays ?? 1)
        }
    }
}

private struct StepRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let step: SequenceStep
    let sequenceID: UUID

    var body: some View {
        let voice = model.playing(tag: step.id)
        let upcoming = model.upcomingIndex(sequenceID) == index
        let full = model.sound(step.play.soundID)?.duration ?? 0
        let length = max(0, (step.play.outPoint ?? full) - step.play.inPoint) * Double(step.play.plays ?? 1)
        HStack {
            Image(systemName: voice != nil ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(voice != nil ? Color.green : .secondary)
                .frame(width: 18)
            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let wait = model.status.first(where: { $0.tag == step.id && $0.armed && $0.startsIn >= 0 }),
               step.start == .returnKey {
                Text(L("あと %.1f 秒", Double(wait.startsIn) / model.sampleRate))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if upcoming && voice == nil {
                Text(L("次")).font(.caption.bold()).foregroundStyle(.orange)
            }
            if let voice {
                Text(voice.loop ? "∞" : "-" + (Double(voice.remainingFrames) / model.sampleRate).timeText)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            } else {
                Text(length.timeText).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        switch step.start {
        case .afterPrevious: parts.append(step.startSeconds > 0 ? L("前の曲の後 %@あけて", fmt(step.startSeconds)) : L("前の曲の後すぐ"))
        case .overlap: parts.append(L("前の曲に %@重ねる", fmt(step.startSeconds)))
        case .returnKey: parts.append(step.startSeconds > 0 ? L("⏎ Return の %@後", fmt(step.startSeconds)) : L("⏎ Return で"))
        }
        parts.append(step.play.fadeIn > 0 ? "F.in \(fmt(step.play.fadeIn))" : "C.in")
        if step.play.fadeOutAtEnd { parts.append(L("終わり F.out %@", fmt(step.play.fadeOut))) }
        if step.play.loop { parts.append(step.play.plays.map { L("リピート %d回", $0) } ?? L("リピート ∞")) }
        return parts.joined(separator: " · ")
    }

    private func fmt(_ s: Double) -> String { String(format: L("%.1f秒"), s) }
}

/// 「space 今の曲を途中で終える」のような操作の案内
private struct KeyHint: View {
    let key: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.keyBorder))
            Text(text)
        }
        .fixedSize()
    }
}
