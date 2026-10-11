// CacaoSoundCues Windows 版の画面（最初の形: キューシートを開いて、キーで鳴らす）
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { CODE_TO_MAC, KEY, KEY_ROWS, ROW_INDENT, keyLabel } from "./keymap";

type Id = string;
interface PlaySettings { soundID: Id; inPoint: number; outPoint?: number; fadeOut: number; volumeDB: number; [k: string]: unknown }
interface SoundRef { id: Id; fileName: string; displayName: string; duration: number }
interface KeyCue { id: Id; keyCode: number; name: string; colorIndex: number; retrigger: string; play: PlaySettings }
interface Show { name: string; sounds: SoundRef[]; keyCues: KeyCue[]; masterVolumeDB: number; panicFade: number; [k: string]: unknown }
interface Status { token: number; owner: Id; tag: Id; position: number; start: number; end: number; armed: boolean; stopping: boolean; looping: boolean; remaining: number }

const COLORS = ["#9e9e9e", "#e53935", "#fb8c00", "#fdd835", "#43a047", "#00acc1", "#1e88e5", "#8e24aa"];
let show: Show | null = null;
let status: Status[] = [];
let lastEscape = 0;

const $ = (id: string) => document.getElementById(id)!;
const message = (text: string) => { $("message").textContent = text; };
const timeText = (t: number) => { const m = Math.floor(Math.max(0, t) / 60); return `${m}:${(Math.max(0, t) - m * 60).toFixed(1).padStart(4, "0")}`; };

async function openShow(path: string) {
  try {
    await invoke("unload_all");
    show = await invoke<Show>("open_show", { path });
    ($("showName") as HTMLInputElement).value = show.name;
    localStorage.setItem("lastShowPath", path);
    await invoke("set_master", { db: show.masterVolumeDB });
    drawKeyboard();
    message(`読み込み中…`);
    const sep = path.includes("\\") ? "\\" : "/";
    await Promise.all(show.sounds.map(s =>
      invoke("load_sound", { id: s.id, path: `${path}${sep}Audio${sep}${s.fileName}` })
        .catch(e => message(`読み込めません: ${s.displayName}（${e}）`))));
    message(`「${show.name}」を開きました（音 ${show.sounds.length}）`);
  } catch (e) {
    message(String(e));
  }
}

function drawKeyboard() {
  const kb = $("keyboard");
  kb.innerHTML = "";
  KEY_ROWS.forEach((row, r) => {
    const div = document.createElement("div");
    div.className = "row";
    div.style.marginLeft = `${ROW_INDENT[r] * 83}px`;
    for (const code of row) {
      const cue = show?.keyCues.find(c => c.keyCode === code);
      const k = document.createElement("div");
      k.className = "key";
      k.dataset.code = String(code);
      if (cue) k.style.background = COLORS[cue.colorIndex % COLORS.length] + "59";
      k.innerHTML = `<div class="label">${keyLabel(code)}</div><div class="name">${cue ? escapeHtml(cue.name) : ""}</div>`;
      div.appendChild(k);
    }
    kb.appendChild(div);
  });
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

/// 鳴っている音を、キーの上に出す（1秒に30回）
function drawStatus() {
  if (!show) return;
  for (const cue of show.keyCues) {
    const k = document.querySelector<HTMLElement>(`.key[data-code="${cue.keyCode}"]`);
    if (!k) continue;
    const v = status.filter(s => s.owner === cue.id && !s.armed).pop();
    k.querySelector(".bar")?.remove();
    k.querySelector(".time")?.remove();
    k.style.background = COLORS[cue.colorIndex % COLORS.length] + (v ? "f2" : "59");
    if (v) {
      const p = Math.min(1, Math.max(0, (v.position - v.start) / Math.max(0.001, v.end - v.start)));
      k.insertAdjacentHTML("beforeend",
        `<div class="bar"><div style="width:${p * 100}%;${v.stopping ? "background:orange" : ""}"></div></div>` +
        `<div class="time">${v.looping ? "∞" : "-" + timeText(v.remaining)}</div>`);
    }
  }
}

async function trigger(cue: KeyCue) {
  const mode = { fadeOut: "toggle", restart: "restart", layer: "play", ignore: "ifIdle" }[cue.retrigger] ?? "toggle";
  await invoke("play", { mode, owner: cue.id, tag: cue.id, settings: cue.play });
}

/// Esc: 全部フェードアウト。1秒以内にもう一度押すとカット
async function panic() {
  const now = Date.now();
  const cut = now - lastEscape < 1000;
  lastEscape = now;
  await invoke("stop_all", { fade: cut ? 0 : show?.panicFade ?? 2 });
}

window.addEventListener("keydown", e => {
  if (e.target instanceof HTMLInputElement) {
    if (e.code === "Escape") (e.target as HTMLInputElement).blur(); else return;
  }
  if (e.ctrlKey || e.altKey || e.metaKey) return;
  const mac = CODE_TO_MAC[e.code];
  if (mac === undefined) return;
  e.preventDefault();
  if (e.repeat) return;
  if (mac === KEY.escape) { panic(); return; }
  const cue = show?.keyCues.find(c => c.keyCode === mac);
  if (cue) trigger(cue);
});

$("btnOpen").addEventListener("click", async () => {
  // キューシートは .ccsc の名前のフォルダ
  const path = await open({ directory: true, title: "キューシート（.ccsc）を開く" });
  if (typeof path === "string") openShow(path);
});
$("btnPanic").addEventListener("click", () => panic());

(async () => {
  const info = await invoke<{ sampleRate: number; deviceName: string; bufferFrames: number }>("output_info");
  $("outInfo").textContent = `${info.deviceName}  ${(info.sampleRate / 1000).toFixed(1)}kHz ・ バッファ ${info.bufferFrames || "自動"}`
    + (info.bufferFrames ? `（${(info.bufferFrames / info.sampleRate * 1000).toFixed(1)}ms）` : "");
  drawKeyboard();
  const start = await invoke<string | null>("startup_file");
  const last = localStorage.getItem("lastShowPath");
  if (start) openShow(start); else if (last) openShow(last);
  setInterval(async () => { status = await invoke<Status[]>("snapshot"); drawStatus(); }, 33);
})();
