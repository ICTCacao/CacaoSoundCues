import CacaoSoundCuesCore
import SwiftUI

/// キーボードを隠したときの、割り当て済みキーの一覧（グループ分け・並べ替えができる）
struct KeyListPanel: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("キー")).font(.headline)
                Spacer()
                if !model.showMode {
                    Button { model.addKeyGroup() } label: { Label(L("グループ"), systemImage: "folder.badge.plus") }
                        .help(L("グループを追加"))
                    Button { model.chooseFileThenKey(group: nil) } label: { Label(L("割り当て"), systemImage: "plus") }
                        .help(L("音ファイルを選んで、キーに割り当てる"))
                }
            }

            if let pending = model.pendingAssign {
                HStack {
                    Image(systemName: "keyboard")
                    Text(L("「%@」を割り当てるキーを押してください（Esc で取消）",
                           pending.urls.first?.deletingPathExtension().lastPathComponent ?? ""))
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
                        if !model.show.keyGroups.isEmpty { Text(L("未分類")) }
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
                    Section(L("リストの開始／停止")) {
                        ForEach(seqKeys) { seq in
                            HStack {
                                KeyBadge(code: seq.toggleKey!, color: .indigo, lit: model.isRunning(seq.id))
                                Text("≡ " + seq.name)
                                Spacer()
                                if model.isRunning(seq.id) {
                                    Text(model.run?.isWaiting == true ? L("Return 待ち") : L("再生中"))
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
                    Text(L("音ファイルをここにドラッグして、\n割り当てるキーを押します"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? Color.accentColor : Theme.keyBorder.opacity(0.6), lineWidth: targeted ? 2 : 1))
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty, !model.showMode else { return false }
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
        .moveDisabled(model.showMode)
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
            TextField(L("グループ名"), text: Binding(get: { group.name }, set: { model.renameKeyGroup(group.id, to: $0) }))
                .disabled(model.showMode)
                .textFieldStyle(.plain)
                .font(.subheadline.bold())
            Spacer()
            if !model.showMode {
                Button { model.chooseFileThenKey(group: group.id) } label: { Image(systemName: "plus") }
                    .help(L("このグループに割り当てを追加"))
                Button { model.moveKeyGroup(group.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .help(L("グループを上へ"))
                Button { model.moveKeyGroup(group.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .help(L("グループを下へ"))
                Button { model.removeKeyGroup(group.id) } label: { Image(systemName: "trash") }
                    .help(L("グループを削除（中のキーは未分類へ）"))
            }
        }
        .buttonStyle(.borderless)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty, !model.showMode else { return false }
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
            Button { model.trigger(cue) } label: { Label(L("鳴らす／止める"), systemImage: "playpause") }
            if !model.showMode {
                Menu {
                    Button { model.setGroup(nil, forCue: cue.id) } label: { Label(L("未分類"), systemImage: "tray") }
                    ForEach(model.show.keyGroups) { g in
                        Button { model.setGroup(g.id, forCue: cue.id) } label: { Label(g.name, systemImage: "folder") }
                    }
                } label: {
                    Label(L("グループへ移動"), systemImage: "folder.badge.gearshape")
                }
                Button(role: .destructive) { model.removeCue(atKey: cue.keyCode) } label: { Label(L("割り当てを外す"), systemImage: "xmark.circle") }
            }
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
