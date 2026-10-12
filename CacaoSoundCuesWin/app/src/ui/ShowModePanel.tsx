// 本番モードのときに設定画面の代わりに出す、本番用の表示（Mac 版 ShowModePanel.swift）
import { L } from "../i18n";
import { timeText, type CueSequence, type SequenceStep, type VoiceStatus } from "../model";
import { activeSequenceID, colorOf, playingOwner, run, show, status, upcomingIndex } from "../store";
import { Icon } from "./icons";
import { KeyBadge } from "./Keyboard";

const progress = (v: VoiceStatus) => Math.min(1, Math.max(0, (v.position - v.start) / Math.max(0.001, v.end - v.start)));
const seconds = (s: number) => L("%.1f秒", s);

function timing(step: SequenceStep): string {
  switch (step.start) {
    case "afterPrevious": return step.startSeconds > 0 ? L("（前の曲の %@後）", seconds(step.startSeconds)) : L("（前の曲の後すぐ）");
    case "overlap": return L("（%@重ねる）", seconds(step.startSeconds));
    case "returnKey": return step.startSeconds > 0 ? L("（Enter の %@後）", seconds(step.startSeconds)) : L("（Enter で）");
  }
}

function NextLine({ seq, index }: { seq: CueSequence; index: number | null }) {
  if (index === null || index < 0 || index >= seq.steps.length) return <div class="sub">{L("次の曲はありません")}</div>;
  const step = seq.steps[index];
  return (
    <div class="next-line">
      <span class="capsule next">{L("次")}</span>
      <b class="title3 ellipsis">{index + 1}. {step.name}</b>
      <span class="sub">{timing(step)}</span>
    </div>
  );
}

export function ShowModePanel() {
  const sh = show.value;
  const seqID = activeSequenceID();
  const seq = sh.sequences.find(q => q.id === seqID);
  const r = run.value;
  const playing = sh.keyCues.flatMap(c => { const v = playingOwner(c.id); return v ? [[c, v] as const] : []; });

  let body;
  if (seq && r && r.sequenceID === seq.id) {
    const index = r.currentIndex;
    if (index !== null && index < seq.steps.length) {
      const step = seq.steps[index];
      const voice = status.value.find(v => v.token === r.currentToken);
      body = <>
        <div class="title1">{index + 1}. {step.name}</div>
        {voice && voice.armed && voice.startsIn >= 0 && <div class="title2 orange mono">{L("あと %.1f 秒で鳴ります", voice.startsIn)}</div>}
        {voice && !voice.armed && <>
          <div class={"bigtime" + (voice.stopping ? " orange" : "")}>{voice.looping ? "∞" : "-" + timeText(voice.remaining)}</div>
          <div class="progress"><div style={{ width: `${progress(voice) * 100}%`, background: voice.stopping ? "orange" : "#34c759" }} /></div>
        </>}
      </>;
    } else {
      body = <div class="waiting">{L("Enter 待ち")}</div>;
    }
    body = <>{body}<NextLine seq={seq} index={upcomingIndex(seq.id)} /></>;
  } else if (seq) {
    body = <>
      <div class="title1 sub">{L("止まっています")}</div>
      <NextLine seq={seq} index={upcomingIndex(seq.id) ?? (seq.steps.length === 0 ? null : 0)} />
    </>;
  } else {
    body = <div class="sub">{L("リストはありません")}</div>;
  }

  return (
    <div class="showmode">
      <div class="showmode-title"><Icon name="lock" size={22} />{L("本番モード")}</div>
      <section>
        <h4>{seq ? L("リスト「%@」", seq.name) : L("リスト")}</h4>
        {body}
      </section>
      <hr />
      <section>
        <h4>{L("鳴っているキー")}</h4>
        {playing.length === 0 && <div class="sub">{L("なし")}</div>}
        {playing.map(([c, v]) => (
          <div key={c.id} class="hrow">
            <KeyBadge code={c.keyCode} color={colorOf(c.colorIndex)} lit />
            <span class="title3 grow">{c.name}</span>
            <span class={"title3 mono" + (v.stopping ? " orange" : "")}>{v.looping ? "∞" : "-" + timeText(v.remaining)}</span>
          </div>
        ))}
      </section>
      <hr />
      <section class="hint-list">
        <Hint k="Enter" text={L("Standby を再生（待っている間にもう一度押すと、すぐ鳴る）")} />
        <Hint k="space" text={L("今の曲を途中で終える")} />
        <Hint k={L("↑↓・ダブルクリック")} text={L("Standby にする")} />
        <Hint k="esc" text={L("全部の音をすぐ止める")} />
      </section>
    </div>
  );
}

function Hint({ k, text }: { k: string; text: string }) {
  return <div class="hrow"><kbd class="big">{k}</kbd><span class="sub">{text}</span></div>;
}
