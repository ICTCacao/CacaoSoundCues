// 画面のキーボード（Mac 版 KeyboardView.swift）
import { signal } from "@preact/signals";
import { useEffect, useRef, useState } from "preact/hooks";
import { L } from "../i18n";
import { timeText, type VoiceStatus } from "../model";
import { prefs } from "../prefs";
import {
  FUNCTION_ROW, KEYPAD_DECIMAL, KEYPAD_ROW123, KEYPAD_TOP_ROWS, KEYPAD_ZERO, ROW_INDENT, keyLabel, keyRows,
} from "../keymap";
import {
  chooseFileForKey, colorOf, cueForKey, dropTarget, endEditing, isRunning, isWaiting, loadStates, moveKey, playingOwner,
  removeCue, run, selectedSequenceID, selection, sequenceForKey, trigger,
} from "../store";
import { openMenu } from "./common";
import { Icon } from "./icons";

const MAX_KEY_WIDTH = 78;
const KEY_HEIGHT = 66;
const FUNCTION_KEY_HEIGHT = 40;
const SPACING = 5;
const KEYPAD_GAP = 22;

/** キーをドラッグして別のキーへ移している途中 */
const keyDrag = signal<{ from: number; over: number | null } | null>(null);

export function Keyboard() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(1200);
  useEffect(() => {
    const ro = new ResizeObserver(([e]) => setWidth(e.contentRect.width));
    ro.observe(ref.current!);
    return () => ro.disconnect();
  }, []);
  const showFn = prefs.showFunctionKeys.value;
  const showPad = prefs.showKeypad.value;
  // 横幅に収まるようにキーの大きさを決める（メイン 13 キー分 + テンキー 4 キー分）
  const columns = 13 + (showPad ? 4 : 0);
  const fixed = SPACING * (columns - 1) + (showPad ? KEYPAD_GAP : 0) + 40;
  const kw = Math.min(MAX_KEY_WIDTH, Math.max(44, (width - fixed) / columns));
  const mainHeight = KEY_HEIGHT * 4 + SPACING * 3;
  const padH = (mainHeight - SPACING * 4) / 5;

  return (
    <div class="keyboard" ref={ref}>
      {showFn && (
        <div class="krow" style={{ marginBottom: `${SPACING}px` }}>
          {FUNCTION_ROW.map(c => <KeyCap key={c} code={c} w={kw} h={FUNCTION_KEY_HEIGHT} />)}
        </div>
      )}
      <div class="kmain" style={{ gap: `${KEYPAD_GAP}px` }}>
        <div class="kcol">
          {keyRows().map((row, i) => (
            <div key={i} class="krow" style={{ paddingLeft: `${ROW_INDENT[i] * kw}px` }}>
              {row.map(c => <KeyCap key={c} code={c} w={kw} h={KEY_HEIGHT} />)}
            </div>
          ))}
        </div>
        {showPad && (
          <div class="kcol">
            {KEYPAD_TOP_ROWS.map((row, i) => (
              <div key={i} class="krow">{row.map(c => <KeyCap key={c} code={c} w={kw} h={padH} />)}</div>
            ))}
            <div class="krow" style={{ alignItems: "flex-start" }}>
              <div class="kcol">
                <div class="krow">{KEYPAD_ROW123.map(c => <KeyCap key={c} code={c} w={kw} h={padH} />)}</div>
                <div class="krow">
                  <KeyCap code={KEYPAD_ZERO} w={kw * 2 + SPACING} h={padH} />
                  <KeyCap code={KEYPAD_DECIMAL} w={kw} h={padH} />
                </div>
              </div>
              <div class="key enter" style={{ width: `${kw}px`, height: `${padH * 2 + SPACING}px` }}
                title={L("テンキーの enter は Enter と同じ「リストの次の曲へ」です（割り当てはできません）")}>
                <div class="label">enter</div>
                <div class="name">{L("次の曲へ")}</div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function progress(v: VoiceStatus) {
  return Math.min(1, Math.max(0, (v.position - v.start) / Math.max(0.001, v.end - v.start)));
}

function KeyCap({ code, w, h }: { code: number; w: number; h: number }) {
  const cue = cueForKey(code);
  const seq = sequenceForKey(code);
  const voice = cue ? playingOwner(cue.id) : undefined;
  const seqRunning = seq ? isRunning(seq.id) : false;
  const lit = !!voice || seqRunning;
  const sel = selection.value;
  const selected = sel.kind === "key" && sel.code === code;
  const drag = keyDrag.value;
  const targeted = dropTarget.value === `key:${code}` || (drag !== null && drag.over === code && drag.from !== code);
  const st = cue ? loadStates.value[cue.play.soundID] : undefined;
  const color = cue ? colorOf(cue.colorIndex) : seq ? "#5856d6" : null;
  const bg = color ? color + (lit ? "f2" : "59") : undefined;
  const showMode = prefs.showMode.value;

  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    endEditing();
    const x0 = e.clientX, y0 = e.clientY;
    let moving = false;
    const assigned = !!(cue || seq) && !showMode;
    const move = (ev: PointerEvent) => {
      if (!assigned) return;
      if (!moving && Math.hypot(ev.clientX - x0, ev.clientY - y0) < 6) return;
      moving = true;
      const el = document.elementFromPoint(ev.clientX, ev.clientY)?.closest<HTMLElement>("[data-key]");
      keyDrag.value = { from: code, over: el ? Number(el.dataset.key) : null };
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      const d = keyDrag.peek();
      keyDrag.value = null;
      if (moving) {
        if (d?.over != null && d.over !== code) moveKey(code, d.over);
        return;
      }
      selection.value = { kind: "key", code };
      if (seq) selectedSequenceID.value = seq.id;
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const onContextMenu = (e: MouseEvent) => {
    const items = [];
    if (cue) items.push({ label: L("鳴らす／止める"), icon: "playPause", action: () => trigger(cue) });
    if (!showMode) {
      items.push({ label: L("音ファイルを割り当てる…"), icon: "folder", action: () => chooseFileForKey(code) });
      if (cue) items.push({ label: L("割り当てを外す"), icon: "xCircle", danger: true, action: () => removeCue(code) });
    }
    openMenu(e, items);
  };

  return (
    <div class={"key" + (selected ? " selected" : "") + (targeted ? " targeted" : "") + (lit ? " lit" : "")}
      data-key={code} data-drop={`key:${code}`}
      style={{ width: `${w}px`, height: `${h}px`, background: bg }}
      onPointerDown={onPointerDown} onContextMenu={onContextMenu}
      title={cue ? `${cue.name}` : L("音ファイルをドラッグして割り当て。割り当て済みのキーはドラッグで別のキーへ移せます")}>
      <div class="khead">
        <span class="label">{keyLabel(code)}</span>
        <span class="kicons">
          {st?.state === "failed" && <span class="warn"><Icon name="warning" size={12} /></span>}
          {st?.state === "loading" && <span class="spinner" />}
          {cue?.play.loop && <Icon name="repeat" size={11} />}
        </span>
      </div>
      <div class="name" style={{ WebkitLineClamp: h < 56 ? 1 : 2 }}>{cue?.name ?? (seq ? "≡ " + seq.name : "")}</div>
      {voice && (
        <div class="kfoot">
          <div class="bar"><div style={{ width: `${progress(voice) * 100}%`, background: voice.stopping ? "orange" : "#fff" }} /></div>
          <div class="time">{voice.looping ? "∞" : "-" + timeText(voice.remaining)}</div>
        </div>
      )}
      {!voice && seqRunning && (
        <div class="kfoot"><div class="time">{run.value && isWaiting(run.value) ? L("Enter 待ち") : L("再生中")}</div></div>
      )}
    </div>
  );
}

/** キーの文字を色付きの角丸で表示（鳴っている間は明るく） */
export function KeyBadge({ code, color, lit }: { code: number; color: string; lit?: boolean }) {
  return <span class="keybadge" style={{ background: color + (lit ? "f2" : "66") }}>{keyLabel(code)}</span>;
}
