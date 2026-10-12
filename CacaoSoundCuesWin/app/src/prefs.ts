// この PC に保存する設定（Mac 版の UserDefaults の代わり。localStorage に保存）
import { signal, effect, type Signal } from "@preact/signals";
import type { FadeCurve, RetriggerMode, StepStart } from "./model";

function stored<T>(key: string, initial: T): Signal<T> {
  let value = initial;
  try {
    const raw = localStorage.getItem(key);
    if (raw !== null) value = JSON.parse(raw) as T;
  } catch { /* 読めなければ最初の値 */ }
  const s = signal<T>(value);
  effect(() => {
    try { localStorage.setItem(key, JSON.stringify(s.value)); } catch { /* 保存できなくても続ける */ }
  });
  return s;
}

export const prefs = {
  showKeyboard: stored("showKeyboard", true),
  /** 右側の音源設定（本番モードでは本番用の表示）を出すか */
  showInspector: stored("showInspector", true),
  showFunctionKeys: stored("showFunctionKeys", false),
  showKeypad: stored("showKeypad", false),
  /** キーボードの大きさ（1 = いちばん大きい） */
  keyboardScale: stored("keyboardScale", 1),
  /** 本番モード（起動し直しても続く） */
  showMode: stored("showMode", false),
  /** キーボードの配列（auto は Windows の配列から決める） */
  layout: stored<"auto" | "jis" | "us">("keyboardLayout", "auto"),
  lastShowPath: stored<string | null>("lastShowPath", null),
  /** 分割画面の仕切りの位置（割合） */
  splitWithKeyboard: stored<number[]>("split.withKeyboard", [0.45]),
  splitKeyList: stored<number[]>("split.keyList", [0.24, 0.6]),
  /** 音源設定を隠しているとき（キーの一覧とリストの2分割） */
  splitKeyListNoInspector: stored<number[]>("split.keyList.noInspector", [0.4]),
};

/** 音を追加したときの最初の設定（設定画面で変更） */
export const defaults = {
  keyFadeIn: stored("default.key.fadeIn", 0),
  keyFadeOut: stored("default.key.fadeOut", 0),
  keyRetrigger: stored<RetriggerMode>("default.key.retrigger", "fadeOut"),
  stepFadeIn: stored("default.step.fadeIn", 0),
  stepFadeOut: stored("default.step.fadeOut", 0),
  stepFadeOutAtEnd: stored("default.step.fadeOutAtEnd", false),
  stepStart: stored<StepStart>("default.step.start", "returnKey"),
  stepStartSeconds: stored("default.step.startSeconds", 0),
  curve: stored<FadeCurve>("default.curve", "equalPower"),
};

export function resetDefaults() {
  defaults.keyFadeIn.value = 0;
  defaults.keyFadeOut.value = 0;
  defaults.keyRetrigger.value = "fadeOut";
  defaults.stepFadeIn.value = 0;
  defaults.stepFadeOut.value = 0;
  defaults.stepFadeOutAtEnd.value = false;
  defaults.stepStart.value = "returnKey";
  defaults.stepStartSeconds.value = 0;
  defaults.curve.value = "equalPower";
}
