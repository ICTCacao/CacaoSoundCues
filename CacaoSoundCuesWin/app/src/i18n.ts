// 画面の言語。日本語の原文をキーにして、言語ファイル（JSON）の訳に置き換える（Mac 版 Lang.swift と同じ）。
// 英語はアプリに同梱（Mac 版の訳 ＋ Windows 版で足した言葉）。ほかの言語は
// %APPDATA%\CacaoSoundCues\Languages に置いた JSON を読む。訳が無い言葉は英語 → 日本語の順に使う。
import { invoke } from "@tauri-apps/api/core";
import { signal } from "@preact/signals";
import enMac from "./lang/en-mac.json";
import enWin from "./lang/en-win.json";

export const ENGLISH: Record<string, string> = { ...enMac.strings, ...enWin.strings };

let table: Record<string, string> = {};
let english: Record<string, string> = {};

export interface Language { code: string; name: string; path?: string }

/** 言語が変わったら画面全体を描き直すための番号 */
export const languageVersion = signal(0);

export const STORAGE_KEY = "language";

export function defaultLanguage(): string {
  return (navigator.language || "ja").startsWith("ja") ? "ja" : "en";
}

export function currentLanguage(): string {
  try { return localStorage.getItem(STORAGE_KEY) ?? defaultLanguage(); } catch { return defaultLanguage(); }
}

export async function availableLanguages(): Promise<Language[]> {
  const list: Language[] = [{ code: "ja", name: "日本語" }, { code: "en", name: "English" }];
  try {
    for (const f of await invoke<Language[]>("list_languages")) {
      if (!list.some(l => l.code === f.code)) list.push(f);
    }
  } catch { /* 言語のフォルダが無くても日本語と英語は使える */ }
  return list;
}

/** 選んである言語を読み込んで、画面の言葉に使う */
export async function applyLanguage(code = currentLanguage()) {
  if (code === "ja") {
    table = {};
    english = {};
  } else {
    english = ENGLISH;
    if (code === "en") {
      table = ENGLISH;
    } else {
      const lang = (await availableLanguages()).find(l => l.code === code);
      table = lang?.path ? await invoke<Record<string, string>>("read_language", { path: lang.path }).catch(() => ({})) : {};
    }
  }
  document.documentElement.lang = code;
  languageVersion.value++;
}

export async function changeLanguage(code: string) {
  try { localStorage.setItem(STORAGE_KEY, code); } catch { /* 保存できなくても今回は切り替える */ }
  await applyLanguage(code);
}

/** 画面に出す言葉。L("保存")、値を差し込むときは L("「%@」を開けません", name) */
export function L(ja: string, ...args: unknown[]): string {
  const f = table[ja] ?? english[ja] ?? ja;
  if (args.length === 0) return f;
  let i = 0;
  return f.replace(/%(%|@|d|\+?\.\d+f)/g, (_m, spec: string) => {
    if (spec === "%") return "%";
    const a = args[i++];
    if (spec === "@") return String(a);
    if (spec === "d") return String(Math.trunc(Number(a)));
    const digits = Number(/\.(\d+)/.exec(spec)![1]);
    const n = Number(a);
    return (spec.startsWith("+") && n >= 0 ? "+" : "") + n.toFixed(digits);
  });
}
