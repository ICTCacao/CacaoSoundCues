// キーボードを隠したときの、割り当て済みキーの一覧（Mac 版 KeyListPanel.swift）
import { L } from "../i18n";
import { timeText, type Id, type KeyCue, type KeyGroup } from "../model";
import { prefs } from "../prefs";
import {
  addKeyGroup, chooseFileThenKey, colorOf, cuesIn, dropTarget, endEditing, isRunning, isWaiting, moveCues, moveKeyGroup,
  pendingAssign, playingOwner, removeCue, removeKeyGroup, renameKeyGroup, run, selection, setGroup, show, trigger,
} from "../store";
import { openMenu, useReorder } from "./common";
import { Icon } from "./icons";
import { KeyBadge } from "./Keyboard";

export function KeyList() {
  const sh = show.value;
  const showMode = prefs.showMode.value;
  const pending = pendingAssign.value;
  const ungrouped = cuesIn(null);
  const seqKeys = sh.sequences.filter(q => q.toggleKey !== undefined);
  const targeted = dropTarget.value === "keylist";
  const baseName = (p: string) => (p.split(/[\\/]/).pop() ?? p).replace(/\.[^.]+$/, "");

  return (
    <div class="panel-body">
      <div class="panel-head">
        <h3>{L("キー")}</h3>
        <span class="spacer" />
        {!showMode && <>
          <button class="btn" onClick={addKeyGroup} title={L("グループを追加")}><Icon name="folderPlus" />{L("グループ")}</button>
          <button class="btn" onClick={() => chooseFileThenKey(null)} title={L("音ファイルを選んで、キーに割り当てる")}><Icon name="plus" />{L("割り当て")}</button>
        </>}
      </div>
      {pending && (
        <div class="pending"><Icon name="keyboard" />{L("「%@」を割り当てるキーを押してください（Esc で取消）", baseName(pending.paths[0] ?? ""))}</div>
      )}
      <div class={"listbox" + (targeted ? " targeted" : "")} data-drop="keylist">
        {(ungrouped.length > 0 || sh.keyGroups.length === 0) && (
          <Section title={sh.keyGroups.length > 0 ? L("未分類") : null} cues={ungrouped} group={null} />
        )}
        {sh.keyGroups.map(g => <Section key={g.id} group={g.id} cues={cuesIn(g.id)} header={<GroupHeader group={g} />} />)}
        {seqKeys.length > 0 && (
          <div class="section">
            <div class="section-head">{L("リストの開始／停止")}</div>
            {seqKeys.map(q => (
              <div key={q.id} class="row">
                <KeyBadge code={q.toggleKey!} color="#5856d6" lit={isRunning(q.id)} />
                <span class="grow ellipsis">≡ {q.name}</span>
                {isRunning(q.id) && <span class="tag-text green">{run.value && isWaiting(run.value) ? L("Enter 待ち") : L("再生中")}</span>}
              </div>
            ))}
          </div>
        )}
        {sh.keyCues.length === 0 && (
          <div class="empty">{L("音ファイルをここにドラッグして、\n割り当てるキーを押します")}</div>
        )}
      </div>
    </div>
  );
}

function Section({ title, cues, group, header }: { title?: string | null; cues: KeyCue[]; group: Id | null; header?: preact.ComponentChildren }) {
  const showMode = prefs.showMode.value;
  const { start, state } = useReorder((from, to) => moveCues(group, from, to), showMode);
  return (
    <div class="section">
      {header ?? (title ? <div class="section-head">{title}</div> : null)}
      <div>
        {cues.map((c, i) => (
          <KeyRow key={c.id} cue={c} index={i} onPointerDown={start(i)}
            dropBefore={state !== null && state.to === i} dropAfter={state !== null && state.to === cues.length && i === cues.length - 1} />
        ))}
      </div>
    </div>
  );
}

function GroupHeader({ group }: { group: KeyGroup }) {
  const showMode = prefs.showMode.value;
  const targeted = dropTarget.value === `group:${group.id}`;
  return (
    <div class={"section-head group" + (targeted ? " targeted" : "")} data-drop={`group:${group.id}`}>
      <input class="plain" value={group.name} disabled={showMode} placeholder={L("グループ名")}
        onInput={e => renameKeyGroup(group.id, (e.target as HTMLInputElement).value)}
        onKeyDown={e => { if (e.key === "Enter") endEditing(); }} />
      {!showMode && <span class="icon-buttons">
        <button class="ibtn" onClick={() => chooseFileThenKey(group.id)} title={L("このグループに割り当てを追加")}><Icon name="plus" /></button>
        <button class="ibtn" onClick={() => moveKeyGroup(group.id, -1)} title={L("グループを上へ")}><Icon name="up" /></button>
        <button class="ibtn" onClick={() => moveKeyGroup(group.id, 1)} title={L("グループを下へ")}><Icon name="down" /></button>
        <button class="ibtn" onClick={() => removeKeyGroup(group.id)} title={L("グループを削除（中のキーは未分類へ）")}><Icon name="trash" /></button>
      </span>}
    </div>
  );
}

function KeyRow({ cue, index, onPointerDown, dropBefore, dropAfter }: { cue: KeyCue; index: number; onPointerDown: (e: PointerEvent) => void; dropBefore: boolean; dropAfter: boolean }) {
  const voice = playingOwner(cue.id);
  const sel = selection.value;
  const selected = sel.kind === "key" && sel.code === cue.keyCode;
  const showMode = prefs.showMode.value;
  const groups = show.value.keyGroups;
  const onContextMenu = (e: MouseEvent) => openMenu(e, [
    { label: L("鳴らす／止める"), icon: "playPause", action: () => trigger(cue) },
    ...(showMode ? [] : [
      {
        label: L("グループへ移動"), icon: "folder", submenu: [
          { label: L("未分類"), icon: "tray", action: () => setGroup(null, cue.id) },
          ...groups.map(g => ({ label: g.name, icon: "folder", action: () => setGroup(g.id, cue.id) })),
        ],
      },
      { label: L("割り当てを外す"), icon: "xCircle", danger: true, action: () => removeCue(cue.keyCode) },
    ]),
  ]);
  return (
    <div class={"row" + (selected ? " selected" : "") + (dropBefore ? " drop-before" : "") + (dropAfter ? " drop-after" : "")}
      data-row={index}
      onPointerDown={e => { endEditing(); selection.value = { kind: "key", code: cue.keyCode }; onPointerDown(e); }}
      onContextMenu={onContextMenu}>
      <KeyBadge code={cue.keyCode} color={colorOf(cue.colorIndex)} lit={!!voice} />
      <span class="grow ellipsis">{cue.name}</span>
      {cue.play.loop && <span class="sub"><Icon name="repeat" size={12} /></span>}
      {voice && <span class={"mono " + (voice.stopping ? "orange" : "green")}>{voice.looping ? "∞" : "-" + timeText(voice.remaining)}</span>}
    </div>
  );
}
