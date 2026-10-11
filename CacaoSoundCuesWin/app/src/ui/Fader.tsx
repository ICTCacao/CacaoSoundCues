// 縦の音量つまみと、左右（PAN）の小さな横スライダー（Mac 版 FaderView.swift）
import { useRef } from "preact/hooks";
import { panLabel } from "../model";
import { endEditing } from "../store";

const RANGE = [-40, 10] as const;
const MARKS = [6, 0, -10, -20, -40];

/** dB → 下からの割合（0〜1）。下の方ほど目盛りが詰まるよう、ゆるやかな曲線にする */
export function faderFraction(db: number) {
  const d = Math.min(Math.max(db, RANGE[0]), RANGE[1]);
  return Math.pow((d - RANGE[0]) / (RANGE[1] - RANGE[0]), 1.6);
}

export function faderDB(f: number) {
  const lin = Math.pow(Math.min(Math.max(f, 0), 1), 1 / 1.6);
  return Math.round((RANGE[0] + lin * (RANGE[1] - RANGE[0])) * 10) / 10;
}

export const FADER_RANGE = RANGE;

interface DragProps<T> {
  value: T;
  onChange: (v: T) => void;
  /** ドラッグを始めたとき・終えたとき（右のつまみでラインを記録するため） */
  onBegin?: () => void;
  onEnd?: () => void;
  tint?: string;
}

/** 縦の音量つまみ。ダブルクリックで 0dB */
export function Fader({ value, onChange, onBegin, onEnd, tint = "var(--accent)", height }: DragProps<number> & { height: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const pad = 8;
  const track = height - pad * 2;
  const y = pad + track * (1 - faderFraction(value));
  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    endEditing();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    onBegin?.();
    const set = (ev: PointerEvent) => {
      const box = ref.current!.getBoundingClientRect();
      onChange(faderDB(1 - (ev.clientY - box.top - pad) / Math.max(1, track)));
    };
    set(e);
    const el = e.currentTarget as HTMLElement;
    const move = (ev: PointerEvent) => set(ev);
    const up = () => { el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); onEnd?.(); };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
  };
  return (
    <div class="fader" ref={ref} style={{ height: `${height}px` }} onPointerDown={onPointerDown} onDblClick={() => onChange(0)}>
      {MARKS.map(m => {
        const my = pad + track * (1 - faderFraction(m));
        return (
          <div key={m}>
            <span class="fader-mark-label" style={{ top: `${my}px` }}>{m > 0 ? `+${m}` : `${m}`}</span>
            <span class="fader-mark" style={{ top: `${my}px`, width: m === 0 ? "10px" : "6px", opacity: m === 0 ? 0.8 : 0.4 }} />
          </div>
        );
      })}
      <div class="fader-track" style={{ top: `${pad}px`, height: `${track}px` }} />
      <div class="fader-knob" style={{ top: `${y}px`, borderColor: tint }}><div style={{ background: tint }} /></div>
    </div>
  );
}

/** 左右（PAN）の小さな横スライダー。ダブルクリックで中央 */
export function PanSlider({ value, onChange, onBegin, onEnd, tint = "var(--accent)" }: DragProps<number>) {
  const ref = useRef<HTMLDivElement>(null);
  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    endEditing();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    onBegin?.();
    const set = (ev: PointerEvent) => {
      const box = ref.current!.getBoundingClientRect();
      let v = ((ev.clientX - box.left - 5) / Math.max(1, box.width - 10)) * 2 - 1;
      v = Math.round(Math.min(Math.max(v, -1), 1) * 20) / 20;
      if (Math.abs(v) < 0.05) v = 0;   // 中央に吸い付く
      onChange(v);
    };
    set(e);
    const el = e.currentTarget as HTMLElement;
    const move = (ev: PointerEvent) => set(ev);
    const up = () => { el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); onEnd?.(); };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
  };
  return (
    <div class="pan">
      <div class="pan-track" ref={ref} onPointerDown={onPointerDown} onDblClick={() => onChange(0)}>
        <div class="pan-groove" />
        <div class="pan-center" />
        <div class="pan-knob" style={{ left: `calc(5px + ${(value + 1) / 2} * (100% - 10px))`, background: tint }} />
      </div>
      <div class="pan-label">{panLabel(value)}</div>
    </div>
  );
}
