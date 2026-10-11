// 波形と再生範囲・フェード・音量ライン・PANライン（Mac 版 WaveformView.swift ＋ VolumeLineView.swift）。
// 1枚のキャンバスに描き、ラインの編集中はラインの操作、それ以外は範囲・フェードの操作を受け取る
import { useEffect, useRef, useState } from "preact/hooks";
import { L } from "../i18n";
import {
  DEFAULT_LINE_SHAPE, MAX_DB, MIN_DB, fadeShape, lineValue, newId, presetBezier, settingsBezier,
  type FadeBezier, type Id, type PlaySettings, type VolumePoint,
} from "../model";
import { endEditing } from "../store";

export type LineMode = "none" | "volume" | "pan";

interface LineKind { min: number; max: number; step: number; color: string; topIsMin: boolean }
const VOLUME: LineKind = { min: MIN_DB, max: MAX_DB, step: 0.1, color: "#59c7fa", topIsMin: false };
const PAN: LineKind = { min: -1, max: 1, step: 0.01, color: "#ff7ad1", topIsMin: true };

export interface ActiveFade { start: number; length: number; from: number; to: number; level: number }

export interface WaveformProps {
  peaks: number[];
  duration: number;
  p: PlaySettings;
  /** 設定を書き換える */
  change: (fn: (p: PlaySettings) => void) => void;
  fadeOutAtEnd: boolean;
  playhead: number | null;
  activeFade: ActiveFade | null;
  onSeek: (seconds: number) => void;
  lineMode: LineMode;
  selectedPoint: Id | null;
  selectedSegment: number | null;
  setSelection: (point: Id | null, segment: number | null) => void;
  /** 再生中のいまの値（音量ラインなら dB、PANラインなら -1〜1） */
  liveVolume: number | null;
  livePan: number | null;
  height: number;
}

/** 波形の背景（カカオ色） */
const CACAO = "#6b4430";
const HANDLE_BAND = 24;
const GRAB = 10;

type Marker =
  | { kind: "start" } | { kind: "end" } | { kind: "fadeIn" } | { kind: "fadeOut" } | { kind: "seek" }
  | { kind: "bezier"; rising: boolean; second: boolean };

type LineTarget = { kind: "point"; index: number } | { kind: "handle"; segment: number; second: boolean };

export function Waveform(props: WaveformProps) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [width, setWidth] = useState(600);
  const peaksCache = useRef<{ key: unknown; w: number; h: number; img: HTMLCanvasElement } | null>(null);
  // 操作中の状態（描き直しても消えないように）
  const drag = useRef<{ marker?: Marker; line?: LineTarget; moved: boolean; x0: number; y0: number } | null>(null);
  const propsRef = useRef(props);
  propsRef.current = props;

  useEffect(() => {
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(10, Math.floor(e.contentRect.width))));
    ro.observe(canvas.current!.parentElement!);
    return () => ro.disconnect();
  }, []);

  const h = props.height;
  const w = width;

  useEffect(() => draw(canvas.current!, w, h, props, peaksCache));

  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0) return;
    endEditing();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const x = e.offsetX, y = e.offsetY;
    drag.current = { moved: false, x0: x, y0: y };
    const pr = propsRef.current;
    if (pr.lineMode !== "none") {
      linePick(pr, x, y, w, h, drag.current);
    } else {
      waveformPick(pr, x, y, w, h, drag.current);
      waveformMove(pr, x, y, w, h, drag.current);
    }
  };
  const onPointerMove = (e: PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const pr = propsRef.current;
    const x = e.offsetX, y = e.offsetY;
    if (pr.lineMode !== "none") {
      if (Math.hypot(x - d.x0, y - d.y0) > 3) d.moved = true;
      if (d.moved && d.line) lineMove(pr, d.line, x, y, w, h);
    } else {
      d.moved = true;
      waveformMove(pr, x, y, w, h, d);
    }
  };
  const onPointerUp = (e: PointerEvent) => {
    const d = drag.current;
    drag.current = null;
    if (!d) return;
    const pr = propsRef.current;
    if (pr.lineMode !== "none") {
      if (!d.moved) lineClick(pr, e.offsetX, e.offsetY, w, h, e.altKey);
    } else if (d.marker?.kind === "seek" && pr.playhead !== null && pr.duration > 0) {
      pr.onSeek(Math.min(Math.max(0, (e.offsetX / w) * pr.duration), pr.duration));
    }
  };

  return (
    <div class="waveform" style={{ height: `${h}px` }}>
      <canvas ref={canvas} onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp}
        onPointerCancel={() => { drag.current = null; }} />
    </div>
  );
}

// MARK: - 座標

const xOf = (t: number, duration: number, w: number) => (duration > 0 ? (t / duration) * w : 0);
const tOf = (x: number, duration: number, w: number) => Math.min(Math.max(0, (x / Math.max(1, w)) * duration), duration);
function yOfLine(k: LineKind, v: number, h: number) {
  const u = (v - k.min) / (k.max - k.min);
  return (k.topIsMin ? u : 1 - u) * h;
}
function valueOfLine(k: LineKind, y: number, h: number) {
  const u = y / Math.max(1, h);
  const v = k.min + (k.topIsMin ? u : 1 - u) * (k.max - k.min);
  return Math.round(Math.min(Math.max(v, k.min), k.max) / k.step) * k.step;
}

// MARK: - 範囲・フェードの操作（ラインを編集していないとき）

function handleX(p: PlaySettings, duration: number, isIn: boolean, xIn: number, xOut: number, w: number) {
  if (duration <= 0) return 0;
  const len = (p.outPoint ?? duration) - p.inPoint;
  const px = (Math.min(isIn ? p.fadeIn : p.fadeOut, len) / duration) * w;
  return isIn ? xIn + px : xOut - px;
}

/** フェードの区間と、ベジエの端点・制御点の位置。区間が狭すぎるときは null */
function bezierGeometry(p: PlaySettings, duration: number, rising: boolean, xIn: number, xOut: number, w: number, h: number) {
  if (duration <= 0) return null;
  const len = (p.outPoint ?? duration) - p.inPoint;
  const secs = Math.min(rising ? p.fadeIn : p.fadeOut, len);
  const fw = (secs / duration) * w;
  if (fw < 24) return null;
  const rx = rising ? xIn : xOut - fw;
  const b = settingsBezier(p, rising);
  const pt = (x: number, y: number) => ({ x: rx + x * fw, y: h * (1 - y) });
  return { rx, fw, p0: pt(0, rising ? 0 : 1), c1: pt(b.x1, b.y1), c2: pt(b.x2, b.y2), p3: pt(1, rising ? 1 : 0) };
}

function waveformPick(pr: WaveformProps, x: number, y: number, w: number, h: number, d: { marker?: Marker }) {
  const { p, duration } = pr;
  if (duration <= 0 || w <= 0) return;
  const xIn = xOf(p.inPoint, duration, w), xOut = xOf(p.outPoint ?? duration, duration, w);
  if (y <= HANDLE_BAND) {
    // 上端ではフェードの丸を優先してつかむ
    const hIn = Math.abs(x - handleX(p, duration, true, xIn, xOut, w));
    const hOut = Math.abs(x - handleX(p, duration, false, xIn, xOut, w));
    if (Math.min(hIn, hOut) <= GRAB + 4) { d.marker = { kind: hIn <= hOut ? "fadeIn" : "fadeOut" }; return; }
  }
  // ベジエの制御点
  let best: [Marker, number] | null = null;
  for (const rising of [true, false]) {
    const g = bezierGeometry(p, duration, rising, xIn, xOut, w, h);
    if (!g) continue;
    for (const [second, c] of [[false, g.c1], [true, g.c2]] as const) {
      const dd = Math.hypot(x - c.x, y - c.y);
      if (dd <= GRAB && dd < (best?.[1] ?? Infinity)) best = [{ kind: "bezier", rising, second }, dd];
    }
  }
  if (best) {
    d.marker = best[0];
    // 決まった形からカスタムに切り替えるときは、今の形から始める
    if (p.curve !== "custom") {
      pr.change(q => {
        q.fadeInBezier = presetBezier(q.curve, true);
        q.fadeOutBezier = presetBezier(q.curve, false);
        q.curve = "custom";
      });
    }
    return;
  }
  const dIn = Math.abs(x - xIn), dOut = Math.abs(x - xOut);
  d.marker = Math.min(dIn, dOut) <= GRAB ? { kind: dIn <= dOut ? "start" : "end" } : { kind: "seek" };
}

function waveformMove(pr: WaveformProps, x: number, y: number, w: number, h: number, d: { marker?: Marker }) {
  const { duration } = pr;
  const m = d.marker;
  if (!m || duration <= 0) return;
  const t = tOf(x, duration, w);
  switch (m.kind) {
    case "start": pr.change(q => { q.inPoint = Math.min(t, (q.outPoint ?? duration) - 0.01); }); break;
    case "end": pr.change(q => {
      const v = Math.max(t, q.inPoint + 0.01);
      if (v >= duration - 0.005) delete q.outPoint; else q.outPoint = v;
    }); break;
    case "fadeIn": pr.change(q => {
      const len = (q.outPoint ?? duration) - q.inPoint;
      q.fadeIn = Math.round(Math.min(Math.max(0, t - q.inPoint), len) * 10) / 10;
    }); break;
    case "fadeOut": pr.change(q => {
      const end = q.outPoint ?? duration;
      q.fadeOut = Math.round(Math.min(Math.max(0, end - t), end - q.inPoint) * 10) / 10;
    }); break;
    case "bezier": {
      const p = pr.p;
      const xIn = xOf(p.inPoint, duration, w), xOut = xOf(p.outPoint ?? duration, duration, w);
      const g = bezierGeometry(p, duration, m.rising, xIn, xOut, w, h);
      if (!g) break;
      const nx = Math.min(Math.max((x - g.rx) / Math.max(1, g.fw), 0), 1);
      const ny = Math.min(Math.max((h - y) / h, 0), 1);
      pr.change(q => {
        const b: FadeBezier = { ...((m.rising ? q.fadeInBezier : q.fadeOutBezier) ?? presetBezier("equalPower", m.rising)) };
        if (m.second) { b.x2 = nx; b.y2 = ny; } else { b.x1 = nx; b.y1 = ny; }
        if (m.rising) q.fadeInBezier = b; else q.fadeOutBezier = b;
      });
      break;
    }
  }
}

// MARK: - ラインの操作（音量ライン・PANライン の編集中）

function lineOf(pr: WaveformProps): [LineKind, VolumePoint[], "volumePoints" | "panPoints"] {
  return pr.lineMode === "pan" ? [PAN, pr.p.panPoints, "panPoints"] : [VOLUME, pr.p.volumePoints, "volumePoints"];
}

function segmentHandles(k: LineKind, points: VolumePoint[], seg: number, duration: number, w: number, h: number) {
  if (seg < 0 || seg + 1 >= points.length) return null;
  const a = points[seg], b = points[seg + 1];
  const s = a.shape ?? DEFAULT_LINE_SHAPE;
  const ax = xOf(a.time, duration, w), bx = xOf(b.time, duration, w);
  const ay = yOfLine(k, a.db, h), by = yOfLine(k, b.db, h);
  const pt = (u: number, v: number) => ({ x: ax + u * (bx - ax), y: ay + v * (by - ay) });
  return { p0: { x: ax, y: ay }, c1: pt(s.x1, s.y1), c2: pt(s.x2, s.y2), p3: { x: bx, y: by } };
}

function nearestPoint(k: LineKind, points: VolumePoint[], x: number, y: number, duration: number, w: number, h: number) {
  let best: [number, number] | null = null;
  points.forEach((p, i) => {
    const d = Math.hypot(x - xOf(p.time, duration, w), y - yOfLine(k, p.db, h));
    if (d <= GRAB && d < (best?.[1] ?? Infinity)) best = [i, d];
  });
  return best ? (best as [number, number])[0] : null;
}

function linePick(pr: WaveformProps, x: number, y: number, w: number, h: number, d: { line?: LineTarget }) {
  const [k, points] = lineOf(pr);
  if (pr.selectedSegment !== null) {
    const g = segmentHandles(k, points, pr.selectedSegment, pr.duration, w, h);
    if (g) {
      if (Math.hypot(x - g.c1.x, y - g.c1.y) <= GRAB) { d.line = { kind: "handle", segment: pr.selectedSegment, second: false }; return; }
      if (Math.hypot(x - g.c2.x, y - g.c2.y) <= GRAB) { d.line = { kind: "handle", segment: pr.selectedSegment, second: true }; return; }
    }
  }
  const i = nearestPoint(k, points, x, y, pr.duration, w, h);
  if (i !== null) {
    d.line = { kind: "point", index: i };
    pr.setSelection(points[i].id, pr.selectedSegment);
  }
}

function lineMove(pr: WaveformProps, target: LineTarget, x: number, y: number, w: number, h: number) {
  const [k, , field] = lineOf(pr);
  const duration = pr.duration;
  pr.change(q => {
    const points = q[field];
    if (target.kind === "point") {
      const i = target.index;
      if (i < 0 || i >= points.length) return;
      const lo = i > 0 ? points[i - 1].time + 0.01 : 0;
      const hi = i + 1 < points.length ? points[i + 1].time - 0.01 : duration;
      points[i] = { ...points[i], time: Math.round(Math.min(Math.max(tOf(x, duration, w), lo), hi) * 100) / 100, db: valueOfLine(k, y, h) };
    } else {
      const s = target.segment;
      if (s + 1 >= points.length) return;
      const a = points[s], b = points[s + 1];
      const ax = xOf(a.time, duration, w), bx = xOf(b.time, duration, w);
      const ay = yOfLine(k, a.db, h), by = yOfLine(k, b.db, h);
      if (bx - ax <= 1 || Math.abs(by - ay) <= 1) return;
      const u = Math.min(Math.max((x - ax) / (bx - ax), 0), 1);
      const v = Math.min(Math.max((y - ay) / (by - ay), 0), 1);
      const shape = { ...(a.shape ?? DEFAULT_LINE_SHAPE) };
      if (target.second) { shape.x2 = u; shape.y2 = v; } else { shape.x1 = u; shape.y1 = v; }
      points[s] = { ...a, shape };
    }
  });
}

function lineClick(pr: WaveformProps, x: number, y: number, w: number, h: number, alt: boolean) {
  const [k, points, field] = lineOf(pr);
  const duration = pr.duration;
  // Alt+クリックで点を消す
  if (alt) {
    const i = nearestPoint(k, points, x, y, duration, w, h);
    if (i !== null) {
      pr.change(q => { q[field] = q[field].filter((_, j) => j !== i); });
      pr.setSelection(null, null);
    }
    return;
  }
  const i = nearestPoint(k, points, x, y, duration, w, h);
  if (i !== null) { pr.setSelection(points[i].id, pr.selectedSegment); return; }
  const time = tOf(x, duration, w);
  const lineY = yOfLine(k, lineValue(points, time), h);
  if (Math.abs(y - lineY) <= 14 || points.length === 0) {
    // 線の上（または最初の1点）なら点を足す
    const pt: VolumePoint = { id: newId(), time: Math.round(time * 100) / 100, db: points.length === 0 ? valueOfLine(k, y, h) : lineValue(points, time) };
    pr.change(q => { q[field] = [...q[field], pt].sort((a, b) => a.time - b.time); });
    pr.setSelection(pt.id, null);
  } else {
    // 点と点の間をクリック → その区間を選ぶ（白い四角でつなぎの形を変えられる）
    let last = -1;
    points.forEach((p, j) => { if (p.time <= time) last = j; });
    pr.setSelection(null, last >= 0 && last + 1 < points.length ? last : null);
  }
}

// MARK: - 描画

function draw(cv: HTMLCanvasElement, w: number, h: number, pr: WaveformProps,
  cache: { current: { key: unknown; w: number; h: number; img: HTMLCanvasElement } | null }) {
  const dpr = window.devicePixelRatio || 1;
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
    cv.width = Math.round(w * dpr);
    cv.height = Math.round(h * dpr);
    cv.style.width = `${w}px`;
    cv.style.height = `${h}px`;
  }
  const ctx = cv.getContext("2d")!;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  const { p, duration, peaks } = pr;

  // 背景（角丸）
  ctx.save();
  roundRect(ctx, 0, 0, w, h, 4);
  ctx.clip();
  ctx.fillStyle = CACAO;
  ctx.fillRect(0, 0, w, h);

  // 波形（大きさが変わったときだけ作り直す）
  if (peaks.length > 0) {
    let c = cache.current;
    if (!c || c.key !== peaks || c.w !== w || c.h !== h) {
      const img = document.createElement("canvas");
      img.width = Math.round(w * dpr);
      img.height = Math.round(h * dpr);
      const g = img.getContext("2d")!;
      g.scale(dpr, dpr);
      g.fillStyle = "rgba(255,255,255,0.92)";
      const mid = h / 2;
      const cols = Math.floor(w);
      for (let col = 0; col < cols; col++) {
        const a = Math.floor((col * peaks.length) / cols);
        const b = Math.max(a + 1, Math.floor(((col + 1) * peaks.length) / cols));
        let m = 0;
        for (let k = a; k < Math.min(b, peaks.length); k++) m = Math.max(m, peaks[k]);
        const hh = Math.max(0.5, Math.min(1, m) * mid);
        g.fillRect(col, mid - hh, 1, hh * 2);
      }
      c = cache.current = { key: peaks, w, h, img };
    }
    ctx.drawImage(c.img, 0, 0, w, h);
  }
  if (duration <= 0) { ctx.restore(); return; }

  const xIn = xOf(p.inPoint, duration, w);
  const xOut = xOf(p.outPoint ?? duration, duration, w);
  ctx.fillStyle = "rgba(0,0,0,0.5)";
  ctx.fillRect(0, 0, Math.max(0, xIn), h);
  ctx.fillRect(xOut, 0, Math.max(0, w - xOut), h);

  // フェードの形（音量のカーブ）。線より上の、音量が下がっている所をうすく塗る
  const start = p.inPoint, end = p.outPoint ?? duration;
  const len = Math.max(0.001, end - start);
  const fi = Math.min(p.fadeIn, len), fo = pr.fadeOutAtEnd ? Math.min(p.fadeOut, len) : 0;
  const gain = (t: number) => {
    let g = 1;
    if (fi > 0 && t < start + fi) g = Math.min(g, fadeShape(p, (t - start) / fi, true));
    if (fo > 0 && t > end - fo) g = Math.min(g, fadeShape(p, (t - (end - fo)) / fo, false));
    return g;
  };
  const steps = Math.max(2, Math.floor(xOut - xIn));
  const line = new Path2D();
  const shade = new Path2D();
  shade.moveTo(xIn, 0);
  for (let i = 0; i <= steps; i++) {
    const px = xIn + ((xOut - xIn) * i) / steps;
    const y = h * (1 - gain((px / w) * duration));
    if (i === 0) line.moveTo(px, y); else line.lineTo(px, y);
    shade.lineTo(px, y);
  }
  shade.lineTo(xOut, 0);
  shade.closePath();
  ctx.fillStyle = "rgba(255,149,0,0.28)";
  ctx.fill(shade);
  ctx.strokeStyle = "#ff9500";
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  ctx.stroke(line);

  // 自動フェードアウトが OFF のときは、止めたときのフェードアウトの長さを点線で示す
  if (!pr.fadeOutAtEnd && p.fadeOut > 0) {
    const f = Math.min(p.fadeOut, len);
    const x0 = xOut - (f / duration) * w;
    const n = Math.max(2, Math.floor(xOut - x0));
    ctx.beginPath();
    for (let i = 0; i <= n; i++) {
      const px = x0 + ((xOut - x0) * i) / n;
      const y = h * (1 - fadeShape(p, i / n, false));
      if (i === 0) ctx.moveTo(px, y); else ctx.lineTo(px, y);
    }
    ctx.setLineDash([5, 4]);
    ctx.strokeStyle = "rgba(255,149,0,0.9)";
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // ベジエの制御点（白い四角）と、端点から伸びる腕（ラインの編集中は出さない）
  if (pr.lineMode === "none") {
    for (const rising of [true, false]) {
      const g = bezierGeometry(p, duration, rising, xIn, xOut, w, h);
      if (!g) continue;
      ctx.beginPath();
      ctx.moveTo(g.p0.x, g.p0.y); ctx.lineTo(g.c1.x, g.c1.y);
      ctx.moveTo(g.p3.x, g.p3.y); ctx.lineTo(g.c2.x, g.c2.y);
      ctx.strokeStyle = "rgba(255,255,255,0.7)";
      ctx.lineWidth = 1;
      ctx.stroke();
      for (const c of [g.c1, g.c2]) square(ctx, c.x, c.y, "#fff", "#ff9500");
    }
    // フェードの長さを変える丸（上端）
    for (const hx of [handleX(p, duration, true, xIn, xOut, w), handleX(p, duration, false, xIn, xOut, w)]) {
      circle(ctx, hx, 8, 7, "#ff9500", "#fff", 1.5);
    }
  }

  // 開始（緑）と終了（赤）
  ctx.fillStyle = "#34c759";
  ctx.fillRect(xIn - 1, 0, 2, h);
  ctx.fillStyle = "#ff3b30";
  ctx.fillRect(xOut - 1, 0, 2, h);

  // いま進んでいるフェード
  const f = pr.activeFade;
  if (f && pr.playhead !== null) {
    const rising = f.to > f.from;
    ctx.beginPath();
    for (let i = 0; i <= 60; i++) {
      const q = i / 60;
      const s = rising ? fadeShape(p, q, true) : 1 - fadeShape(p, q, false);
      const g = f.from + (f.to - f.from) * s;
      const x = xOf(f.start + f.length * q, duration, w), y = h * (1 - Math.min(Math.max(g, 0), 1));
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.save();
    ctx.shadowColor = "rgba(255,204,0,0.7)";
    ctx.shadowBlur = 8;
    ctx.strokeStyle = "#ffcc00";
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.stroke();
    const dot = { x: xOf(pr.playhead, duration, w), y: h * (1 - Math.min(Math.max(f.level, 0), 1)) };
    circle(ctx, dot.x, dot.y, 7, "#ffcc00", "#fff", 2);
    ctx.restore();
    const label = rising ? L("フェードイン ↑") : L("フェードアウト ↓");
    ctx.font = "bold 11px 'Yu Gothic UI', 'Meiryo UI', sans-serif";
    const tw = ctx.measureText(label).width + 12;
    const lx = Math.min(dot.x + 10, w - tw - 4), ly = Math.min(Math.max(dot.y - 24, 2), h - 20);
    ctx.fillStyle = "#ffcc00";
    roundRect(ctx, lx, ly, tw, 17, 8.5);
    ctx.fill();
    ctx.fillStyle = "#000";
    ctx.fillText(label, lx + 6, ly + 12.5);
  }

  // PANライン と音量ライン（編集中の線を上に）
  const order: ["pan" | "volume", LineKind, VolumePoint[], number | null][] = [
    ["pan", PAN, p.panPoints, pr.livePan],
    ["volume", VOLUME, p.volumePoints, pr.liveVolume],
  ];
  if (pr.lineMode === "pan") order.reverse();
  for (const [mode, kind, points, live] of order) drawLine(ctx, kind, points, pr, mode === pr.lineMode, live, w, h);

  // 再生位置
  if (pr.playhead !== null) {
    ctx.fillStyle = "#ffcc00";
    ctx.fillRect(xOf(pr.playhead, duration, w) - 1, 0, 2, h);
  }
  ctx.restore();
}

function drawLine(ctx: CanvasRenderingContext2D, k: LineKind, points: VolumePoint[], pr: WaveformProps, editing: boolean, live: number | null, w: number, h: number) {
  const duration = pr.duration;
  if (editing) {
    // 0（音量なら 0dB、PAN なら中央）の目安
    ctx.beginPath();
    ctx.moveTo(0, yOfLine(k, 0, h));
    ctx.lineTo(w, yOfLine(k, 0, h));
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = "rgba(255,255,255,0.35)";
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (!editing && points.length === 0) return;
  if (editing && k.topIsMin) {
    ctx.font = "bold 10px sans-serif";
    ctx.fillStyle = k.color;
    ctx.fillText("L", 5, 13);
    ctx.fillText("R", 5, h - 5);
  }
  // 線（1 ピクセルごとに値を取る）
  ctx.beginPath();
  const cols = Math.max(2, Math.floor(w));
  for (let c = 0; c <= cols; c++) {
    const px = (c * w) / cols;
    const py = yOfLine(k, lineValue(points, tOf(px, duration, w)), h);
    if (c === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
  }
  ctx.globalAlpha = editing ? 1 : 0.7;
  ctx.strokeStyle = k.color;
  ctx.lineWidth = editing ? 2.5 : 1.5;
  ctx.lineJoin = "round";
  ctx.stroke();
  ctx.globalAlpha = 1;

  // 選んだ区間のつなぎの形（白い四角と腕）
  const seg = pr.selectedSegment;
  if (editing && seg !== null && seg + 1 < points.length && points[seg].db !== points[seg + 1].db) {
    const g = segmentHandles(k, points, seg, duration, w, h);
    if (g) {
      ctx.beginPath();
      ctx.moveTo(g.p0.x, g.p0.y); ctx.lineTo(g.c1.x, g.c1.y);
      ctx.moveTo(g.p3.x, g.p3.y); ctx.lineTo(g.c2.x, g.c2.y);
      ctx.strokeStyle = "rgba(255,255,255,0.75)";
      ctx.lineWidth = 1;
      ctx.stroke();
      for (const c of [g.c1, g.c2]) square(ctx, c.x, c.y, "#fff", k.color);
    }
  }
  // 点
  for (const pt of points) {
    const selected = pt.id === pr.selectedPoint;
    circle(ctx, xOf(pt.time, duration, w), yOfLine(k, pt.db, h), selected ? 7 : 5, selected ? "#fff" : k.color, selected ? k.color : "#fff", 1.5);
  }
  // 再生中の位置の値
  if (pr.playhead !== null && live !== null && points.length > 0) {
    ctx.beginPath();
    ctx.arc(xOf(pr.playhead, duration, w), yOfLine(k, live, h), 5, 0, Math.PI * 2);
    ctx.fillStyle = "#ffcc00";
    ctx.fill();
  }
}

function circle(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, fill: string, stroke: string, lw: number) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = fill;
  ctx.fill();
  ctx.strokeStyle = stroke;
  ctx.lineWidth = lw;
  ctx.stroke();
}

function square(ctx: CanvasRenderingContext2D, x: number, y: number, fill: string, stroke: string) {
  ctx.fillStyle = fill;
  ctx.fillRect(x - 5, y - 5, 10, 10);
  ctx.strokeStyle = stroke;
  ctx.lineWidth = 1.5;
  ctx.strokeRect(x - 5, y - 5, 10, 10);
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
