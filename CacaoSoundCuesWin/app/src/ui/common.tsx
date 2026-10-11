// いくつもの画面で使う小さな部品（秒の入力欄・スライダー・右クリックのメニュー・分割画面など）
import { signal, type Signal } from "@preact/signals";
import { useEffect, useRef, useState } from "preact/hooks";
import { Fragment, type ComponentChildren } from "preact";
import { L } from "../i18n";
import { Icon } from "./icons";
import { endEditing } from "../store";

/** 秒の入力欄（Enter か、ほかを押したときに確定） */
export function SecondsField({ value, onChange, width = 60, disabled }: { value: number; onChange: (v: number) => void; width?: number; disabled?: boolean }) {
  const [text, setText] = useState<string | null>(null);
  const shown = text ?? String(Math.round(value * 100) / 100);
  const commit = () => {
    if (text === null) return;
    const v = parseFloat(text.replace(",", "."));
    if (!isNaN(v)) onChange(Math.max(0, v));
    setText(null);
  };
  return (
    <input class="num" style={{ width: `${width}px` }} value={shown} disabled={disabled}
      onInput={e => setText((e.target as HTMLInputElement).value)}
      onBlur={commit}
      onKeyDown={e => { if (e.key === "Enter") { commit(); endEditing(); } }} />
  );
}

/** 横のスライダー（unit 刻みに丸める） */
export function Slider({ value, min, max, unit = 0.1, onChange, disabled }: { value: number; min: number; max: number; unit?: number; onChange: (v: number) => void; disabled?: boolean }) {
  return (
    <input type="range" class="slider" min={min} max={max} step={unit} value={value} disabled={disabled}
      onInput={e => onChange(Math.round(parseFloat((e.target as HTMLInputElement).value) / unit) * unit)} />
  );
}

export function Toggle({ checked, onChange, children, disabled, title }: { checked: boolean; onChange: (v: boolean) => void; children: ComponentChildren; disabled?: boolean; title?: string }) {
  return (
    <label class={"toggle" + (disabled ? " disabled" : "")} title={title}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={e => onChange((e.target as HTMLInputElement).checked)} />
      <span>{children}</span>
    </label>
  );
}

/** ボタンの形の ON/OFF（Mac の .toggleStyle(.button)） */
export function ToggleButton({ on, onClick, icon, children, title }: { on: boolean; onClick: () => void; icon?: string; children?: ComponentChildren; title?: string }) {
  return (
    <button class={"btn" + (on ? " on" : "")} onClick={onClick} title={title}>
      {icon && <Icon name={icon} />}{children}
    </button>
  );
}

/** 選ぶボタンが並んだもの（Mac の segmented） */
export function Segmented<T extends string | boolean>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <div class="segmented">
      {options.map(o => (
        <button key={String(o.value)} class={o.value === value ? "on" : ""} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

export function Select<T extends string>({ value, options, onChange, disabled }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; disabled?: boolean }) {
  return (
    <select value={value} disabled={disabled} onChange={e => { onChange((e.target as HTMLSelectElement).value as T); endEditing(); }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  );
}

/** 「space 今の曲を途中で終える」のような操作の案内 */
export function KeyHint({ k, text }: { k: string; text: string }) {
  return <span class="keyhint"><kbd>{k}</kbd>{text}</span>;
}

// MARK: - 右クリックのメニュー

export interface MenuItem { label: string; icon?: string; danger?: boolean; action?: () => void; submenu?: MenuItem[] }
export const contextMenu = signal<{ x: number; y: number; items: MenuItem[] } | null>(null);

export function openMenu(e: MouseEvent, items: MenuItem[]) {
  e.preventDefault();
  e.stopPropagation();
  if (items.length === 0) return;
  contextMenu.value = { x: e.clientX, y: e.clientY, items };
}

export function ContextMenuView() {
  const m = contextMenu.value;
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  useEffect(() => {
    if (!m || !ref.current) { setPos(null); return; }
    const r = ref.current.getBoundingClientRect();
    setPos({ x: Math.min(m.x, window.innerWidth - r.width - 4), y: Math.min(m.y, window.innerHeight - r.height - 4) });
  }, [m]);
  if (!m) return null;
  const close = () => { contextMenu.value = null; };
  const render = (items: MenuItem[]) => items.map((it, i) => it.submenu ? (
    <div key={i} class="menu-item has-sub">
      {it.icon && <Icon name={it.icon} />}<span>{it.label}</span><span class="chev">›</span>
      <div class="menu sub">{render(it.submenu)}</div>
    </div>
  ) : (
    <div key={i} class={"menu-item" + (it.danger ? " danger" : "")} onClick={() => { close(); it.action?.(); }}>
      {it.icon && <Icon name={it.icon} />}<span>{it.label}</span>
    </div>
  ));
  return (
    <div class="menu-backdrop" onMouseDown={close} onContextMenu={e => { e.preventDefault(); close(); }}>
      <div ref={ref} class="menu" style={{ left: `${(pos ?? m).x}px`, top: `${(pos ?? m).y}px`, visibility: pos ? "visible" : "hidden" }}
        onMouseDown={e => e.stopPropagation()}>
        {render(m.items)}
      </div>
    </div>
  );
}

// MARK: - 分割画面（仕切りの位置を割合で覚える）

export function Split({ fractions, mins, children }: { fractions: Signal<number[]>; mins: number[]; children: ComponentChildren[] }) {
  const ref = useRef<HTMLDivElement>(null);
  const n = children.length;
  let f = fractions.value;
  if (f.length !== n - 1) f = Array.from({ length: n - 1 }, (_, i) => (i + 1) / n);
  const edges = [0, ...f, 1];
  const drag = (i: number) => (e: PointerEvent) => {
    e.preventDefault();
    const box = ref.current!.getBoundingClientRect();
    const move = (ev: PointerEvent) => {
      const x = (ev.clientX - box.left) / box.width;
      const next = [...edges];
      const lo = next[i] + mins[i] / box.width;
      const hi = next[i + 2] - mins[i + 1] / box.width;
      next[i + 1] = Math.min(Math.max(x, lo), hi);
      fractions.value = next.slice(1, -1);
    };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return (
    <div class="split" ref={ref}>
      {children.map((c, i) => (
        <Fragment key={i}>
          <div class="split-pane" style={{ flexBasis: `${(edges[i + 1] - edges[i]) * 100}%`, minWidth: `${mins[i]}px` }}>{c}</div>
          {i < n - 1 && <div class="split-divider" onPointerDown={drag(i)} />}
        </Fragment>
      ))}
    </div>
  );
}

/** 行をドラッグして並べ替える。行には data-row（番号）を付ける */
export function useReorder(onMove: (from: number, to: number) => void, disabled: boolean) {
  const [state, setState] = useState<{ from: number; to: number } | null>(null);
  const start = (index: number) => (e: PointerEvent) => {
    if (disabled || e.button !== 0) return;
    const y0 = e.clientY;
    let moving = false;
    let to = index;
    const container = (e.currentTarget as HTMLElement).parentElement!;
    const move = (ev: PointerEvent) => {
      if (!moving && Math.abs(ev.clientY - y0) < 6) return;
      moving = true;
      const rows = [...container.querySelectorAll<HTMLElement>("[data-row]")];
      to = rows.length;
      for (const r of rows) {
        const b = r.getBoundingClientRect();
        if (ev.clientY < b.top + b.height / 2) { to = Number(r.dataset.row); break; }
      }
      setState({ from: index, to });
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      setState(null);
      if (moving && to !== index && to !== index + 1) onMove(index, to);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return { start, state };
}

export const cutLabel = (v: number) => (v === 0 ? L("カット") : "");
