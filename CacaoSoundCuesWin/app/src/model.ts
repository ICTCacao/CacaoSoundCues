// キューシートのデータ（Mac 版 Model.swift と同じ形の JSON）と、表示のための計算

export type Id = string;
export type FadeCurve = "linear" | "equalPower" | "sCurve" | "custom";
export type RetriggerMode = "fadeOut" | "restart" | "layer" | "ignore";
export type StepStart = "afterPrevious" | "overlap" | "returnKey";

export interface FadeBezier { x1: number; y1: number; x2: number; y2: number }

/** 音量ライン・PANライン の点（db に、音量ラインは dB、PANライン は -1〜1） */
export interface VolumePoint { id: Id; time: number; db: number; shape?: FadeBezier }

export interface PlaySettings {
  soundID: Id;
  inPoint: number;
  outPoint?: number;
  fadeIn: number;
  fadeOut: number;
  fadeOutAtEnd: boolean;
  loop: boolean;
  loopCount: number;
  volumeDB: number;
  curve: FadeCurve;
  fadeInBezier?: FadeBezier;
  fadeOutBezier?: FadeBezier;
  volumePoints: VolumePoint[];
  pan: number;
  panPoints: VolumePoint[];
}

export interface SoundRef { id: Id; fileName: string; displayName: string; duration: number }

export interface KeyCue {
  id: Id;
  keyCode: number;
  name: string;
  colorIndex: number;
  retrigger: RetriggerMode;
  play: PlaySettings;
  groupID?: Id;
}

export interface KeyGroup { id: Id; name: string }

export interface SequenceStep { id: Id; name: string; play: PlaySettings; start: StepStart; startSeconds: number }

export interface CueSequence { id: Id; name: string; toggleKey?: number; steps: SequenceStep[]; loop: boolean; stopFade: number }

export interface Show {
  formatVersion: number;
  name: string;
  sounds: SoundRef[];
  keyCues: KeyCue[];
  keyGroups: KeyGroup[];
  sequences: CueSequence[];
  masterVolumeDB: number;
  panicFade: number;
}

/** 鳴っている音の状態（Rust の snapshot。時間は秒） */
export interface VoiceStatus {
  token: number;
  owner: Id;
  tag: Id;
  position: number;
  start: number;
  end: number;
  armed: boolean;
  stopping: boolean;
  looping: boolean;
  remaining: number;
  level: number;
  fading: boolean;
  fadingDown: boolean;
  fadeElapsed: number;
  fadeLength: number;
  fadeFrom: number;
  fadeTo: number;
  startsIn: number;
  lineGain: number;
  panNow: number;
}

export const newId = (): Id => crypto.randomUUID().toUpperCase();

export const MIN_DB = -40;
export const MAX_DB = 6;
export const DEFAULT_LINE_SHAPE: FadeBezier = { x1: 0.42, y1: 0, x2: 0.58, y2: 1 };

export function newShow(name: string): Show {
  return { formatVersion: 1, name, sounds: [], keyCues: [], keyGroups: [], sequences: [], masterVolumeDB: 0, panicFade: 2 };
}

export function newPlaySettings(soundID: Id): PlaySettings {
  return {
    soundID, inPoint: 0, fadeIn: 0, fadeOut: 0, fadeOutAtEnd: false, loop: false, loopCount: 0,
    volumeDB: 0, curve: "equalPower", volumePoints: [], pan: 0, panPoints: [],
  };
}

/** 読み込んだ JSON の抜けている値を、Mac 版と同じ既定値で埋める */
export function normalizeShow(s: Show): Show {
  const play = (p: PlaySettings): PlaySettings => ({ ...newPlaySettings(p.soundID), ...p });
  s.sounds ??= [];
  s.keyCues = (s.keyCues ?? []).map(c => ({ ...c, colorIndex: c.colorIndex ?? 0, retrigger: c.retrigger ?? "fadeOut", play: play(c.play) }));
  s.keyGroups ??= [];
  s.sequences = (s.sequences ?? []).map(q => ({
    ...q, loop: q.loop ?? false, stopFade: q.stopFade ?? 3,
    steps: (q.steps ?? []).map(st => ({
      ...st, startSeconds: st.startSeconds ?? 0,
      start: ((st.start as string) === "manual" ? "returnKey" : st.start ?? "returnKey") as StepStart,
      play: play(st.play),
    })),
  }));
  s.masterVolumeDB ??= 0;
  s.panicFade ??= 2;
  s.formatVersion ??= 1;
  return s;
}

/** 何回鳴るか。null は止めるまでくり返す */
export function plays(p: PlaySettings): number | null {
  if (!p.loop) return 1;
  return p.loopCount > 0 ? p.loopCount : null;
}

// MARK: - フェードの形（Mac 版 FadeBezier と同じ計算）

export function presetBezier(curve: FadeCurve, rising: boolean): FadeBezier {
  if (curve === "linear") return rising ? { x1: 1 / 3, y1: 1 / 3, x2: 2 / 3, y2: 2 / 3 } : { x1: 1 / 3, y1: 2 / 3, x2: 2 / 3, y2: 1 / 3 };
  if (curve === "sCurve") return rising ? { x1: 1 / 3, y1: 0, x2: 2 / 3, y2: 1 } : { x1: 1 / 3, y1: 1, x2: 2 / 3, y2: 0 };
  return rising ? { x1: 1 / 3, y1: Math.PI / 6, x2: 2 / 3, y2: 1 } : { x1: 1 / 3, y1: 1, x2: 2 / 3, y2: 1 - Math.PI / 6 };
}

/** 進み p（0〜1）のときの音量（0〜1）。x(t) = p を二分法で解く */
export function bezierGain(b: FadeBezier, rising: boolean, p: number): number {
  const x = Math.min(Math.max(p, 0), 1);
  const y0 = rising ? 0 : 1, y3 = rising ? 1 : 0;
  let lo = 0, hi = 1, t = x;
  for (let i = 0; i < 16; i++) {
    const u = 1 - t;
    const xt = 3 * u * u * t * b.x1 + 3 * u * t * t * b.x2 + t * t * t;
    if (xt < x) lo = t; else hi = t;
    t = (lo + hi) / 2;
  }
  const u = 1 - t;
  const y = u * u * u * y0 + 3 * u * u * t * b.y1 + 3 * u * t * t * b.y2 + t * t * t * y3;
  return Math.min(Math.max(y, 0), 1);
}

/** 実際に使うフェードの形 */
export function settingsBezier(p: PlaySettings, rising: boolean): FadeBezier {
  if (p.curve === "custom") {
    const b = rising ? p.fadeInBezier : p.fadeOutBezier;
    if (b) return b;
  }
  return presetBezier(p.curve === "custom" ? "equalPower" : p.curve, rising);
}

/** ミキサーと同じフェードの音量 */
export function fadeShape(p: PlaySettings, q: number, rising: boolean): number {
  q = Math.min(Math.max(q, 0), 1);
  switch (p.curve) {
    case "linear": return rising ? q : 1 - q;
    case "equalPower": return rising ? Math.sin(q * Math.PI / 2) : Math.cos(q * Math.PI / 2);
    case "sCurve": return rising ? 0.5 - 0.5 * Math.cos(q * Math.PI) : 0.5 + 0.5 * Math.cos(q * Math.PI);
    default: return bezierGain(settingsBezier(p, rising), rising, q);
  }
}

// MARK: - 音量ライン

/** 線の、ある時刻（秒）の値。点が無ければ 0 */
export function lineValue(points: VolumePoint[], t: number): number {
  if (points.length === 0) return 0;
  if (t <= points[0].time) return points[0].db;
  for (let k = 0; k < points.length - 1; k++) {
    const a = points[k], b = points[k + 1];
    if (t < b.time) {
      const p = (t - a.time) / Math.max(1e-9, b.time - a.time);
      return a.db + (b.db - a.db) * bezierGain(a.shape ?? DEFAULT_LINE_SHAPE, true, p);
    }
  }
  return points[points.length - 1].db;
}

/** つまみで記録した細かい点を、形を保ったまま減らす */
export function simplifyPoints(points: VolumePoint[], tolerance = 0.5, maxCount = 64): VolumePoint[] {
  const pts = [...points].sort((a, b) => a.time - b.time);
  const error = (i: number) => {
    const a = pts[i - 1], b = pts[i + 1], p = pts[i];
    const u = (p.time - a.time) / Math.max(1e-9, b.time - a.time);
    return Math.abs(p.db - (a.db + (b.db - a.db) * u));
  };
  while (pts.length > 2) {
    let best = 1, bestErr = Infinity;
    for (let i = 1; i < pts.length - 1; i++) {
      const e = error(i);
      if (e < bestErr) { bestErr = e; best = i; }
    }
    if (bestErr > tolerance && pts.length <= maxCount) break;
    pts.splice(best, 1);
  }
  return pts;
}

// MARK: - 表示

/** 秒を 1:23.4 の形に */
export function timeText(t: number): string {
  if (!isFinite(t)) return "--:--";
  t = Math.max(0, t);
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  return `${m}:${s.toFixed(1).padStart(4, "0")}`;
}

export const dbToGain = (db: number) => Math.pow(10, db / 20);

export function panLabel(pan: number): string {
  if (Math.abs(pan) < 0.01) return "C";
  return pan < 0 ? `L${Math.round(-pan * 100)}` : `R${Math.round(pan * 100)}`;
}

export const signed = (v: number, digits = 1) => (v >= 0 ? "+" : "") + v.toFixed(digits);

/** キューシートに保存したファイル名から、先頭の「ID-」を除いた元の名前 */
export function originalFileName(s: SoundRef): string {
  const prefix = s.id + "-";
  return s.fileName.startsWith(prefix) ? s.fileName.slice(prefix.length) : s.fileName;
}

export const AUDIO_EXTENSIONS = ["wav", "wave", "aif", "aiff", "aifc", "mp3", "m4a", "mp4", "aac", "flac", "ogg", "oga", "caf"];
