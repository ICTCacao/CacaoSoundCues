// CacaoSoundCues Windows 版の画面の入口。音は Rust 側、画面はここから
import { render } from "preact";
import { effect } from "@preact/signals";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { L, applyLanguage, languageVersion } from "./i18n";
import { detectLayout, setLayout } from "./keymap";
import { prefs } from "./prefs";
import {
  appendSteps, applyMasterVolume, assign, confirmDiscard, confirmQuit, dirty, dropTarget, endEditing, handleKeyDown,
  message, newShowFile, selection, selectedSequenceID, openPanel, openShow, output, pendingAssign, save, saveAs, settingsOpen, show, tick,
  toggleShowMode, type OutputInfo,
} from "./store";
import { App } from "./ui/App";
import { contextMenu } from "./ui/common";
import { modal } from "./ui/modal";

const win = getCurrentWindow();

// キーボード: アプリのショートカット（Ctrl+…）と、音を鳴らすキー
window.addEventListener("keydown", e => {
  if (modal.peek() || message.peek()) {
    if (e.key === "Enter" && message.peek()) { message.value = null; e.preventDefault(); }
    if (e.code !== "Escape") return;   // ダイアログ中も Esc（全停止）だけは効かせる
  }
  if (contextMenu.peek() && e.code === "Escape") contextMenu.value = null;
  if (e.ctrlKey && !e.altKey) {
    const k = e.key.toLowerCase();
    const run = (f: () => unknown) => { e.preventDefault(); f(); };
    if (k === "n") return run(newShowFile);
    if (k === "o") return run(openPanel);
    if (k === "s") return run(e.shiftKey ? saveAs : save);
    if (k === "l" && e.shiftKey) return run(toggleShowMode);
    if (k === ",") return run(() => { settingsOpen.value = true; });
    // ブラウザの再読み込み・印刷・検索などは使わない（本番中に画面が消えないように）
    if (["r", "p", "f", "g", "j", "u", "h"].includes(k) || e.key === "+" || e.key === "-" || e.key === "0") e.preventDefault();
    return;
  }
  if (e.altKey || e.metaKey) return;
  if (e.key === "F5" || e.key === "F7" || e.key === "F12" || e.key === "F3") e.preventDefault();
  if (handleKeyDown(e)) e.preventDefault();
}, true);

// スペースや Enter でボタンが押されないよう、キーを離したときも止める
window.addEventListener("keyup", e => {
  const t = e.target as HTMLElement;
  if ((e.code === "Space" || e.code === "Enter") && t.tagName === "BUTTON") e.preventDefault();
}, true);

// ボタンやスライダーを押したら選択を外す（キーがボタンではなく音出しに届くように）
window.addEventListener("pointerup", () => {
  setTimeout(() => {
    const a = document.activeElement as HTMLElement | null;
    if (!a || a === document.body) return;
    const text = a instanceof HTMLTextAreaElement || (a instanceof HTMLInputElement && !["checkbox", "radio", "range", "button"].includes(a.type));
    if (!text && a.tagName !== "SELECT") a.blur();
  }, 0);
});
window.addEventListener("contextmenu", e => e.preventDefault());

// 音ファイル・キューシートのドロップ（Windows のエクスプローラーから）
function dropAt(x: number, y: number): string | null {
  const scale = window.devicePixelRatio || 1;
  const el = document.elementFromPoint(x / scale, y / scale)?.closest<HTMLElement>("[data-drop]");
  return el?.dataset.drop ?? null;
}

getCurrentWebview().onDragDropEvent(async ev => {
  const p = ev.payload;
  if (p.type === "over" || p.type === "enter") {
    dropTarget.value = prefs.showMode.peek() ? null : dropAt(p.position.x, p.position.y);
    return;
  }
  if (p.type === "leave") { dropTarget.value = null; return; }
  dropTarget.value = null;
  const paths = p.paths;
  if (paths.length === 0) return;
  // キューシート（.ccsc のフォルダ）なら開く
  const pkg = paths.find(x => x.toLowerCase().replace(/[\\/]+$/, "").endsWith(".ccsc"));
  if (pkg) {
    if (await confirmDiscard()) openShow(pkg);
    return;
  }
  if (prefs.showMode.peek()) return;
  const target = dropAt(p.position.x, p.position.y);
  if (!target) return;
  const [kind, arg] = target.split(":");
  if (kind === "key") await assign(paths, Number(arg));
  else if (kind === "keylist") pendingAssign.value = { paths, group: null };
  else if (kind === "group") pendingAssign.value = { paths, group: arg };
  else if (kind === "sequence") await appendSteps(paths, arg);
});

// ウィンドウの題名（本番モード・未保存の印）
effect(() => {
  void languageVersion.value;
  const title = (prefs.showMode.value ? L("● 本番モード — ") : "") + show.value.name + (dirty.value ? L(" — 未保存") : "") + " — CacaoSoundCues";
  win.setTitle(title);
});

// 閉じるときの確認（本番モード・再生中・未保存）
win.onCloseRequested(async e => {
  if (!(await confirmQuit())) e.preventDefault();
});

async function start() {
  await applyLanguage();
  // キーボードの配列（自動なら Windows の配列から）
  effect(() => {
    const l = prefs.layout.value;
    if (l === "auto") detectLayout().then(d => { setLayout(d); languageVersion.value++; });
    else { setLayout(l); languageVersion.value++; }
  });
  render(<App />, document.getElementById("app")!);
  try {
    output.value = await invoke<OutputInfo>("output_info");
  } catch (e) {
    message.value = L("音声出力を開始できません: %@", String(e));
  }
  applyMasterVolume();
  const startFile = await invoke<string | null>("startup_file");
  const last = prefs.lastShowPath.peek();
  if (startFile) await openShow(startFile, true);
  else if (last) await openShow(last, true, true);
  await applyDebugOptions();
  // 起動直後に文字入力欄が選ばれていると、キーを押しても鳴らないため
  setTimeout(endEditing, 200);
  // 1秒に30回、鳴っている音の状態を取る（前の回が終わってから次へ）
  const loop = async () => {
    await tick();
    setTimeout(loop, 33);
  };
  loop();
}

/** 開発版だけ: 起動時の選択（画面写真・確認用） */
async function applyDebugOptions() {
  const opts = await invoke<string | null>("debug_options").catch(() => null);
  if (!opts) return;
  for (const o of opts.split(",")) {
    const [k, v] = o.trim().split(":");
    if (k === "key") selection.value = { kind: "key", code: Number(v) };
    if (k === "step") {
      const seq = show.peek().sequences[0];
      const st = seq?.steps[Number(v)];
      if (seq && st) { selectedSequenceID.value = seq.id; selection.value = { kind: "step", sequence: seq.id, step: st.id }; }
    }
    if (k === "settings") settingsOpen.value = true;
    if (k === "keylist") prefs.showKeyboard.value = false;
    if (k === "keyboard") prefs.showKeyboard.value = true;
  }
}

start();
