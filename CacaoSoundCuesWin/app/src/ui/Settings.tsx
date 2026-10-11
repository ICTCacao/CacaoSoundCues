// 設定（Ctrl+,）: 言語・キーボード・音を追加したときの最初の設定（Mac 版 SettingsView.swift）
import { useEffect, useState } from "preact/hooks";
import { invoke } from "@tauri-apps/api/core";
import { ENGLISH, L, availableLanguages, changeLanguage, currentLanguage, type Language } from "../i18n";
import { defaults, prefs, resetDefaults } from "../prefs";
import { settingsOpen } from "../store";
import { SecondsField, Segmented, Select, Toggle } from "./common";
import { Icon } from "./icons";
import { curveOptions, retriggerOptions, stepStartOptions } from "./Inspector";

function SettingsSeconds({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) {
  return (
    <div class="form-row">
      <span>{label}</span>
      <span class="hrow">
        <SecondsField width={70} value={value} onChange={onChange} />
        <span>{L("秒")}</span>
        <span class="orange" style={{ width: "40px" }}>{value === 0 ? L("カット") : ""}</span>
      </span>
    </div>
  );
}

export function Settings() {
  const [languages, setLanguages] = useState<Language[]>([]);
  const reload = () => availableLanguages().then(setLanguages);
  useEffect(() => { reload(); }, []);
  if (!settingsOpen.value) return null;
  const d = defaults;
  const close = () => { settingsOpen.value = false; };

  return (
    <div class="sheet-backdrop" onMouseDown={close}>
      <div class="sheet settings" onMouseDown={e => e.stopPropagation()}>
        <div class="sheet-head">
          <h2>{L("設定")}</h2>
          <button class="ibtn" onClick={close} title={L("閉じる")}><Icon name="x" /></button>
        </div>
        <div class="sheet-body">
          <section>
            <h4>{L("言語 / Language")}</h4>
            <div class="form-row">
              <span>{L("画面の言語")}</span>
              <Select value={currentLanguage()} options={languages.map(l => ({ value: l.code, label: l.name }))}
                onChange={code => changeLanguage(code)} />
            </div>
            <p class="caption sub">{L("ほかの言語は、翻訳用のひな形（英語）を書き出し、英語の部分を置き換えて言語のフォルダに置くと選べるようになります。訳の無い言葉は英語で表示されます。")}</p>
            <div class="hrow wrap">
              <button class="btn" onClick={async () => { await invoke("export_language_template", { strings: ENGLISH }); reload(); }}>
                <Icon name="export" />{L("翻訳用のひな形を書き出す…")}
              </button>
              <button class="btn" onClick={() => invoke("open_language_folder")}><Icon name="folder" />{L("言語のフォルダを開く")}</button>
              <button class="btn" onClick={reload}><Icon name="refresh" />{L("読み込み直す")}</button>
            </div>
          </section>

          <section>
            <h4>{L("キーボード")}</h4>
            <div class="form-row">
              <span>{L("キーボードの配列")}</span>
              <Segmented value={prefs.layout.value} onChange={v => { prefs.layout.value = v; }}
                options={[{ value: "auto", label: L("自動") }, { value: "jis", label: L("日本語（JIS）") }, { value: "us", label: L("英語（US）") }]} />
            </div>
            <Toggle checked={prefs.showFunctionKeys.value} onChange={v => { prefs.showFunctionKeys.value = v; }}>{L("F キー（F1〜F12）の行を表示")}</Toggle>
            <Toggle checked={prefs.showKeypad.value} onChange={v => { prefs.showKeypad.value = v; }}>{L("テンキーを表示")}</Toggle>
          </section>

          <p class="sub">{L("音を追加したときの最初の設定です。追加したあとは、音ごとに変えられます。")}</p>

          <section>
            <h4>{L("キーに割り当てる音")}</h4>
            <SettingsSeconds label={L("フェードイン")} value={d.keyFadeIn.value} onChange={v => { d.keyFadeIn.value = v; }} />
            <SettingsSeconds label={L("フェードアウト")} value={d.keyFadeOut.value} onChange={v => { d.keyFadeOut.value = v; }} />
            <div class="form-row">
              <span>{L("鳴っている間にもう一度押したら")}</span>
              <Select value={d.keyRetrigger.value} options={retriggerOptions()} onChange={v => { d.keyRetrigger.value = v; }} />
            </div>
          </section>

          <section>
            <h4>{L("リストに追加する曲")}</h4>
            <div class="form-row">
              <span>{L("鳴らし始めるタイミング")}</span>
              <Select value={d.stepStart.value} options={stepStartOptions()} onChange={v => { d.stepStart.value = v; }} />
            </div>
            <SettingsSeconds label={d.stepStart.value === "overlap" ? L("重ねる長さ") : d.stepStart.value === "returnKey" ? L("Enter を押してから待つ時間") : L("前の曲との間")}
              value={d.stepStartSeconds.value} onChange={v => { d.stepStartSeconds.value = v; }} />
            <SettingsSeconds label={L("フェードイン")} value={d.stepFadeIn.value} onChange={v => { d.stepFadeIn.value = v; }} />
            <SettingsSeconds label={L("フェードアウト")} value={d.stepFadeOut.value} onChange={v => { d.stepFadeOut.value = v; }} />
            <Toggle checked={d.stepFadeOutAtEnd.value} onChange={v => { d.stepFadeOutAtEnd.value = v; }}>{L("終了位置に向けて自動でフェードアウトする")}</Toggle>
          </section>

          <section>
            <h4>{L("共通")}</h4>
            <div class="form-row">
              <span>{L("フェードのカーブ")}</span>
              <Segmented value={d.curve.value} options={curveOptions(false)} onChange={v => { d.curve.value = v; }} />
            </div>
          </section>

          <div class="hrow">
            <span class="spacer" />
            <button class="btn" onClick={resetDefaults}><Icon name="undo" />{L("最初の状態に戻す")}</button>
          </div>
        </div>
      </div>
    </div>
  );
}
