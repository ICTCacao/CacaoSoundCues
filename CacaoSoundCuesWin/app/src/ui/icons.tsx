// ボタンの小さなアイコン（Mac 版の SF Symbols の代わり。線で描く）
const P: Record<string, string> = {
  folder: "M3 6.5h6l2 2h10v10.5H3z",
  save: "M12 3v11M7.5 9.5 12 14l4.5-4.5M4 15v5h16v-5",
  lock: "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3",
  lockOpen: "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 6.8-1.2",
  keyboard: "M3 7h18v11H3zM6.5 10.5h1M10.5 10.5h1M14.5 10.5h1M8 14.5h8",
  sliders: "M4 7h9M17 7h3M4 17h3M11 17h9M15 5v4M9 15v4",
  speaker: "M4 10h3l5-4v12l-5-4H4zM15.5 9.5a3.5 3.5 0 0 1 0 5M18 7a7 7 0 0 1 0 10",
  stop: "M7 7h10v10H7z",
  play: "M8 5.5v13l10-6.5z",
  plus: "M12 5v14M5 12h14",
  minus: "M5 12h14",
  trash: "M5 7h14M9.5 7V4.5h5V7M7 7l1 13h8l1-13",
  x: "M6.5 6.5l11 11M17.5 6.5l-11 11",
  xCircle: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM9 9l6 6M15 9l-6 6",
  returnKey: "M19 5v6a3 3 0 0 1-3 3H6M9.5 10.5 6 14l3.5 3.5",
  repeat: "M5 11V9.5A2.5 2.5 0 0 1 7.5 7H18M15 4l3 3-3 3M19 13v1.5a2.5 2.5 0 0 1-2.5 2.5H6M9 20l-3-3 3-3",
  up: "M6 15l6-6 6 6",
  down: "M6 9l6 6 6-6",
  folderPlus: "M3 6.5h6l2 2h10v10.5H3zM12 11v5M9.5 13.5h5",
  gear: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8",
  leftRight: "M4 12h16M7.5 8.5 4 12l3.5 3.5M16.5 8.5 20 12l-3.5 3.5",
  lineChart: "M4 18l5-6 4 3 7-9M4 4v16h16",
  note: "M9 17.5V5.5l10-2v12M9 17.5a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0zM19 15.5a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z",
  list: "M8 6h12M8 12h12M8 18h12M4 6h.5M4 12h.5M4 18h.5",
  wave: "M3 12h2M7 8v8M11 5v14M15 9v6M19 11v2",
  warning: "M12 3.5 2.5 20h19zM12 10v4.5M12 17v.5",
  speakerOn: "M4 10h3l5-4v12l-5-4H4zM15.5 9.5a3.5 3.5 0 0 1 0 5",
  playPause: "M5 6v12l7-6zM15 6v12M19 6v12",
  tray: "M3 13l3-8h12l3 8v6H3zM3 13h5l1.5 2.5h5L16 13h5",
  undo: "M9 14 4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3",
  refresh: "M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7",
  export: "M12 15V3M7.5 7.5 12 3l4.5 4.5M5 13v7h14v-7",
};

export function Icon({ name, size = 15 }: { name: keyof typeof P | string; size?: number }) {
  return (
    <svg class="icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d={P[name] ?? ""} />
    </svg>
  );
}
