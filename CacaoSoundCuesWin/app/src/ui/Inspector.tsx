// 選んだキーの音、またはリストの曲の設定（Mac 版 InspectorView.swift）
import { useEffect, useRef, useState } from "preact/hooks";
import { L } from "../i18n";
import {
  MAX_DB, MIN_DB, lineValue, originalFileName, panLabel, plays, signed, simplifyPoints, timeText,
  type FadeCurve, type Id, type KeyCue, type PlaySettings, type RetriggerMode, type SequenceStep, type StepStart,
} from "../model";
import { keyLabel } from "../keymap";
import {
  COLORS, PREVIEW_OWNER, colorOf, cueForKey, edit, endEditing, liveUpdate, loadStates, loaded, playingOwner, playingTag,
  preview, seek, selection, sequenceForKey, setDeleteKeyAction, show, soundOf, writeLinePoint,
} from "../store";
import { SecondsField, Segmented, Select, Slider, Toggle, ToggleButton } from "./common";
import { FADER_RANGE, Fader, PanSlider } from "./Fader";
import { Icon } from "./icons";
import { Waveform, type ActiveFade, type LineMode } from "./Waveform";

export const retriggerOptions = (): { value: RetriggerMode; label: string }[] => [
  { value: "fadeOut", label: L("止める（フェードアウト）") },
  { value: "restart", label: L("頭から鳴らし直す") },
  { value: "layer", label: L("重ねて鳴らす") },
  { value: "ignore", label: L("何もしない") },
];
export const stepStartOptions = (): { value: StepStart; label: string }[] => [
  { value: "afterPrevious", label: L("前の曲が終わったとき") },
  { value: "overlap", label: L("前の曲に重ねる") },
  { value: "returnKey", label: L("Enter キーを押したとき（自動再生しない）") },
];
export const curveOptions = (withCustom: boolean): { value: FadeCurve; label: string }[] => [
  { value: "linear", label: L("直線") },
  { value: "equalPower", label: L("等パワー") },
  { value: "sCurve", label: L("S字") },
  ...(withCustom ? [{ value: "custom" as FadeCurve, label: L("カスタム") }] : []),
];

export function Inspector() {
  const sel = selection.value;
  let body;
  if (sel.kind === "key") {
    const cue = cueForKey(sel.code);
    const seq = sequenceForKey(sel.code);
    if (cue) body = <KeyCueInspector key={cue.id} cue={cue} />;
    else if (seq) body = <h3>{L("キー「%@」: リスト「%@」の開始／停止", keyLabel(sel.code), seq.name)}</h3>;
    else body = <>
      <h3>{L("キー「%@」", keyLabel(sel.code))}</h3>
      <p class="sub">{L("音ファイルをこのキーにドラッグすると割り当てられます。")}</p>
    </>;
  } else if (sel.kind === "step") {
    const step = show.value.sequences.find(q => q.id === sel.sequence)?.steps.find(s => s.id === sel.step);
    body = step ? <StepInspector key={step.id} step={step} /> : <Placeholder />;
  } else {
    body = <Placeholder />;
  }
  return <div class="inspector">{body}</div>;
}

function Placeholder() {
  return (
    <div class="sub howto">
      <h3>{L("使い方")}</h3>
      <p>{L("・音ファイル（wav / aiff / mp3 / m4a など）をキーにドラッグして割り当てる")}</p>
      <p>{L("・キーを押すと鳴る。鳴っている間にもう一度押すとフェードアウト（0秒ならカットアウト）")}</p>
      <p>{L("・キーをクリックすると、ここで再生範囲・フェード・リピートを設定できる")}</p>
      <p>{L("・リスト（幕間 BGM など）は1つずつ鳴る。Enter で次の曲へ進む（鳴っていなければ選んでいるリストを開始）")}</p>
      <p>{L("・リストの曲をダブルクリックすると、その曲が「次」になる。Enter で鳴る")}</p>
      <p>{L("・スペースでリストの今の曲を途中で終える（次の曲はその曲のタイミング設定どおりに続く）")}</p>
      <p>{L("・Esc で全部の音をすぐ止める（フェードなし）")}</p>
    </div>
  );
}

function KeyCueInspector({ cue }: { cue: KeyCue }) {
  const set = (fn: (c: KeyCue) => void) => edit(() => fn(cue));
  return (
    <>
      <div class="hrow">
        <span class="bigkey" style={{ background: colorOf(cue.colorIndex) + "80" }}>{keyLabel(cue.keyCode)}</span>
        <input class="grow title3" value={cue.name} placeholder={L("名前")}
          onInput={e => set(c => { c.name = (e.target as HTMLInputElement).value; })}
          onKeyDown={e => { if (e.key === "Enter") endEditing(); }} />
        {COLORS.map((c, i) => (
          <span key={i} class={"colordot" + (cue.colorIndex === i ? " on" : "")} style={{ background: c }}
            onClick={() => set(x => { x.colorIndex = i; })} />
        ))}
      </div>
      <div class="hrow">
        <span class="nowrap">{L("鳴っている間にもう一度押したら")}</span>
        <Select value={cue.retrigger} options={retriggerOptions()} onChange={v => set(c => { c.retrigger = v; })} />
      </div>
      <PlaySettingsEditor p={cue.play} owner={cue.id} />
    </>
  );
}

function StepInspector({ step }: { step: SequenceStep }) {
  const set = (fn: (s: SequenceStep) => void) => edit(() => fn(step));
  const common = L("どのタイミングでも、再生中に Enter を押すとすぐこの曲へ進みます（前の曲はその曲のフェードアウトで止まります）。リストの最初の曲は開始キーで鳴ります。");
  const hint = step.start === "afterPrevious"
    ? L("前の曲が終わったら自動で鳴ります。") + common
    : step.start === "overlap"
      ? L("前の曲の終わりに重ねて鳴ります（クロスフェード）。前の曲は重ねる長さで自動的にフェードアウトし、この曲は重ねる長さでフェードインします。前の曲の「終了位置に向けて自動でフェードアウト」や、この曲の「フェードイン」を設定してあれば、そちらが優先されます。") + common
      : L("自動では鳴りません。前の曲が終わってもリストは待機したままで、Enter を押すと鳴ります（待機中に開始／停止キーを押すとリストは止まります）。秒数を入れると、Enter を押してからその秒数だけ待って鳴ります（前の曲は Enter を押したときに止まります）。待っている間にもう一度 Enter を押すと、すぐ鳴ります。");
  return (
    <>
      <input class="title3 full" value={step.name} placeholder={L("曲名")}
        onInput={e => set(s => { s.name = (e.target as HTMLInputElement).value; })}
        onKeyDown={e => { if (e.key === "Enter") endEditing(); }} />
      <fieldset class="group">
        <legend>{L("この曲を鳴らし始めるタイミング")}</legend>
        <div class="radios">
          {stepStartOptions().map(o => (
            <label key={o.value} class="radio">
              <input type="radio" checked={step.start === o.value} onChange={() => { set(s => { s.start = o.value; }); endEditing(); }} />
              {o.label}
            </label>
          ))}
        </div>
        <div class="hrow">
          <span class="nowrap">{step.start === "overlap" ? L("重ねる長さ") : step.start === "returnKey" ? L("Enter を押してから") : L("前の曲との間")}</span>
          <Slider value={step.startSeconds} min={0} max={30} onChange={v => set(s => { s.startSeconds = v; })} />
          <SecondsField value={step.startSeconds} onChange={v => set(s => { s.startSeconds = v; })} />
          <span class="nowrap">{step.start === "returnKey" ? L("秒待って鳴らす") : L("秒")}</span>
        </div>
        <p class="caption sub">{hint}</p>
      </fieldset>
      <PlaySettingsEditor p={step.play} owner={step.id} />
    </>
  );
}

const WAVE_HEIGHT = 220;

/** キーの音とリストの曲で共通の設定 */
function PlaySettingsEditor({ p, owner }: { p: PlaySettings; owner: Id }) {
  const [lineMode, setLineModeState] = useState<LineMode>("none");
  const [selectedPoint, setSelectedPoint] = useState<Id | null>(null);
  const [selectedSegment, setSelectedSegment] = useState<number | null>(null);
  // 右のつまみ・PAN スライダーで書き込み中の値と、最後に点を書いた時刻
  const w = useRef({ db: null as number | null, lastTime: null as number | null, startDB: 0, pan: null as number | null, lastPanTime: null as number | null, startPan: 0 });
  const [, force] = useState(0);

  const sound = soundOf(p.soundID);
  const info = loaded.get(p.soundID);
  const st = loadStates.value[p.soundID];
  const duration = info?.duration ?? sound?.duration ?? 0;
  const previewing = playingOwner(PREVIEW_OWNER);
  const voice = previewing ?? playingOwner(owner) ?? playingTag(owner);
  const playhead = voice && info ? voice.position : null;

  /** 設定を書き換え、鳴っている音にもすぐ効かせる */
  const change = (fn: (q: PlaySettings) => void) => {
    edit(() => fn(p));
    liveUpdate(owner, p);
  };

  const pRef = useRef(p);
  pRef.current = p;
  const voiceRef = useRef(voice);
  voiceRef.current = voice;

  // 選んだマークを delete キーで消せるようにする
  useEffect(() => {
    setDeleteKeyAction(selectedPoint ? () => deleteSelectedPoint() : null);
    return () => setDeleteKeyAction(null);
  }, [selectedPoint]);

  const deleteSelectedPoint = () => {
    if (!selectedPoint) return;
    change(q => {
      q.volumePoints = q.volumePoints.filter(x => x.id !== selectedPoint);
      q.panPoints = q.panPoints.filter(x => x.id !== selectedPoint);
    });
    setSelectedPoint(null);
    setSelectedSegment(null);
  };

  const setLineMode = (m: LineMode) => {
    setLineModeState(m);
    setSelectedPoint(null);
    setSelectedSegment(null);
  };

  // MARK: 右のつまみ（音量ライン）

  const liveDB = p.volumePoints.length > 0 && voice ? p.volumeDB + 20 * Math.log10(Math.max(voice.lineGain, 0.00001)) : null;
  const currentDB = liveDB ?? p.volumeDB + lineValue(p.volumePoints, p.inPoint);
  const rightDB = w.current.db ?? currentDB;

  const beginWriting = () => {
    w.current.startDB = currentDB;
    w.current.lastTime = null;
    w.current.db = currentDB;
    force(n => n + 1);
  };

  /** 右のつまみを動かした。再生中は再生位置に音量ラインの点を書き込む。止まっているときは線全体を上下する */
  const rightFaderChanged = (newDB: number) => {
    const s = w.current;
    s.db = newDB;
    const q = pRef.current;
    const v = voiceRef.current;
    if (v) {
      const t = Math.round(v.position * 100) / 100;
      const lineDB = Math.min(Math.max(newDB - q.volumeDB, MIN_DB), MAX_DB);
      change(x => { x.volumePoints = writeLinePoint(x, x.volumePoints, Math.round(lineDB * 10) / 10, t, s.lastTime); });
      s.lastTime = t;
    } else {
      const delta = newDB - s.startDB;
      s.startDB = newDB;
      change(x => {
        if (x.volumePoints.length === 0) x.volumeDB = Math.min(Math.max(x.volumeDB + delta, FADER_RANGE[0]), FADER_RANGE[1]);
        else x.volumePoints = x.volumePoints.map(pt => ({ ...pt, db: Math.min(Math.max(pt.db + delta, MIN_DB), MAX_DB) }));
      });
    }
  };

  const endWriting = () => {
    if (w.current.lastTime !== null) change(x => { x.volumePoints = simplifyPoints(x.volumePoints); });
    w.current.db = null;
    w.current.lastTime = null;
    force(n => n + 1);
  };

  // MARK: 右の PAN スライダー（PANライン）

  const livePan = p.panPoints.length > 0 && voice ? voice.panNow : null;
  const rightPan = w.current.pan ?? livePan ?? Math.min(Math.max(p.pan + lineValue(p.panPoints, p.inPoint), -1), 1);

  const beginPanWriting = () => {
    w.current.startPan = rightPan;
    w.current.lastPanTime = null;
    w.current.pan = rightPan;
    force(n => n + 1);
  };

  const rightPanChanged = (newPan: number) => {
    const s = w.current;
    s.pan = newPan;
    const q = pRef.current;
    const v = voiceRef.current;
    if (v) {
      const t = Math.round(v.position * 100) / 100;
      const value = Math.min(Math.max(newPan - q.pan, -1), 1);
      change(x => { x.panPoints = writeLinePoint(x, x.panPoints, Math.round(value * 100) / 100, t, s.lastPanTime); });
      s.lastPanTime = t;
    } else {
      const delta = newPan - s.startPan;
      s.startPan = newPan;
      change(x => {
        if (x.panPoints.length === 0) x.pan = Math.min(Math.max(x.pan + delta, -1), 1);
        else x.panPoints = x.panPoints.map(pt => ({ ...pt, db: Math.min(Math.max(pt.db + delta, -1), 1) }));
      });
    }
  };

  const endPanWriting = () => {
    if (w.current.lastPanTime !== null) change(x => { x.panPoints = simplifyPoints(x.panPoints, 0.02); });
    w.current.pan = null;
    w.current.lastPanTime = null;
    force(n => n + 1);
  };

  // 右のつまみを押さえている間は、動かさなくても再生位置に書き続ける（DAW の「タッチ」）
  const latest = useRef({ rightFaderChanged, rightPanChanged });
  latest.current = { rightFaderChanged, rightPanChanged };
  useEffect(() => {
    const id = setInterval(() => {
      if (w.current.db !== null && voiceRef.current) latest.current.rightFaderChanged(w.current.db);
      if (w.current.pan !== null && voiceRef.current) latest.current.rightPanChanged(w.current.pan);
    }, 100);
    return () => clearInterval(id);
  }, []);

  const activeFade: ActiveFade | null = voice && info && voice.fading && voice.fadeLength > 0.05
    ? { start: voice.position - voice.fadeElapsed, length: voice.fadeLength, from: voice.fadeFrom, to: voice.fadeTo, level: voice.level }
    : null;
  const writing = w.current.db !== null;
  const writingPan = w.current.pan !== null;
  const end = p.outPoint ?? duration;

  return (
    <div class="play-editor">
      <div class="hrow">
        <Icon name="wave" />
        <span class="ellipsis">{sound ? originalFileName(sound) : L("（音なし）")}</span>
        <span class="mono sub">{timeText(duration)}</span>
        {st?.state === "failed" && <span class="red">{st.reason}</span>}
        <span class="spacer" />
        <button class="btn" disabled={st?.state !== "ready"} onClick={() => preview(p)}>
          <Icon name={previewing ? "stop" : "play"} />{previewing ? L("試聴を止める") : L("試聴")}
        </button>
      </div>

      <fieldset class="group">
        <legend class="legend-row">
          <span>{L("再生範囲")}</span>
          <span class="spacer" />
          <ToggleButton on={lineMode === "volume"} icon="lineChart" onClick={() => setLineMode(lineMode === "volume" ? "none" : "volume")}
            title={L("曲の中で音量を変える線を、波形の上で編集します")}>{L("音量ライン")}</ToggleButton>
          <ToggleButton on={lineMode === "pan"} icon="leftRight" onClick={() => setLineMode(lineMode === "pan" ? "none" : "pan")}
            title={L("曲の中で左右を変える線を、波形の上で編集します")}>{L("PANライン")}</ToggleButton>
        </legend>
        {/* 左: PAN と基本の音量 ／ 真ん中: 波形とライン ／ 右: いまの音量（ラインに合わせて自動で動く） */}
        <div class="wave-row">
          <div class="strip" title={L("左右（PAN）と、この音の基本の音量。ダブルクリックで中央／0dB に戻す")}>
            <PanSlider value={p.pan} onChange={v => change(q => { q.pan = v; })} />
            <span class="caption mono">{signed(p.volumeDB)}</span>
            <Fader height={WAVE_HEIGHT - 44} value={p.volumeDB} onChange={v => change(q => { q.volumeDB = v; })} />
          </div>
          <div class="grow" style={{ minWidth: 0 }}>
            <Waveform peaks={info?.peaks ?? []} duration={duration} p={p} change={change}
              fadeOutAtEnd={p.fadeOutAtEnd && plays(p) !== null}
              playhead={playhead} activeFade={activeFade}
              onSeek={s => { if (voice) seek(voice.token, s); }}
              lineMode={lineMode} selectedPoint={selectedPoint} selectedSegment={selectedSegment}
              setSelection={(pt, seg) => { setSelectedPoint(pt); setSelectedSegment(seg); }}
              liveVolume={voice ? 20 * Math.log10(Math.max(voice.lineGain, 0.0001)) : null}
              livePan={voice ? voice.panNow - p.pan : null}
              height={WAVE_HEIGHT} />
          </div>
          <div class="strip" title={L("いまの左右と音量（基本 ＋ PANライン・音量ライン）。再生中はラインに合わせて動き、ドラッグするとその場のラインを書き込む。止まっているときはライン全体を動かす")}>
            <PanSlider value={rightPan} tint={livePan !== null || writingPan ? "#ffcc00" : undefined}
              onChange={rightPanChanged} onBegin={beginPanWriting} onEnd={endPanWriting} />
            <span class={"caption mono" + (liveDB !== null || writing ? " yellow" : "")}>{signed(rightDB)}</span>
            <Fader height={WAVE_HEIGHT - 44} value={rightDB} tint="#ffcc00" onChange={rightFaderChanged} onBegin={beginWriting} onEnd={endWriting} />
          </div>
        </div>
        {lineMode !== "none" && <LineControls p={p} pan={lineMode === "pan"} selectedPoint={selectedPoint}
          onDelete={deleteSelectedPoint}
          onClear={() => { change(q => { if (lineMode === "pan") q.panPoints = []; else q.volumePoints = []; }); setSelectedPoint(null); setSelectedSegment(null); }} />}
        <div class="hrow">
          <span class="nowrap">{L("開始")}</span>
          <SecondsField width={80} value={p.inPoint} onChange={v => change(q => { q.inPoint = Math.min(Math.max(0, v), (q.outPoint ?? duration) - 0.01); })} />
          <span class="mono sub nowrap">{timeText(p.inPoint)}</span>
          <span class="spacer" />
          <span class="nowrap">{L("終了")}</span>
          <SecondsField width={80} value={end} onChange={v => change(q => {
            const c = Math.min(Math.max(v, q.inPoint + 0.01), duration);
            if (c >= duration) delete q.outPoint; else q.outPoint = c;
          })} />
          <span class="mono sub nowrap">{timeText(end)}</span>
          <button class="btn" onClick={() => change(q => { q.inPoint = 0; delete q.outPoint; })}><Icon name="leftRight" />{L("全体に戻す")}</button>
        </div>
        <p class="caption sub">{L("緑（開始）と赤（終了）の線をドラッグして範囲を、上の端のオレンジの丸をドラッグしてフェードの長さを、白い四角をドラッグしてフェードの形（ベジエ曲線）を決めます（点線は止めたときのフェードアウト）。再生中は波形をクリックするとその位置へ移ります。長さ %@", timeText(end - p.inPoint))}</p>
      </fieldset>

      <fieldset class="group">
        <legend>{L("フェード（0秒 = カット）")}</legend>
        <FadeRow label={L("フェードイン")} value={p.fadeIn} onChange={v => change(q => { q.fadeIn = v; })} />
        <FadeRow label={L("フェードアウト")} value={p.fadeOut} onChange={v => change(q => { q.fadeOut = v; })} />
        <Toggle checked={p.fadeOutAtEnd} disabled={plays(p) === null} onChange={v => change(q => { q.fadeOutAtEnd = v; })}>
          {L("終了位置に向けて自動でフェードアウトする（長さは上と同じ）")}
        </Toggle>
        <div class="hrow">
          <span class="nowrap">{L("カーブ")}</span>
          <Segmented value={p.curve} options={curveOptions(true)} onChange={v => change(q => { q.curve = v; })} />
        </div>
      </fieldset>

      {/* 幅が狭くても文字が縦に折れないよう、リピートと音量は別の行にする */}
      <div class="hrow">
        <Toggle checked={p.loop} onChange={v => change(q => { q.loop = v; })}>{L("リピート（開始〜終了をくり返す）")}</Toggle>
        {p.loop && <>
          <Segmented value={p.loopCount > 0} options={[{ value: false, label: L("止めるまで") }, { value: true, label: L("回数を指定") }]}
            onChange={v => change(q => { q.loopCount = v ? Math.max(2, q.loopCount) : 0; })} />
          {p.loopCount > 0 && (
            <span class="stepper">
              <span class="mono">{L("%d 回鳴らす", p.loopCount)}</span>
              <button class="ibtn" onClick={() => change(q => { q.loopCount = Math.max(2, q.loopCount - 1); })}><Icon name="minus" size={12} /></button>
              <button class="ibtn" onClick={() => change(q => { q.loopCount = Math.min(99, q.loopCount + 1); })}><Icon name="plus" size={12} /></button>
            </span>
          )}
        </>}
      </div>
    </div>
  );
}

/** ラインの編集中に、波形の下に出す説明と操作 */
function LineControls({ p, pan, selectedPoint, onDelete, onClear }: { p: PlaySettings; pan: boolean; selectedPoint: Id | null; onDelete: () => void; onClear: () => void }) {
  const points = pan ? p.panPoints : p.volumePoints;
  const pt = points.find(x => x.id === selectedPoint);
  return (
    <>
      <div class="hrow">
        {pt && <>
          <span class="mono">{pan ? L("マーク %@ ／ %@", timeText(pt.time), panLabel(pt.db)) : L("マーク %@ ／ %@ dB", timeText(pt.time), signed(pt.db))}</span>
          <button class="btn danger" onClick={onDelete} title={L("Delete キーでも消せます")}><Icon name="minus" />{L("このマークを消す")}</button>
        </>}
        <span class="spacer" />
        <button class="btn danger" disabled={points.length === 0} onClick={onClear}><Icon name="trash" />{pan ? L("PANラインを消す") : L("音量ラインを消す")}</button>
      </div>
      <p class="caption sub">{pan
        ? L("ピンクの線が左右です（上が L、下が R、真ん中が中央）。左の PAN に足し合わせます。線をクリックでマークを足す、マークをドラッグで動かす、Alt+クリックか Delete キーで消す。マークとマークの間をクリックすると、白い四角でつなぎの形を変えられます。")
        : L("水色の線が音量です。線をクリックでマークを足す、マークをドラッグで動かす、Alt+クリックか Delete キーで消す。マークとマークの間をクリックすると、白い四角でつなぎの形（ベジエ曲線）を変えられます。フェードインは、最初のマークの音量まで上がります。")}</p>
    </>
  );
}

function FadeRow({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) {
  return (
    <div class="hrow">
      <span style={{ width: "190px" }}>{label}</span>
      <Slider value={value} min={0} max={20} onChange={onChange} />
      <SecondsField value={value} onChange={onChange} />
      <span>{L("秒")}</span>
      <span class="orange" style={{ width: "40px" }}>{value === 0 ? L("カット") : ""}</span>
    </div>
  );
}
