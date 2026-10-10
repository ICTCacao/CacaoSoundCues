import CacaoSoundCuesCore
import SwiftUI

/// キーボードを隠したときの、割り当て済みキーの一覧（グループ分け・並べ替えができる）
struct KeyListPanel: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("キー").font(.headline)
                Spacer()
                Button { model.addKeyGroup() } label: { Label("グループ", systemImage: "folder.badge.plus") }
                    .help("グループを追加")
                Button { model.chooseFileThenKey(group: nil) } label: { Label("割り当て", systemImage: "plus") }
                    .help("音ファイルを選んで、キーに割り当てる")
            }

            if let pending = model.pendingAssign {
                HStack {
                    Image(systemName: "keyboard")
                    Text("「\(pending.urls.first?.deletingPathExtension().lastPathComponent ?? "")」を割り当てるキーを押してください（Esc で取消）")
                        .lineLimit(2)
                }
                .font(.callout.bold())
                .foregroundStyle(.orange)
            }

            List(selection: selectionBinding) {
                let ungrouped = model.cues(in: nil)
                if !ungrouped.isEmpty || model.show.keyGroups.isEmpty {
                    Section {
                        rows(ungrouped, group: nil)
                    } header: {
                        if !model.show.keyGroups.isEmpty { Text("未分類") }
                    }
                }
                ForEach(model.show.keyGroups) { group in
                    Section {
                        rows(model.cues(in: group.id), group: group.id)
                    } header: {
                        GroupHeader(group: group)
                    }
                }
                let seqKeys = model.show.sequences.filter { $0.toggleKey != nil }
                if !seqKeys.isEmpty {
                    Section("リストの開始／停止") {
                        ForEach(seqKeys) { seq in
                            HStack {
                                KeyBadge(code: seq.toggleKey!, color: .indigo, lit: model.isRunning(seq.id))
                                Text("≡ " + seq.name)
                                Spacer()
                                if model.isRunning(seq.id) {
                                    Text(model.run?.isWaiting == true ? "Return 待ち" : "再生中")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                }
                            }
                            .selectionDisabled()
                        }
                    }
                }
            }
            .overlay {
                if model.show.keyCues.isEmpty {
                    Text("音ファイルをここにドラッグして、\n割り当てるキーを押します")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? Color.accentColor : Theme.keyBorder.opacity(0.6), lineWidth: targeted ? 2 : 1))
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                model.pendingAssign = (urls, nil)
                return true
            } isTargeted: { targeted = $0 }
        }
        .padding(12)
    }

    @ViewBuilder
    private func rows(_ cues: [KeyCue], group: UUID?) -> some View {
        ForEach(cues) { cue in
            KeyRow(cue: cue)
                .tag(cue.keyCode)
        }
        .onMove { model.moveCues(in: group, from: $0, to: $1) }
    }

    private var selectionBinding: Binding<UInt16?> {
        Binding(
            get: { if case .key(let code) = model.selection { return code } else { return nil } },
            set: { new in
                AppModel.endEditing()
                if let new { model.selection = .key(new) }
            })
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: KeyGroup

    var body: some View {
        HStack(spacing: 6) {
            TextField("グループ名", text: Binding(get: { group.name }, set: { model.renameKeyGroup(group.id, to: $0) }))
                .textFieldStyle(.plain)
                .font(.subheadline.bold())
            Spacer()
            Button { model.chooseFileThenKey(group: group.id) } label: { Image(systemName: "plus") }
                .help("このグループに割り当てを追加")
            Button { model.moveKeyGroup(group.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .help("グループを上へ")
            Button { model.moveKeyGroup(group.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .help("グループを下へ")
            Button { model.removeKeyGroup(group.id) } label: { Image(systemName: "trash") }
                .help("グループを削除（中のキーは未分類へ）")
        }
        .buttonStyle(.borderless)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.pendingAssign = (urls, group.id)
            return true
        }
    }
}

private struct KeyRow: View {
    @Environment(AppModel.self) private var model
    let cue: KeyCue

    var body: some View {
        let voice = model.playing(owner: cue.id)
        HStack(spacing: 8) {
            KeyBadge(code: cue.keyCode, color: AppModel.colors[cue.colorIndex % AppModel.colors.count], lit: voice != nil)
            Text(cue.name).lineLimit(1)
            if cue.play.loop { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let voice {
                Text(voice.loop ? "∞" : "-" + (Double(voice.remainingFrames) / model.sampleRate).timeText)
                    .monospacedDigit()
                    .foregroundStyle(voice.stopping ? .orange : .green)
            }
        }
        .contextMenu {
            Button { model.trigger(cue) } label: { Label("鳴らす／止める", systemImage: "playpause") }
            Menu {
                Button { model.setGroup(nil, forCue: cue.id) } label: { Label("未分類", systemImage: "tray") }
                ForEach(model.show.keyGroups) { g in
                    Button { model.setGroup(g.id, forCue: cue.id) } label: { Label(g.name, systemImage: "folder") }
                }
            } label: {
                Label("グループへ移動", systemImage: "folder.badge.gearshape")
            }
            Button(role: .destructive) { model.removeCue(atKey: cue.keyCode) } label: { Label("割り当てを外す", systemImage: "xmark.circle") }
        }
    }
}

/// キーの文字を色付きの角丸で表示（鳴っている間は明るく）
struct KeyBadge: View {
    let code: UInt16
    let color: Color
    var lit = false

    var body: some View {
        Text(KeyboardLayout.label(code))
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .frame(minWidth: 28, minHeight: 24)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(lit ? 0.95 : 0.4)))
    }
}
