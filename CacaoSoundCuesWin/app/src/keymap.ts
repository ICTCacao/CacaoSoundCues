// キーの対応表。キューシートには Mac のキーコード（物理的なキーの位置）で保存されているので、
// Windows（ブラウザの KeyboardEvent.code）と読み替える。Mac で作ったキューシートを Windows でそのまま使える。

export const MAC_TO_CODE: Record<number, string> = {
  0: "KeyA", 1: "KeyS", 2: "KeyD", 3: "KeyF", 4: "KeyH", 5: "KeyG", 6: "KeyZ", 7: "KeyX", 8: "KeyC", 9: "KeyV",
  11: "KeyB", 12: "KeyQ", 13: "KeyW", 14: "KeyE", 15: "KeyR", 16: "KeyY", 17: "KeyT",
  18: "Digit1", 19: "Digit2", 20: "Digit3", 21: "Digit4", 22: "Digit6", 23: "Digit5", 24: "Equal", 25: "Digit9",
  26: "Digit7", 27: "Minus", 28: "Digit8", 29: "Digit0", 30: "BracketRight", 31: "KeyO", 32: "KeyU",
  33: "BracketLeft", 34: "KeyI", 35: "KeyP", 37: "KeyL", 38: "KeyJ", 39: "Quote", 40: "KeyK", 41: "Semicolon",
  42: "Backslash", 43: "Comma", 44: "Slash", 45: "KeyN", 46: "KeyM", 47: "Period", 50: "Backquote",
  93: "IntlYen", 94: "IntlRo",
  // 操作用
  36: "Enter", 76: "NumpadEnter", 49: "Space", 53: "Escape", 126: "ArrowUp", 125: "ArrowDown", 51: "Backspace", 117: "Delete",
  // F キー
  122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
  // テンキー
  82: "Numpad0", 83: "Numpad1", 84: "Numpad2", 85: "Numpad3", 86: "Numpad4", 87: "Numpad5", 88: "Numpad6",
  89: "Numpad7", 91: "Numpad8", 92: "Numpad9", 65: "NumpadDecimal", 69: "NumpadAdd", 78: "NumpadSubtract",
  67: "NumpadMultiply", 75: "NumpadDivide", 81: "NumpadEqual", 71: "NumLock",
};

export const CODE_TO_MAC: Record<string, number> = Object.fromEntries(
  Object.entries(MAC_TO_CODE).map(([k, v]) => [v, Number(k)]),
);

export const KEY = { escape: 53, space: 49, ret: 36, enter: 76, up: 126, down: 125 };

/// 画面に出すキーの文字（日本語配列の見た目に合わせる）
const LABELS: Record<string, string> = {
  Equal: "^", Minus: "-", BracketRight: "[", BracketLeft: "@", Quote: ":", Semicolon: ";", Backslash: "]",
  Comma: ",", Slash: "/", Period: ".", Backquote: "`", IntlYen: "¥", IntlRo: "_", Space: "space",
  Escape: "esc", NumLock: "clear", Enter: "return", NumpadEnter: "enter",
};

export function keyLabel(mac: number): string {
  const code = MAC_TO_CODE[mac];
  if (!code) return `#${mac}`;
  if (LABELS[code]) return LABELS[code];
  if (code.startsWith("Key")) return code.slice(3);
  if (code.startsWith("Digit")) return code.slice(5);
  if (code.startsWith("Numpad")) {
    const rest = code.slice(6);
    const sym: Record<string, string> = { Decimal: ".", Add: "+", Subtract: "-", Multiply: "*", Divide: "/", Equal: "=" };
    return "num" + (sym[rest] ?? rest);
  }
  return code;
}

/// 画面のキーボード（日本語配列）。Mac 版と同じ並び
export const KEY_ROWS: number[][] = [
  [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 93],
  [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30],
  [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42],
  [6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 94],
];
export const ROW_INDENT = [0, 0.5, 0.75, 1.25];
export const FUNCTION_ROW = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111];
