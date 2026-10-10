import CacaoSoundCuesCore
import SwiftUI

/// 本番モードのときに設定画面の代わりに出す、本番用の表示（今の曲・残り時間・次の曲・鳴っているキー）
struct ShowModePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(L("本番モード"), systemImage: "lock.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.red)

                sequenceSection
                Divider()
                keysSection
                Divider()
                hints
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - リスト

    @ViewBuilder
    private var sequenceSection: some View {
        let seqID = model.activeSequenceID
        let seq = seqID.flatMap { id in model.show.sequences.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            Text(seq.map { L("リスト「%@」", $0.name) } ?? L("リスト"))
                .font(.headline)
                .foregroundStyle(.secondary)

            if let seq, let run = model.run, run.sequenceID == seq.id {
                if let index = run.currentIndex, seq.steps.indices.contains(index) {
                    let step = seq.steps[index]
                    let voice = model.status.first { $0.token == run.currentToken }
                    Text("\(index + 1). \(step.name)")
                        .font(.title.bold())
                        .lineLimit(2)
                    if let voice, voice.armed, voice.startsIn >= 0 {
                        Text(L("あと %.1f 秒で鳴ります", Double(voice.startsIn) / model.sampleRate))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                    } else if let voice {
                        Text(voice.loop ? "∞" : "-" + (Double(voice.remainingFrames) / model.sampleRate).timeText)
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(voice.stopping ? .orange : .primary)
                        ProgressView(value: progress(voice))
                            .tint(voice.stopping ? .orange : .green)
                    }
                } else {
                    Text(L("Return 待ち"))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.orange)
                }
                nextLine(seq: seq, index: model.upcomingIndex(seq.id))
            } else if let seq {
                Text(L("止まっています"))
                    .font(.title.bold())
                    .foregroundStyle(.secondary)
                nextLine(seq: seq, index: model.upcomingIndex(seq.id) ?? (seq.steps.isEmpty ? nil : 0))
            } else {
                Text(L("リストはありません")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nextLine(seq: CueSequence, index: Int?) -> some View {
        if let index, seq.steps.indices.contains(index) {
            let step = seq.steps[index]
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("次"))
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                Text("\(index + 1). \(step.name)")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(timing(step))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(L("次の曲はありません")).foregroundStyle(.secondary)
        }
    }

    private func timing(_ step: SequenceStep) -> String {
        switch step.start {
        case .afterPrevious: return step.startSeconds > 0 ? L("（前の曲の %@後）", seconds(step.startSeconds)) : L("（前の曲の後すぐ）")
        case .overlap: return L("（%@重ねる）", seconds(step.startSeconds))
        case .returnKey: return step.startSeconds > 0 ? L("（Return の %@後）", seconds(step.startSeconds)) : L("（Return で）")
        }
    }

    private func seconds(_ s: Double) -> String { String(format: L("%.1f秒"), s) }

    // MARK: - キー

    @ViewBuilder
    private var keysSection: some View {
        let playing = model.show.keyCues.compactMap { cue in model.playing(owner: cue.id).map { (cue, $0) } }
        VStack(alignment: .leading, spacing: 8) {
            Text(L("鳴っているキー"))
                .font(.headline)
                .foregroundStyle(.secondary)
            if playing.isEmpty {
                Text(L("なし")).foregroundStyle(.secondary)
            }
            ForEach(playing, id: \.0.id) { cue, voice in
                HStack(spacing: 10) {
                    KeyBadge(code: cue.keyCode, color: AppModel.colors[cue.colorIndex % AppModel.colors.count], lit: true)
                    Text(cue.name).font(.title3)
                    Spacer()
                    Text(voice.loop ? "∞" : "-" + (Double(voice.remainingFrames) / model.sampleRate).timeText)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(voice.stopping ? .orange : .primary)
                }
            }
        }
    }

    // MARK: - 操作の案内

    private var hints: some View {
        VStack(alignment: .leading, spacing: 6) {
            hint("return", L("次の曲へ（待っている間にもう一度押すと、すぐ鳴る）"))
            hint("space", L("今の曲を途中で終える"))
            hint(L("↑↓・ダブルクリック"), L("次に鳴らす曲を選ぶ"))
            hint("esc", L("全部フェードアウト（2度押しでカット）"))
        }
        .font(.callout)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.callout.bold().monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.keyBorder))
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func progress(_ v: VoiceStatus) -> Double {
        let len = max(1, v.endFrame - v.startFrame)
        return min(1, max(0, Double(v.position - v.startFrame) / Double(len)))
    }
}
