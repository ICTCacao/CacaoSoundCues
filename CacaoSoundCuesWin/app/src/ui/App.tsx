// 画面全体（Mac 版 MainView.swift）
import { L, languageVersion } from "../i18n";
import { signed } from "../model";
import { prefs } from "../prefs";
import {
  applyMasterVolume, dirty, edit, memoryBytes, message, newShowFile, openPanel, output, panic, save, saveAs, settingsOpen,
  show, toggleShowMode,
} from "../store";
import { ContextMenuView, Slider, ToggleButton, openMenu, Split } from "./common";
import { Icon } from "./icons";
import { Inspector } from "./Inspector";
import { Keyboard } from "./Keyboard";
import { KeyList } from "./KeyList";
import { modal } from "./modal";
import { SequencePanel } from "./SequencePanel";
import { Settings } from "./Settings";
import { ShowModePanel } from "./ShowModePanel";

import { signal } from "@preact/signals";
import { getVersion } from "@tauri-apps/api/app";

/** 表示用のバージョン（tauri.conf.json の version） */
export const VERSION = signal("");
getVersion().then(v => { VERSION.value = v; }).catch(() => {});

export function App() {
  void languageVersion.value;   // 言語が変わったら全体を描き直す
  const showMode = prefs.showMode.value;
  const right = <div class="panel">{showMode ? <ShowModePanel /> : <Inspector />}</div>;
  const inspector = prefs.showInspector.value;
  return (
    <div class="app">
      <TopBar />
      {prefs.showKeyboard.value ? <>
        <Keyboard />
        {inspector ? (
          <Split fractions={prefs.splitWithKeyboard} mins={[400, 480]}>
            {[<div class="panel bg"><SequencePanel /></div>, right]}
          </Split>
        ) : (
          <Split fractions={prefs.splitKeyListNoInspector} mins={[400]}>
            {[<div class="panel bg"><SequencePanel /></div>]}
          </Split>
        )}
      </> : inspector ? (
        <Split fractions={prefs.splitKeyList} mins={[260, 380, 460]}>
          {[<div class="panel bg"><KeyList /></div>, <div class="panel bg"><SequencePanel /></div>, right]}
        </Split>
      ) : (
        <Split fractions={prefs.splitKeyListNoInspector} mins={[260, 380]}>
          {[<div class="panel bg"><KeyList /></div>, <div class="panel bg"><SequencePanel /></div>]}
        </Split>
      )}
      <Settings />
      <ModalView />
      <MessageView />
      <ContextMenuView />
    </div>
  );
}

function TopBar() {
  const sh = show.value;
  const showMode = prefs.showMode.value;
  const out = output.value;
  const ms = out.bufferFrames ? (out.bufferFrames / out.sampleRate) * 1000 : 0;
  const fileMenu = (e: MouseEvent) => openMenu(e, [
    { label: L("新規キューシート") + "\tCtrl+N", icon: "plus", action: newShowFile },
    { label: L("開く…") + "\tCtrl+O", icon: "folder", action: openPanel },
    { label: L("保存") + "\tCtrl+S", icon: "save", action: save },
    { label: L("別名で保存…") + "\tCtrl+Shift+S", icon: "save", action: saveAs },
  ]);
  return (
    <header class={"topbar" + (showMode ? " showmode-on" : "")}>
      <button class="ibtn" title={L("ファイル")} onClick={fileMenu} onContextMenu={fileMenu}><Icon name="list" /></button>
      <input class="showname" value={sh.name} disabled={showMode} placeholder={L("キューシート名")}
        onInput={e => edit(s => { s.name = (e.target as HTMLInputElement).value; })}
        onKeyDown={e => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
      <button class="btn" disabled={showMode} onClick={openPanel}><Icon name="folder" />{L("開く…")}</button>
      <button class="btn" onClick={save}><Icon name="save" />{L("保存")}</button>
      <button class={"btn prominent " + (showMode ? "red" : "gray")} onClick={toggleShowMode}
        title={showMode ? L("本番モードを終了して、編集できるようにする") : L("編集を止めて、キー操作と再生だけにする")}>
        <Icon name={showMode ? "lock" : "lockOpen"} />{showMode ? L("本番モード中") : L("本番モード")}
      </button>
      <ToggleButton on={prefs.showKeyboard.value} icon="keyboard" onClick={() => { prefs.showKeyboard.value = !prefs.showKeyboard.value; }}
        title={L("キーボードを隠すと、割り当てたキーだけを一覧で表示します")}>{L("キーボード")}</ToggleButton>
      <ToggleButton on={prefs.showInspector.value} icon="sidebarRight" onClick={() => { prefs.showInspector.value = !prefs.showInspector.value; }}
        title={L("右側の音源設定（本番モードでは本番用の表示）を出す・隠す")}>{L("音源設定")}</ToggleButton>
      <button class="ibtn" title={L("設定") + "（Ctrl+,）"} onClick={() => { settingsOpen.value = true; }}><Icon name="gear" /></button>
      <span class="spacer" />
      <span class="master">
        <Icon name="speaker" />
        <Slider value={sh.masterVolumeDB} min={-40} max={6} onChange={v => { edit(s => { s.masterVolumeDB = v; }); applyMasterVolume(); }} />
        <span class="mono" style={{ width: "64px" }}>{signed(sh.masterVolumeDB)} dB</span>
      </span>
      <button class="btn prominent red" onClick={panic} title={L("全部の音をすぐ止める（フェードなし）")}>
        <Icon name="stop" />{L("全停止（Esc）")}
      </button>
      <div class="outinfo">
        <div>{VERSION.value} ・ {out.deviceName}  {(out.sampleRate / 1000).toFixed(1)}kHz</div>
        <div>{out.bufferFrames
          ? L("バッファ %d（%.1fms）・メモリ %dMB", out.bufferFrames, ms, Math.round(memoryBytes.value / 1048576))
          : L("バッファ 自動・メモリ %dMB", Math.round(memoryBytes.value / 1048576))}</div>
      </div>
      {dirty.value && <span class="dirty-dot" title={L("未保存")} />}
    </header>
  );
}

function ModalView() {
  const m = modal.value;
  if (!m) return null;
  return (
    <div class="sheet-backdrop">
      <div class="sheet alert">
        <h3>{m.title}</h3>
        {m.text && <p class="pre">{m.text}</p>}
        <div class="hrow end">
          {m.buttons.map((b, i) => (
            <button key={i} class={"btn" + (b.kind === "primary" ? " prominent accent" : b.kind === "danger" ? " prominent red" : "")}
              onClick={() => m.resolve(i)}>{b.label}</button>
          ))}
        </div>
      </div>
    </div>
  );
}

function MessageView() {
  const text = message.value;
  if (!text) return null;
  return (
    <div class="sheet-backdrop">
      <div class="sheet alert">
        <h3>{L("お知らせ")}</h3>
        <p class="pre">{text}</p>
        <div class="hrow end"><button class="btn prominent accent" onClick={() => { message.value = null; }}>OK</button></div>
      </div>
    </div>
  );
}
