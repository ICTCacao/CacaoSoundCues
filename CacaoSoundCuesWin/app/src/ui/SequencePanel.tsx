// シーケンシャル再生のリスト（幕間 BGM など。Mac 版 SequencePanel.swift）
import { useEffect, useRef } from "preact/hooks";
import { L } from "../i18n";
import { plays, timeText, type CueSequence, type Id, type SequenceStep } from "../model";
import { prefs } from "../prefs";
import { keyLabel } from "../keymap";
import {
  addSequence, advanceActiveSequence, capturingSequenceKey, chooseStepFiles, cueStep, dropTarget, edit, endEditing,
  isRunning, isWaiting, loadStates, moveStep, playingTag, removeSequence, removeStep, run, selectedSequenceID, selection, show,
  soundOf, startSequence, status, toggleSequence, upcomingIndex,
} from "../store";
import { KeyHint, SecondsField, Toggle, openMenu, useReorder } from "./common";
import { Icon } from "./icons";

export function SequencePanel() {
  const sh = show.value;
  const showMode = prefs.showMode.value;
  const id = selectedSequenceID.value;
  const seq = sh.sequences.find(q => q.id === id);
  return (
    <div class="panel-body">
      <div class="panel-head">
        <h3>{L("リスト")}</h3>
        {sh.sequences.length > 0 && (
          <select value={id ?? ""} onChange={e => { selectedSequenceID.value = (e.target as HTMLSelectElement).value; endEditing(); }}>
            {sh.sequences.map(q => <option key={q.id} value={q.id}>{q.name}</option>)}
          </select>
        )}
        {!showMode && <>
          <button class="ibtn" onClick={addSequence} title={L("リストを追加")}><Icon name="plus" /></button>
          {id && <button class="ibtn" onClick={() => removeSequence(id)} title={L("このリストを削除")}><Icon name="minus" /></button>}
        </>}
        <span class="spacer" />
      </div>
      {seq ? <SequenceEditor seq={seq} /> : (
        <div class="placeholder">
          <p>{L("幕間 BGM など、曲を順番に続けて再生するリストです。")}</p>
          <button class="btn" onClick={addSequence}><Icon name="list" />{L("リストを作る")}</button>
        </div>
      )}
    </div>
  );
}

function SequenceEditor({ seq }: { seq: CueSequence }) {
  const showMode = prefs.showMode.value;
  const running = isRunning(seq.id);
  const r = run.value;
  const targeted = dropTarget.value === `sequence:${seq.id}`;
  const capturing = capturingSequenceKey.value === seq.id;
  const set = (fn: (q: CueSequence) => void) => edit(() => fn(seq));
  const { start, state } = useReorder((from, to) => moveStep(seq.id, from, to), showMode);
  const listRef = useRef<HTMLDivElement>(null);

  // 鳴り始めた曲の行が見えるようにスクロール
  const sel = selection.value;
  const selectedStep = sel.kind === "step" && sel.sequence === seq.id ? sel.step : null;
  useEffect(() => {
    if (!selectedStep) return;
    listRef.current?.querySelector(`[data-step="${selectedStep}"]`)?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [selectedStep]);

  const total = seq.steps.reduce((sum, st) => {
    const full = soundOf(st.play.soundID)?.duration ?? 0;
    return sum + Math.max(0, (st.play.outPoint ?? full) - st.play.inPoint) * (plays(st.play) ?? 1);
  }, 0);

  return (
    <div class="seq-editor">
      <fieldset class="plain" disabled={showMode}>
        <div class="hrow">
          <input class="grow" value={seq.name} placeholder={L("リスト名")}
            onInput={e => set(q => { q.name = (e.target as HTMLInputElement).value; })}
            onKeyDown={e => { if (e.key === "Enter") endEditing(); }} />
          <Toggle checked={seq.loop} onChange={v => set(q => { q.loop = v; })}>{L("最後まで行ったら先頭へ")}</Toggle>
        </div>
        <div class="hrow">
          <span class="nowrap">{L("開始／停止キー")}</span>
          <button class={"btn mono" + (capturing ? " on" : "")} onClick={() => { capturingSequenceKey.value = seq.id; }}>
            <Icon name="keyboard" />{capturing ? L("キーを押してください…") : seq.toggleKey !== undefined ? keyLabel(seq.toggleKey) : L("未設定")}
          </button>
          {seq.toggleKey !== undefined && (
            <button class="btn" onClick={() => set(q => { delete q.toggleKey; })}><Icon name="x" />{L("解除")}</button>
          )}
          <span class="spacer" />
          <span class="nowrap">{L("停止フェード")}</span>
          <SecondsField value={seq.stopFade} onChange={v => set(q => { q.stopFade = v; })} />
          <span>{L("秒")}</span>
        </div>
      </fieldset>

      <div ref={listRef} class={"listbox steps" + (targeted ? " targeted" : "")} data-drop={`sequence:${seq.id}`}>
        {seq.steps.map((st, i) => (
          <StepRow key={st.id} step={st} index={i} seq={seq} selected={selectedStep === st.id}
            onPointerDown={start(i)}
            dropBefore={state !== null && state.to === i}
            dropAfter={state !== null && state.to === seq.steps.length && i === seq.steps.length - 1} />
        ))}
        {seq.steps.length === 0 && (
          <div class="empty">
            {L("曲のファイルをここにドラッグ")}
            {!showMode && <div><button class="btn" onClick={() => chooseStepFiles(seq.id)}><Icon name="plus" />{L("曲を追加…")}</button></div>}
          </div>
        )}
      </div>

      {/* 操作キーの説明（スペースは画面のキーボードに出さないため、ここで案内する） */}
      <div class="hints">
        <KeyHint k="space" text={L("今の曲を途中で終える")} />
        <KeyHint k="Enter" text={L("Standby を再生")} />
        <KeyHint k={L("↑↓・ダブルクリック")} text={L("Standby にする")} />
      </div>

      <div class="hrow">
        <button class={"btn prominent " + (running ? "orange" : "green")} style={{ minWidth: "96px" }} onClick={() => toggleSequence(seq.id)}>
          <Icon name={running ? "stop" : "play"} />{running ? L("停止") : L("開始")}
        </button>
        <button class="btn" onClick={() => (running ? advanceActiveSequence() : startSequence(seq.id))}>
          <Icon name="returnKey" />{L("次の曲へ（Enter）")}
        </button>
        {r && r.sequenceID === seq.id && isWaiting(r) && <b class="orange">{L("Enter 待ち")}</b>}
        <span class="spacer" />
        {!showMode && seq.steps.length > 0 && (
          <button class="btn" onClick={() => chooseStepFiles(seq.id)} title={L("曲のファイルを選んで、リストの最後に足す")}><Icon name="plus" />{L("曲を追加…")}</button>
        )}
        <span class="sub mono">{L("%d 曲・%@", seq.steps.length, timeText(total))}</span>
      </div>
    </div>
  );
}

function StepRow({ step, index, seq, selected, onPointerDown, dropBefore, dropAfter }: {
  step: SequenceStep; index: number; seq: CueSequence; selected: boolean;
  onPointerDown: (e: PointerEvent) => void; dropBefore: boolean; dropAfter: boolean;
}) {
  const voice = playingTag(step.id);
  const upcoming = upcomingIndex(seq.id) === index;
  const full = soundOf(step.play.soundID)?.duration ?? 0;
  const length = Math.max(0, (step.play.outPoint ?? full) - step.play.inPoint) * (plays(step.play) ?? 1);
  const wait = step.start === "returnKey" ? status.value.find(v => v.tag === step.id && v.armed && v.startsIn >= 0) : undefined;
  const showMode = prefs.showMode.value;
  const st = loadStates.value[step.play.soundID];
  const failed = st?.state === "failed" ? L("読み込めません: %@", st.reason) : null;
  const select = (seqID: Id) => { selectedSequenceID.value = seqID; selection.value = { kind: "step", sequence: seqID, step: step.id }; };
  const onContextMenu = (e: MouseEvent) => {
    select(seq.id);
    openMenu(e, [
      { label: L("次に鳴らす曲にする（Enter で再生）"), icon: "returnKey", action: () => cueStep(seq.id, index) },
      ...(showMode ? [] : [{ label: L("削除"), icon: "trash", danger: true, action: () => removeStep(step.id, seq.id) }]),
    ]);
  };
  return (
    <div class={"row step" + (selected ? " selected" : "") + (dropBefore ? " drop-before" : "") + (dropAfter ? " drop-after" : "")}
      data-row={index} data-step={step.id}
      onPointerDown={e => { endEditing(); select(seq.id); onPointerDown(e); }}
      onDblClick={() => cueStep(seq.id, index)}
      onContextMenu={onContextMenu}>
      {failed
        ? <span class="warn" style={{ width: "18px" }} title={failed}><Icon name="warning" /></span>
        : <span class={voice ? "green" : "sub"} style={{ width: "18px" }}><Icon name={voice ? "speakerOn" : "note"} /></span>}
      <span class="sub mono">{index + 1}.</span>
      <div class="grow" style={{ minWidth: 0 }}>
        <div class="ellipsis">{step.name}</div>
        <div class="caption sub ellipsis">{stepDetail(step)}</div>
      </div>
      {wait && <b class="caption orange mono">{L("あと %.1f 秒", wait.startsIn)}</b>}
      {/* 舞台の言い方（きっかけ直前の「Standby」→「Go」）に合わせる。日本語の画面でも同じ */}
      {upcoming && !voice && <span class="capsule orange-bg">Standby</span>}
      {voice && <span class="capsule green-bg">Playing</span>}
      {voice
        ? <span class="mono green">{voice.looping ? "∞" : "-" + timeText(voice.remaining)}</span>
        : <span class="mono sub">{timeText(length)}</span>}
    </div>
  );
}

const fmt = (s: number) => L("%.1f秒", s);

function stepDetail(step: SequenceStep): string {
  const parts: string[] = [];
  switch (step.start) {
    case "afterPrevious": parts.push(step.startSeconds > 0 ? L("前の曲の後 %@あけて", fmt(step.startSeconds)) : L("前の曲の後すぐ")); break;
    case "overlap": parts.push(L("前の曲に %@重ねる", fmt(step.startSeconds))); break;
    case "returnKey": parts.push(step.startSeconds > 0 ? L("⏎ Enter の %@後", fmt(step.startSeconds)) : L("⏎ Enter で")); break;
  }
  parts.push(step.play.fadeIn > 0 ? `F.in ${fmt(step.play.fadeIn)}` : "C.in");
  if (step.play.fadeOutAtEnd) parts.push(L("終わり F.out %@", fmt(step.play.fadeOut)));
  if (step.play.loop) { const n = plays(step.play); parts.push(n !== null ? L("リピート %d回", n) : L("リピート ∞")); }
  return parts.join(" · ");
}
