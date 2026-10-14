// アプリの状態と操作（Mac 版 AppModel.swift の移植）。音は Rust 側（engine.ts 経由）で鳴らす
import { signal, computed } from "@preact/signals";
import { invoke } from "@tauri-apps/api/core";
import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";
import { L } from "./i18n";
import {
  type CueSequence, type Id, type KeyCue, type PlaySettings, type Show, type SoundRef, type VoiceStatus,
  AUDIO_EXTENSIONS, newId, newPlaySettings, newShow, normalizeShow, simplifyPoints,
} from "./model";
import { prefs, defaults } from "./prefs";
import { ALL_KEYS, CODE_TO_MAC, KEY, keyLabel, reservedReason } from "./keymap";
import { choose } from "./ui/modal";

export type Selection =
  | { kind: "none" }
  | { kind: "key"; code: number }
  | { kind: "step"; sequence: Id; step: Id };

export type LoadState = { state: "loading" } | { state: "ready" } | { state: "failed"; reason: string };

/** 再生中のリスト（同時に鳴らすリストは1つだけ） */
export interface SequenceRun {
  sequenceID: Id;
  /** 鳴っている曲（Return 待ちの間は null） */
  currentToken: number | null;
  currentIndex: number | null;
  /** 前の曲の終わりを待っている次の曲（ミキサー側で待機中） */
  armedToken: number | null;
  armedIndex: number | null;
  /** Return で鳴らす次の曲（タイミングが「Return キーを押したとき」のとき） */
  pendingIndex: number | null;
  changedAt: number;
}

const newRun = (sequenceID: Id, currentToken: number | null, currentIndex: number | null): SequenceRun => ({
  sequenceID, currentToken, currentIndex, armedToken: null, armedIndex: null, pendingIndex: null, changedAt: Date.now(),
});
export const isWaiting = (r: SequenceRun) => r.currentToken === null;

export interface OutputInfo { sampleRate: number; deviceName: string; bufferFrames: number }

/** インスペクタの試聴ボタン用の持ち主 */
export const PREVIEW_OWNER: Id = "00000000-0000-4000-8000-0000000000AA";
export const COLORS = ["#8e8e93", "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#30b0c7", "#007aff", "#af52de"];
export const colorOf = (i: number) => COLORS[((i % COLORS.length) + COLORS.length) % COLORS.length];

// MARK: - 音の命令（送った順に必ず届ける）

/** 音の命令は1つずつ順に送る。続けて送った命令の順番が入れ替わると
 * （例: 1曲目を鳴らす → 2曲目を1曲目に重ねて待機）、2曲目がすぐ鳴ってしまうため */
let chain: Promise<unknown> = Promise.resolve();
function engine(cmd: string, args?: Record<string, unknown>) {
  chain = chain.then(() => invoke(cmd, args)).catch(() => undefined);
  return chain;
}

// MARK: - 状態

export const show = signal<Show>(newShow(L("新しいキューシート")));
export const showPath = signal<string | null>(null);
export const dirty = signal(false);
export const selection = signal<Selection>({ kind: "none" });
export const selectedSequenceID = signal<Id | null>(null);
/** リストの開始／停止キーを割り当て待ち */
export const capturingSequenceKey = signal<Id | null>(null);
/** キー一覧に落とした音ファイル。次に押したキーに割り当てる */
export const pendingAssign = signal<{ paths: string[]; group: Id | null } | null>(null);
export const loadStates = signal<Record<Id, LoadState>>({});
export const status = signal<VoiceStatus[]>([]);
export const run = signal<SequenceRun | null>(null);
/** ダブルクリックで決めた「次に始める曲」（鳴っていないリスト用） */
export const cuedStart = signal<{ sequence: Id; index: number } | null>(null);
export const message = signal<string | null>(null);
export const output = signal<OutputInfo>({ sampleRate: 48000, deviceName: "", bufferFrames: 0 });
/** ファイルをドラッグして重ねている場所（data-drop の値） */
export const dropTarget = signal<string | null>(null);
/** 設定画面を開いているか */
export const settingsOpen = signal(false);

/** 読み込んだ音の長さと波形（表示用） */
export const loaded = new Map<Id, { duration: number; peaks: number[] }>();
/** まだキューシートに保存していない音の元のファイル */
const pendingFiles = new Map<Id, string>();
/** delete キーで消すもの（音量ラインで選んでいるマーク） */
export let deleteKeyAction: (() => void) | null = null;
export const setDeleteKeyAction = (f: (() => void) | null) => { deleteKeyAction = f; };

let nextToken = 0;

export const isPlaying = computed(() => status.value.some(v => !v.armed));
export const memoryBytes = computed(() => {
  void loadStates.value;
  let frames = 0;
  for (const s of loaded.values()) frames += s.duration * output.value.sampleRate;
  return frames * 8;
});

/** キューシートを書き換える（画面を描き直し、未保存の印を付ける） */
export function edit(fn: (s: Show) => void) {
  const s = show.peek();
  fn(s);
  show.value = { ...s };
  dirty.value = true;
}

// MARK: - 本番モード

export async function toggleShowMode() {
  if (prefs.showMode.value) {
    const i = await choose(L("本番モードを終了しますか？"), L("終了すると、キューシートを編集できるようになります。"),
      [{ label: L("キャンセル") }, { label: L("本番モードを終了"), kind: "danger" }]);
    if (i !== 1) return;
    prefs.showMode.value = false;
  } else {
    endEditing();
    capturingSequenceKey.value = null;
    pendingAssign.value = null;
    prefs.showMode.value = true;
  }
}

/** 本番モード中なら知らせて true（編集の操作の頭で使う） */
function lockedForShow(): boolean {
  if (!prefs.showMode.value) return false;
  message.value = L("本番モード中は編集できません。上の「本番モード」を押して終了してください。");
  return true;
}

/** 文字入力を終えてキーを音出しに戻す */
export function endEditing() {
  const a = document.activeElement as HTMLElement | null;
  if (a && a !== document.body) a.blur();
}

// MARK: - 再生

/** 鳴らせるか（読み込み済みで、範囲が空でない） */
function canPlay(p: PlaySettings): boolean {
  const st = loadStates.peek()[p.soundID];
  const info = loaded.get(p.soundID);
  if (st?.state !== "ready" || !info) return false;
  const start = Math.min(Math.max(0, p.inPoint), info.duration);
  const end = Math.min(info.duration, p.outPoint ?? info.duration);
  return end > start;
}

interface PlayOptions { follow?: number; gap?: number; crossfade?: boolean; delay?: number }

/** 鳴らす。鳴らせたら token を返す */
function send(mode: "play" | "toggle" | "restart" | "ifIdle", p: PlaySettings, owner: Id, tag: Id, o: PlayOptions = {}): number | null {
  if (!canPlay(p)) return null;
  const token = ++nextToken;
  engine("play", { token, mode, owner, tag, settings: p, follow: o.follow ?? 0, gap: o.gap ?? 0, crossfade: o.crossfade ?? false, delay: o.delay ?? 0 });
  return token;
}

const stopToken = (token: number, fade: number | null) => engine("stop_token", { token, fade });
const stopOwner = (owner: Id, fade: number | null) => engine("stop_owner", { owner, fade });

export function trigger(cue: KeyCue) {
  const mode = ({ fadeOut: "toggle", restart: "restart", layer: "play", ignore: "ifIdle" } as const)[cue.retrigger] ?? "toggle";
  send(mode, cue.play, cue.id, cue.id);
}

/** 再生中の音の音量・左右・ラインを、設定を変えたその場で反映する（キーの音・リストの曲・試聴） */
export function liveUpdate(id: Id, p: PlaySettings) {
  engine("live_update", { id, settings: p });
  engine("live_update", { id: PREVIEW_OWNER, settings: p });
}

/** 鳴っている音の再生位置を秒で移す */
export function seek(token: number, seconds: number) {
  if (prefs.showMode.peek()) return;
  engine("seek", { token, seconds });
}

export function preview(p: PlaySettings) {
  if (lockedForShow()) return;
  send("toggle", p, PREVIEW_OWNER, PREVIEW_OWNER);
}

/** Esc: 全部の音をすぐ止める（フェードなし。プツッと鳴らないよう、ミキサーが数ミリ秒だけ絞る） */
export function panic() {
  engine("stop_all", { fade: 0 });
  run.value = null;
}

export function applyMasterVolume() {
  engine("set_master", { db: show.peek().masterVolumeDB });
}

export const playingOwner = (owner: Id) => status.value.findLast(v => v.owner === owner && !v.armed);
export const playingTag = (tag: Id) => status.value.findLast(v => v.tag === tag && !v.armed);

// MARK: - リスト（シーケンシャル再生）

const seqOf = (id: Id | null | undefined) => show.peek().sequences.find(s => s.id === id);
export const isRunning = (id: Id) => run.value?.sequenceID === id;

/** Return の対象になるリスト（再生中のもの、無ければ画面で選んでいるもの） */
export function activeSequenceID(): Id | null {
  return run.value?.sequenceID ?? selectedSequenceID.value ?? show.value.sequences[0]?.id ?? null;
}

export function toggleSequence(id: Id) {
  if (isRunning(id)) stopSequence(id); else startSequence(id, cuedIndex(id) ?? 0);
}

function cuedIndex(id: Id): number | null {
  const c = cuedStart.peek();
  return c && c.sequence === id ? c.index : null;
}

/** ↑↓: リストの「次に鳴らす曲」を1つ上下に動かす（ダブルクリックと同じ扱い） */
export function moveCue(delta: number) {
  const id = activeSequenceID();
  const seq = seqOf(id);
  if (!id || !seq || seq.steps.length === 0) return;
  let base = upcomingIndex(id);
  const sel = selection.peek();
  if (base === null && sel.kind === "step" && sel.sequence === id) {
    const i = seq.steps.findIndex(s => s.id === sel.step);
    base = i >= 0 ? i : null;
  }
  const r = run.peek();
  if (base === null && r && r.sequenceID === id) base = r.currentIndex;
  const index = base === null ? 0 : Math.min(Math.max(base + delta, 0), seq.steps.length - 1);
  cueStep(id, index);
}

/** ダブルクリック: 次に鳴らす曲をこの曲にする（鳴らさない）。Return で鳴る */
export function cueStep(id: Id, index: number) {
  endEditing();
  const seq = seqOf(id);
  if (!seq || index < 0 || index >= seq.steps.length) return;
  selectedSequenceID.value = id;
  selection.value = { kind: "step", sequence: id, step: seq.steps[index].id };
  // 読み込めていない曲は飛ばされてしまうので、選べないことを知らせる
  if (loadStates.peek()[seq.steps[index].play.soundID]?.state !== "ready") {
    message.value = L("「%@」は読み込めていないため、鳴らせません。", seq.steps[index].name);
    return;
  }
  const r = run.peek();
  if (r && r.sequenceID === id) {
    if (r.armedToken !== null) stopToken(r.armedToken, 0);
    const cleared = { ...r, armedToken: null, armedIndex: null, pendingIndex: null };
    run.value = cleared;
    if (isWaiting(cleared)) run.value = { ...cleared, pendingIndex: index };
    else scheduleNext(index);
    cuedStart.value = null;
  } else {
    cuedStart.value = { sequence: id, index };
  }
}

export function startSequence(id: Id, from = 0) {
  const seq = seqOf(id);
  if (!seq) return;
  // 別のリストが鳴っていたら停止フェードで止める。同じリストの中で移るときは、今の曲をその曲のフェードアウトで止める
  const r = run.peek();
  const old = r ? seqOf(r.sequenceID) : undefined;
  if (old) {
    stopOwner(old.id, old.id === id ? null : old.stopFade);
    run.value = null;
  }
  cuedStart.value = null;
  const i = playableIndex(seq, from);
  if (i === null) {
    message.value = L("再生できる曲がありません");
    return;
  }
  playStep(seq, i);
}

export function stopSequence(id: Id) {
  const seq = seqOf(id);
  if (!isRunning(id) || !seq) return;
  stopOwner(id, seq.stopFade);
  run.value = null;
}

/** Return: 再生中のリストの次の曲をすぐ鳴らす。どのリストも鳴っていなければ、選んでいるリストを開始する */
export function advanceActiveSequence() {
  const cued = cuedStart.peek();
  if (cued && run.peek()?.sequenceID !== cued.sequence) {
    startSequence(cued.sequence, cued.index);
    return;
  }
  const r = run.peek();
  const seq = r ? seqOf(r.sequenceID) : undefined;
  if (!r || !seq) {
    const id = activeSequenceID();
    if (id) startSequence(id);
    return;
  }
  // 「Return を押してから n 秒」を待っている間にもう一度 Return を押したら、待たずにすぐ鳴らす
  if (r.currentToken !== null && status.peek().some(v => v.token === r.currentToken && v.armed)) {
    engine("start_now", { token: r.currentToken });
    return;
  }
  const target = r.pendingIndex ?? r.armedIndex ?? (r.currentIndex !== null ? playableIndex(seq, r.currentIndex + 1) : null);
  if (r.armedToken !== null) stopToken(r.armedToken, 0);
  if (r.currentToken !== null) stopToken(r.currentToken, null);
  if (target === null) {
    run.value = null;
    return;
  }
  playStep(seq, target);
}

/** スペース: リストの今の曲を途中で終える（その曲のフェードアウトで） */
export function endCurrentSequenceSong() {
  const t = run.peek()?.currentToken;
  if (t != null) stopToken(t, null);
}

/** 次に Return を押したときに鳴る曲（表示用） */
export function upcomingIndex(id: Id): number | null {
  const r = run.value;
  if (r && r.sequenceID === id) return r.pendingIndex ?? r.armedIndex;
  const c = cuedStart.value;
  return c && c.sequence === id ? c.index : null;
}

/** タイミングが「Return キーを押したとき」で秒数があれば、その秒数だけ待ってから鳴らす */
function playStep(seq: CueSequence, i: number) {
  const step = seq.steps[i];
  const delay = step.start === "returnKey" && step.startSeconds > 0 ? step.startSeconds : 0;
  const token = send("play", step.play, seq.id, step.id, { delay });
  if (token === null) return;
  run.value = newRun(seq.id, token, i);
  followPlaying(seq.id, i);
  scheduleNext();
}

/** 鳴り始めた曲の行を選択状態にする（キーの設定を開いている最中は奪わない） */
function followPlaying(seqID: Id, index: number) {
  const seq = seqOf(seqID);
  if (!seq || index < 0 || index >= seq.steps.length) return;
  if (selection.peek().kind === "key") return;
  selectedSequenceID.value = seqID;
  selection.value = { kind: "step", sequence: seqID, step: seq.steps[index].id };
}

function playableIndex(seq: CueSequence, index: number): number | null {
  const n = seq.steps.length;
  if (n === 0) return null;
  for (let k = 0; k < n; k++) {
    const j = index + k;
    if (j >= n && !seq.loop) return null;
    const i = j % n;
    if (loadStates.peek()[seq.steps[i].play.soundID]?.state === "ready") return i;
  }
  return null;
}

/** 次の曲のタイミングに合わせて、ミキサーに待機させるか Return 待ちにする */
function scheduleNext(forced: number | null = null) {
  const r = run.peek();
  const seq = r ? seqOf(r.sequenceID) : undefined;
  if (!r || !seq || r.currentIndex === null || r.currentToken === null) return;
  const next = (forced !== null ? playableIndex(seq, forced) : null) ?? playableIndex(seq, r.currentIndex + 1);
  if (next === null) return;
  const step = seq.steps[next];
  const nr = { ...r };
  if (step.start === "afterPrevious" || step.start === "overlap") {
    const gap = step.start === "overlap" ? -step.startSeconds : step.startSeconds;
    const token = send("play", step.play, seq.id, step.id, { follow: r.currentToken, gap, crossfade: step.start === "overlap" });
    if (token === null) return;
    nr.armedToken = token;
    nr.armedIndex = next;
  } else {
    nr.pendingIndex = next;
  }
  run.value = nr;
}

function advanceSequences() {
  const r = run.peek();
  if (!r) return;
  const st = status.peek();
  if (r.armedToken !== null && r.armedIndex !== null && st.some(v => v.token === r.armedToken && !v.armed)) {
    run.value = newRun(r.sequenceID, r.armedToken, r.armedIndex);
    followPlaying(r.sequenceID, r.armedIndex);
    scheduleNext();
    return;
  }
  // コマンドがまだ音声スレッドに届いていない間は判定しない
  if (r.currentToken === null || Date.now() - r.changedAt <= 250) return;
  const alive = st.some(v => v.token === r.currentToken || v.token === r.armedToken);
  if (alive) return;
  // 前の曲が終わった。次が Return 待ちならリストは待機、無ければ終わり
  run.value = r.pendingIndex !== null ? { ...r, currentToken: null, currentIndex: null } : null;
}

/** 1秒に30回: 鳴っている音の状態を取り、リストを進める */
export async function tick() {
  try {
    status.value = await invoke<VoiceStatus[]>("snapshot");
    advanceSequences();
  } catch { /* 次の回で取り直す */ }
}

// MARK: - 音ファイル

const sep = (p: string) => (p.includes("\\") ? "\\" : "/");
const baseName = (p: string) => p.split(/[\\/]/).pop() ?? p;
const stripExt = (n: string) => n.replace(/\.[^.]+$/, "");

export function fileFor(sound: SoundRef): string | null {
  const pending = pendingFiles.get(sound.id);
  if (pending) return pending;
  const pkg = showPath.peek();
  if (!pkg) return null;
  const s = sep(pkg);
  return `${pkg.replace(/[\\/]+$/, "")}${s}Audio${s}${sound.fileName}`;
}

export const soundOf = (id: Id) => show.value.sounds.find(s => s.id === id);

/** 一度に読み込む数（低性能の PC でも画面が止まらないように） */
const MAX_LOADING = 2;
const loadQueue: (() => Promise<void>)[] = [];
let loading = 0;

function pump() {
  while (loading < MAX_LOADING && loadQueue.length > 0) {
    const job = loadQueue.shift()!;
    loading++;
    job().finally(() => { loading--; pump(); });
  }
}

function setLoadState(id: Id, st: LoadState) {
  loadStates.value = { ...loadStates.peek(), [id]: st };
}

/** 開き直したときに古い読み込みの結果を捨てるための番号 */
let generation = 0;

function load(sound: SoundRef) {
  const path = fileFor(sound);
  if (!path) {
    setLoadState(sound.id, { state: "failed", reason: L("ファイルが見つかりません") });
    return;
  }
  setLoadState(sound.id, { state: "loading" });
  const gen = generation;
  loadQueue.push(async () => {
    if (gen !== generation) return;
    try {
      await chain;   // 先に送った「全部手放す」が済んでから読み込む
      const r = await invoke<{ duration: number; peaks: number[] }>("load_sound", { id: sound.id, path });
      if (gen !== generation || !show.peek().sounds.some(s => s.id === sound.id)) return;
      loaded.set(sound.id, r);
      // 長さを調べられなかった音（一部の mp3 など）は、読み込んだ長さを使う
      const s = show.peek().sounds.find(x => x.id === sound.id);
      if (s && Math.abs(s.duration - r.duration) > 0.05) s.duration = r.duration;
      setLoadState(sound.id, { state: "ready" });
    } catch (e) {
      if (gen !== generation) return;
      setLoadState(sound.id, { state: "failed", reason: String(e) });
    }
  });
  pump();
}

async function addSound(path: string): Promise<SoundRef | null> {
  const name = baseName(path);
  const ext = (name.split(".").pop() ?? "").toLowerCase();
  if (!AUDIO_EXTENSIONS.includes(ext)) {
    message.value = L("音ファイルではありません: %@", name);
    return null;
  }
  const duration = await invoke<number | null>("probe_sound", { path }).catch(() => null);
  // キューシートの Audio/ から持ってきたファイルは、名前の頭の「ID-」を外す
  const clean = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}-./.test(name) ? name.slice(37) : name;
  const s: SoundRef = { id: newId(), fileName: clean, displayName: stripExt(clean), duration: duration ?? 0 };
  pendingFiles.set(s.id, path);
  edit(sh => sh.sounds.push(s));
  load(s);
  return s;
}

// MARK: - キーの割り当て

export const cueForKey = (code: number) => show.value.keyCues.find(c => c.keyCode === code);
export const sequenceForKey = (code: number) => show.value.sequences.find(s => s.toggleKey === code);

export async function assign(paths: string[], code: number, group: Id | null = null) {
  if (lockedForShow()) return;
  const path = paths[0];
  if (!path) return;
  const reason = reservedReason(code);
  if (reason) { message.value = reason; return; }
  const seq = sequenceForKey(code);
  if (seq) { message.value = L("このキーはリスト「%@」の開始／停止キーです", seq.name); return; }
  const s = await addSound(path);
  if (!s) return;
  edit(sh => {
    const existing = sh.keyCues.find(c => c.keyCode === code);
    if (existing) {
      existing.play.soundID = s.id;
      existing.play.inPoint = 0;
      delete existing.play.outPoint;
      existing.name = s.displayName;
    } else {
      const p = newPlaySettings(s.id);
      p.fadeIn = defaults.keyFadeIn.peek();
      p.fadeOut = defaults.keyFadeOut.peek();
      p.curve = defaults.curve.peek();
      sh.keyCues.push({
        id: newId(), keyCode: code, name: s.displayName, colorIndex: sh.keyCues.length % COLORS.length,
        retrigger: defaults.keyRetrigger.peek(), play: p, ...(group ? { groupID: group } : {}),
      });
    }
  });
  selection.value = { kind: "key", code };
}

/** 古いキューシートで操作用のキー（スペースなど）に割り当てていたものを外して知らせる */
function releaseReservedKeys(): boolean {
  const released: string[] = [];
  const sh = show.peek();
  for (const c of sh.keyCues) if (reservedReason(c.keyCode)) released.push(L("「%@」（%@）", c.name, keyLabel(c.keyCode)));
  sh.keyCues = sh.keyCues.filter(c => !reservedReason(c.keyCode));
  for (const q of sh.sequences) {
    if (q.toggleKey !== undefined && reservedReason(q.toggleKey)) {
      released.push(L("リスト「%@」の開始／停止キー（%@）", q.name, keyLabel(q.toggleKey)));
      delete q.toggleKey;
    }
  }
  if (released.length > 0) {
    message.value = L("次の割り当てを外しました。スペース・Enter・Esc は操作用のキーです。\n") + released.join("\n");
  }
  return released.length > 0;
}

/** キーの割り当てを別のキーへ移す。移り先も割り当て済みなら入れ替える */
export function moveKey(from: number, to: number) {
  if (lockedForShow() || from === to) return;
  const reason = reservedReason(to);
  if (reason) { message.value = reason; return; }
  const sh = show.peek();
  const srcCue = sh.keyCues.find(c => c.keyCode === from);
  const dstCue = sh.keyCues.find(c => c.keyCode === to);
  const srcSeq = sh.sequences.find(q => q.toggleKey === from);
  const dstSeq = sh.sequences.find(q => q.toggleKey === to);
  if (!srcCue && !srcSeq) return;
  edit(() => {
    if (srcCue) srcCue.keyCode = to;
    if (srcSeq) srcSeq.toggleKey = to;
    if (dstCue) dstCue.keyCode = from;
    if (dstSeq) dstSeq.toggleKey = from;
  });
  selection.value = { kind: "key", code: to };
}

/** キーの割り当てを別のキーへコピーする（Ctrl＋ドラッグ）。音・音量・フェードなどの設定はそのまま、別のキーとして使う。
 *  コピー先は空いているキーだけ（割り当て済みのキーは上書きしない） */
export function copyKey(from: number, to: number) {
  if (lockedForShow() || from === to) return;
  const reason = reservedReason(to);
  if (reason) { message.value = reason; return; }
  const src = cueForKey(from);
  if (!src) return;
  const used = cueForKey(to);
  if (used) { message.value = L("コピー先のキーには「%@」が割り当て済みです。空いているキーへコピーしてください", used.name); return; }
  const seq = sequenceForKey(to);
  if (seq) { message.value = L("このキーはリスト「%@」の開始／停止キーです", seq.name); return; }
  edit(sh => {
    const copy = { ...structuredClone(src), id: newId(), keyCode: to };
    // 並びはコピー元のすぐ後ろに
    const i = sh.keyCues.findIndex(c => c.id === src.id);
    sh.keyCues.splice(i < 0 ? sh.keyCues.length : i + 1, 0, copy);
  });
  selection.value = { kind: "key", code: to };
}

export function removeCue(code: number) {
  if (lockedForShow()) return;
  const cue = cueForKey(code);
  if (cue) stopOwner(cue.id, 0);
  edit(sh => { sh.keyCues = sh.keyCues.filter(c => c.keyCode !== code); });
}

function assignSequenceKey(code: number, id: Id) {
  const reason = reservedReason(code);
  if (reason) { message.value = reason; return; }
  const cue = cueForKey(code);
  if (cue) { message.value = L("このキーには「%@」が割り当て済みです", cue.name); return; }
  edit(sh => {
    for (const q of sh.sequences) if (q.toggleKey === code) delete q.toggleKey;
    const q = sh.sequences.find(x => x.id === id);
    if (q) q.toggleKey = code;
  });
}

const audioFilter = () => [{ name: L("音ファイル"), extensions: AUDIO_EXTENSIONS }];

/** 音ファイルを選んでから、割り当てるキーを押してもらう（キーボードを隠しているとき） */
export async function chooseFileThenKey(group: Id | null) {
  if (lockedForShow()) return;
  const path = await openDialog({ multiple: false, filters: audioFilter() });
  if (typeof path === "string") pendingAssign.value = { paths: [path], group };
}

/** 音ファイルを選んで、このキーに割り当てる */
export async function chooseFileForKey(code: number) {
  if (lockedForShow()) return;
  const path = await openDialog({ multiple: false, filters: audioFilter() });
  if (typeof path === "string") await assign([path], code);
}

// MARK: - キー一覧のグループ

/** グループごとのキー（未分類 = null）。並びは keyCues の順 */
export function cuesIn(group: Id | null): KeyCue[] {
  const sh = show.value;
  const known = new Set(sh.keyGroups.map(g => g.id));
  return sh.keyCues.filter(c => (group === null ? !c.groupID || !known.has(c.groupID) : c.groupID === group));
}

export function addKeyGroup() {
  edit(sh => sh.keyGroups.push({ id: newId(), name: L("グループ%d", sh.keyGroups.length + 1) }));
}

export function removeKeyGroup(id: Id) {
  edit(sh => {
    for (const c of sh.keyCues) if (c.groupID === id) delete c.groupID;
    sh.keyGroups = sh.keyGroups.filter(g => g.id !== id);
  });
}

export function moveKeyGroup(id: Id, delta: number) {
  edit(sh => {
    const i = sh.keyGroups.findIndex(g => g.id === id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= sh.keyGroups.length) return;
    [sh.keyGroups[i], sh.keyGroups[j]] = [sh.keyGroups[j], sh.keyGroups[i]];
  });
}

export function renameKeyGroup(id: Id, name: string) {
  edit(sh => { const g = sh.keyGroups.find(x => x.id === id); if (g) g.name = name; });
}

export function setGroup(group: Id | null, cueID: Id) {
  edit(sh => {
    const i = sh.keyCues.findIndex(c => c.id === cueID);
    if (i < 0) return;
    const [cue] = sh.keyCues.splice(i, 1);
    if (group) cue.groupID = group; else delete cue.groupID;
    sh.keyCues.push(cue);   // 移動先のグループの末尾へ
  });
}

/** グループの中で並べ替える（from の行を to の位置へ） */
export function moveCues(group: Id | null, from: number, to: number) {
  edit(sh => {
    const ordered = [cuesIn(null), ...sh.keyGroups.map(g => cuesIn(g.id))];
    const k = group ? sh.keyGroups.findIndex(g => g.id === group) + 1 : 0;
    const list = ordered[k];
    const [item] = list.splice(from, 1);
    list.splice(to > from ? to - 1 : to, 0, item);
    sh.keyCues = ordered.flat();
  });
}

// MARK: - リストの編集

export function addSequence() {
  if (lockedForShow()) return;
  const seq: CueSequence = { id: newId(), name: L("リスト%d", show.peek().sequences.length + 1), steps: [], loop: true, stopFade: 3 };
  edit(sh => sh.sequences.push(seq));
  selectedSequenceID.value = seq.id;
}

export function removeSequence(id: Id) {
  if (lockedForShow()) return;
  stopSequence(id);
  edit(sh => { sh.sequences = sh.sequences.filter(q => q.id !== id); });
  selectedSequenceID.value = show.peek().sequences[0]?.id ?? null;
}

export async function appendSteps(paths: string[], id: Id) {
  if (lockedForShow()) return;
  for (const path of paths) {
    const s = await addSound(path);
    if (!s) continue;
    const p = newPlaySettings(s.id);
    p.fadeIn = defaults.stepFadeIn.peek();
    p.fadeOut = defaults.stepFadeOut.peek();
    p.fadeOutAtEnd = defaults.stepFadeOutAtEnd.peek();
    p.curve = defaults.curve.peek();
    edit(sh => sh.sequences.find(q => q.id === id)?.steps.push({
      id: newId(), name: s.displayName, play: p, start: defaults.stepStart.peek(), startSeconds: defaults.stepStartSeconds.peek(),
    }));
  }
}

export async function chooseStepFiles(id: Id) {
  if (lockedForShow()) return;
  const paths = await openDialog({ multiple: true, filters: audioFilter() });
  if (Array.isArray(paths)) await appendSteps(paths, id);
  else if (typeof paths === "string") await appendSteps([paths], id);
}

export function removeStep(stepID: Id, id: Id) {
  if (lockedForShow()) return;
  edit(sh => {
    const q = sh.sequences.find(x => x.id === id);
    if (q) q.steps = q.steps.filter(s => s.id !== stepID);
  });
  const sel = selection.peek();
  if (sel.kind === "step" && sel.step === stepID) selection.value = { kind: "none" };
}

export function moveStep(id: Id, from: number, to: number) {
  if (lockedForShow()) return;
  edit(sh => {
    const q = sh.sequences.find(x => x.id === id);
    if (!q) return;
    const [item] = q.steps.splice(from, 1);
    q.steps.splice(to > from ? to - 1 : to, 0, item);
  });
}

// MARK: - ファイル

function reset(sh: Show, path: string | null) {
  engine("unload_all");
  generation++;
  loadQueue.length = 0;
  run.value = null;
  cuedStart.value = null;
  loaded.clear();
  loadStates.value = {};
  pendingFiles.clear();
  showPath.value = path;
  selection.value = { kind: "none" };
  show.value = sh;
  selectedSequenceID.value = sh.sequences[0]?.id ?? null;
}

export async function newShowFile() {
  if (lockedForShow()) return;
  if (!(await confirmDiscard())) return;
  reset(newShow(L("新しいキューシート")), null);
  dirty.value = false;
  applyMasterVolume();
}

export async function openPanel() {
  if (lockedForShow()) return;
  if (!(await confirmDiscard())) return;
  const path = await openDialog({ directory: true, title: L("キューシート（.ccsc のフォルダ）を開く") });
  if (typeof path === "string") await openShow(path);
}

/** 起動時に前回のキューシートを開くときは、本番モード中でも開く */
export async function openShow(path: string, evenInShowMode = false, quiet = false) {
  if (!evenInShowMode && lockedForShow()) return;
  try {
    const loadedShow = normalizeShow(await invoke<Show>("open_show", { path }));
    // 名前を付けずに保存した古いキューシートは、ファイル名を名前にする
    const renamed = isUntitled(loadedShow.name);
    if (renamed) loadedShow.name = nameFromPath(path);
    reset(loadedShow, path);
    const released = releaseReservedKeys();
    show.value = { ...show.peek() };
    dirty.value = released || renamed;
    applyMasterVolume();
    show.peek().sounds.forEach(load);
    prefs.lastShowPath.value = path;
  } catch (e) {
    // 起動時に前回のキューシートが見つからないときは、知らせずに空のまま始める
    if (quiet) { prefs.lastShowPath.value = null; return; }
    message.value = path.toLowerCase().replace(/[\\/]+$/, "").endsWith(".ccsc")
      ? String(e)
      : L("キューシート（.ccsc のフォルダ）を選んでください") + "\n" + path;
  }
}

/** ファイルの場所から、拡張子を除いた名前 */
function nameFromPath(path: string): string {
  const base = path.replace(/[\\/]+$/, "").split(/[\\/]/).pop() ?? path;
  return base.replace(/\.ccsc$/i, "");
}

/** 「新しいキューシート」のまま（どの言語で作ったものでも） */
function isUntitled(name: string): boolean {
  const n = name.trim();
  return n === "" || n === "新しいキューシート" || n === "New Cue Sheet" || n === L("新しいキューシート");
}

export async function save(): Promise<boolean> {
  const path = showPath.peek();
  return path ? write(path) : saveAs();
}

export async function saveAs(): Promise<boolean> {
  let path = await saveDialog({
    defaultPath: show.peek().name + ".ccsc",
    filters: [{ name: L("キューシート"), extensions: ["ccsc"] }],
  });
  if (!path) return false;
  if (!path.toLowerCase().endsWith(".ccsc")) path += ".ccsc";
  // 保存のときに付けたファイル名を、キューシートの名前にする
  show.peek().name = nameFromPath(path);
  return write(path);
}

async function write(path: string): Promise<boolean> {
  // どこからも使われていない音は保存しない
  const sh = show.peek();
  const used = new Set([...sh.keyCues.map(c => c.play.soundID), ...sh.sequences.flatMap(q => q.steps.map(s => s.play.soundID))]);
  if (sh.sounds.some(s => !used.has(s.id))) sh.sounds = sh.sounds.filter(s => used.has(s.id));
  const sources: Record<string, string> = {};
  for (const s of sh.sounds) {
    const f = fileFor(s);
    if (f) sources[s.id] = f;
  }
  try {
    const saved = normalizeShow(await invoke<Show>("save_show", { path, show: sh, sources }));
    show.value = saved;
    showPath.value = path;
    pendingFiles.clear();
    dirty.value = false;
    prefs.lastShowPath.value = path;
    return true;
  } catch (e) {
    message.value = L("保存できません: %@", String(e));
    return false;
  }
}

/** 未保存の変更があれば確認する。続けてよければ true */
export async function confirmDiscard(): Promise<boolean> {
  if (!dirty.peek()) return true;
  const i = await choose(L("「%@」の変更を保存しますか？", show.peek().name), undefined,
    [{ label: L("保存"), kind: "primary" }, { label: L("キャンセル") }, { label: L("保存しない") }]);
  if (i === 0) return save();
  return i === 2;
}

export async function confirmQuit(): Promise<boolean> {
  if (prefs.showMode.peek() || isPlaying.peek()) {
    const title = prefs.showMode.peek() ? L("本番モード中です。終了しますか？") : L("再生中です。終了しますか？");
    const i = await choose(title, undefined, [{ label: L("キャンセル") }, { label: L("終了する"), kind: "danger" }]);
    if (i !== 1) return false;
  }
  return confirmDiscard();
}

// MARK: - キー入力

const isTextInput = (el: EventTarget | null) =>
  el instanceof HTMLTextAreaElement ||
  (el instanceof HTMLInputElement && !["checkbox", "radio", "range", "button"].includes(el.type));

/** キーを押したとき。アプリで使ったら true */
export function handleKeyDown(e: KeyboardEvent): boolean {
  const mac = CODE_TO_MAC[e.code];
  // Esc（全停止）は文字入力中でも必ず効かせる
  if (mac === KEY.escape && capturingSequenceKey.peek() === null && pendingAssign.peek() === null) {
    endEditing();
    if (!e.repeat) panic();
    return true;
  }
  if (isTextInput(e.target)) return false;
  if (mac === undefined) return false;

  const pending = pendingAssign.peek();
  if (pending) {
    if (!e.repeat) {
      pendingAssign.value = null;
      if (mac === KEY.escape) return true;
      const reason = reservedReason(mac);
      if (reason) message.value = reason;
      else if (!ALL_KEYS.has(mac)) message.value = L("このキーには割り当てられません（数字・英字・記号・スペースのキーを使ってください）");
      else assign(pending.paths, mac, pending.group);
    }
    return true;
  }
  const capturing = capturingSequenceKey.peek();
  if (capturing) {
    if (mac !== KEY.escape) assignSequenceKey(mac, capturing);
    capturingSequenceKey.value = null;
    return true;
  }
  if (mac === KEY.space) {
    if (!e.repeat) endCurrentSequenceSong();
    return true;
  }
  const cue = cueForKey(mac);
  if (cue) {
    if (!e.repeat) trigger(cue);
    return true;
  }
  const seq = sequenceForKey(mac);
  if (seq) {
    if (!e.repeat) toggleSequence(seq.id);
    return true;
  }
  if (mac === KEY.ret || mac === KEY.enter) {
    if (!e.repeat) advanceActiveSequence();
    return true;
  }
  // delete キー: 音量ラインで選んでいるマークを消す
  if ((mac === 51 || mac === 117) && deleteKeyAction && !prefs.showMode.peek()) {
    deleteKeyAction();
    return true;
  }
  if (mac === KEY.up || mac === KEY.down) {
    moveCue(mac === KEY.up ? -1 : 1);
    return true;
  }
  return false;
}

// MARK: - 音量ラインの書き込み（インスペクタの右のつまみ）

/** 線に、時刻 t の点を書き込む。前に書いた時刻から t までの点は上書きする */
export function writeLinePoint(p: PlaySettings, pts0: { id: Id; time: number; db: number; shape?: { x1: number; y1: number; x2: number; y2: number } }[], value: number, t: number, from: number | null) {
  let pts = [...pts0];
  const linear = { x1: 1 / 3, y1: 1 / 3, x2: 2 / 3, y2: 2 / 3 };
  if (pts.length === 0 && t > p.inPoint + 0.05) pts.push({ id: newId(), time: p.inPoint, db: 0, shape: linear });
  if (from !== null) pts = pts.filter(q => !(q.time > from + 0.001 && q.time <= t + 0.001));
  else pts = pts.filter(q => Math.abs(q.time - t) >= 0.001);
  pts.push({ id: newId(), time: t, db: value, shape: linear });
  pts.sort((a, b) => a.time - b.time);
  return pts;
}

export { simplifyPoints };
