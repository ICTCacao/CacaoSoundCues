// CacaoSoundCues Windows 版の Rust 側。音（エンジン・読み込み・出力）とキューシートの読み書きを受け持つ。
// 画面は src/ の TypeScript。画面から命令を受け取り、鳴っている状態を返す。

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{mpsc, Arc, Mutex};

use cacaosoundcues_engine::model::{self, PlaySettings, Show};
use cacaosoundcues_engine::{decode_file, Command, DecodedSound, MixerHandle};
use serde::Serialize;
use tauri::{Manager, State};
use tauri_plugin_opener::OpenerExt;

struct AppState {
    mixer: MixerHandle,
    info: OutputInfo,
    /// 読み込み済みの音（ID → 音）。鳴っている最中に消えないよう、ここで持っておく
    sounds: Mutex<HashMap<String, Arc<DecodedSound>>>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct OutputInfo {
    sample_rate: f64,
    device_name: String,
    buffer_frames: u32,
}

fn id_u128(id: &str) -> u128 {
    uuid::Uuid::parse_str(id).map(|u| u.as_u128()).unwrap_or(0)
}

fn id_string(v: u128) -> String {
    uuid::Uuid::from_u128(v).hyphenated().to_string().to_uppercase()
}

/// 出力は専用のスレッドで持つ（Windows の出力の決まりで、出力の窓口を別のスレッドへ渡せないため）
fn start_audio() -> Result<(MixerHandle, OutputInfo), String> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || match cacaosoundcues_engine::start_output(128) {
        Ok((out, handle)) => {
            let info = OutputInfo {
                sample_rate: out.sample_rate,
                device_name: out.device_name.clone(),
                buffer_frames: out.requested_buffer.unwrap_or(0),
            };
            let _ = tx.send(Ok((handle, info)));
            // 出力を持ったまま、アプリが終わるまで待つ
            loop {
                std::thread::park();
                let _ = &out;
            }
        }
        Err(e) => {
            let _ = tx.send(Err(e));
        }
    });
    rx.recv().map_err(|e| e.to_string())?
}

#[tauri::command]
fn output_info(state: State<AppState>) -> OutputInfo {
    state.info.clone()
}

/// キューシート（.ccsc フォルダ）の show.json を読んで返す
#[tauri::command]
fn open_show(path: String) -> Result<Show, String> {
    model::load(&PathBuf::from(path))
}

/// キューシートを保存する。sources は「まだキューシートに無い音の ID → 元のファイルの場所」
#[tauri::command]
fn save_show(path: String, show: Show, sources: HashMap<String, String>) -> Result<Show, String> {
    let pkg = PathBuf::from(&path);
    let old = pkg.clone();
    model::save(&show, &pkg, |s| {
        sources
            .get(&s.id.to_string())
            .map(PathBuf::from)
            .or_else(|| Some(model::audio_path(s, &old)))
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LoadedSound {
    duration: f64,
    peaks: Vec<f32>,
}

/// 音ファイルを読み込んで持っておく（重いので別のスレッドで）
#[tauri::command]
async fn load_sound(state: State<'_, AppState>, id: String, path: String) -> Result<LoadedSound, String> {
    let rate = state.info.sample_rate;
    let path = model::find_audio(&PathBuf::from(&path)).ok_or("ファイルが見つかりません")?;
    let decoded = tauri::async_runtime::spawn_blocking(move || decode_file(&path, rate))
        .await
        .map_err(|e| e.to_string())??;
    let result = LoadedSound { duration: decoded.duration(), peaks: decoded.peaks.clone() };
    state.sounds.lock().unwrap().insert(id, Arc::new(decoded));
    Ok(result)
}

/// 音の長さだけを調べる（ファイルを足したとき）
#[tauri::command]
fn probe_sound(path: String) -> Option<f64> {
    cacaosoundcues_engine::probe_duration(&PathBuf::from(path))
}

#[tauri::command]
fn unload_all(state: State<AppState>) {
    state.mixer.send(Command::StopAll { fade_frames: 0 });
    state.sounds.lock().unwrap().clear();
}

/// 鳴らす。mode は play / toggle / restart / ifIdle。token は画面側で決めた番号（鳴らせたら true）
#[tauri::command]
#[allow(clippy::too_many_arguments)]
fn play(
    state: State<AppState>,
    token: u64,
    mode: String,
    owner: String,
    tag: String,
    settings: PlaySettings,
    follow: Option<u64>,
    gap: Option<f64>,
    crossfade: Option<bool>,
    delay: Option<f64>,
) -> bool {
    let Some(buffer) = state.sounds.lock().unwrap().get(&settings.sound_id.to_string()).map(|s| s.buffer.clone()) else {
        return false;
    };
    let Some(mut spec) = model::make_spec(
        &settings,
        buffer,
        token,
        id_u128(&owner),
        id_u128(&tag),
        follow.unwrap_or(0),
        gap.unwrap_or(0.0),
        crossfade.unwrap_or(false),
    ) else {
        return false;
    };
    spec.delay_frames = (delay.unwrap_or(0.0) * state.info.sample_rate) as i64;
    let cmd = match mode.as_str() {
        "toggle" => Command::Toggle(spec),
        "restart" => Command::Restart(spec),
        "ifIdle" => Command::PlayIfIdle(spec),
        _ => Command::Play(spec),
    };
    state.mixer.send(cmd);
    true
}

/// 読み込み済みの音を手放す（キューシートから消したとき）
#[tauri::command]
fn unload_sound(state: State<AppState>, id: String) {
    state.sounds.lock().unwrap().remove(&id);
}

fn fade_frames(state: &AppState, seconds: Option<f64>) -> i64 {
    seconds.map(|s| (s * state.info.sample_rate) as i64).unwrap_or(-1)
}

#[tauri::command]
fn stop_owner(state: State<AppState>, owner: String, fade: Option<f64>) {
    state.mixer.send(Command::StopOwner { owner: id_u128(&owner), fade_frames: fade_frames(&state, fade) });
}

#[tauri::command]
fn stop_token(state: State<AppState>, token: u64, fade: Option<f64>) {
    state.mixer.send(Command::StopToken { token, fade_frames: fade_frames(&state, fade) });
}

#[tauri::command]
fn stop_all(state: State<AppState>, fade: f64) {
    state.mixer.send(Command::StopAll { fade_frames: (fade * state.info.sample_rate) as i64 });
}

#[tauri::command]
fn set_master(state: State<AppState>, db: f64) {
    state.mixer.send(Command::SetMasterGain(10f32.powf(db as f32 / 20.0)));
}

#[tauri::command]
fn seek(state: State<AppState>, token: u64, seconds: f64) {
    state.mixer.send(Command::Seek { token, frame: (seconds * state.info.sample_rate) as i64 });
}

#[tauri::command]
fn start_now(state: State<AppState>, token: u64) {
    state.mixer.send(Command::StartNow(token));
}

/// 再生中の音の音量・PAN・ラインを、その場で変える（持ち主か印が id の音すべて）
#[tauri::command]
fn live_update(state: State<AppState>, id: String, settings: PlaySettings) {
    let id = id_u128(&id);
    let sr = state.info.sample_rate;
    state.mixer.send(Command::SetGain { id, gain: 10f32.powf(settings.volume_db as f32 / 20.0) });
    state.mixer.send(Command::SetPan { id, pan: settings.pan as f32 });
    state.mixer.send(Command::SetEnvelope { id, envelope: model::envelope(&settings.volume_points, sr) });
    state.mixer.send(Command::SetPanEnvelope { id, envelope: model::envelope(&settings.pan_points, sr) });
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Status {
    token: u64,
    owner: String,
    tag: String,
    position: f64,
    start: f64,
    end: f64,
    armed: bool,
    stopping: bool,
    looping: bool,
    remaining: f64,
    level: f32,
    fading: bool,
    fading_down: bool,
    fade_elapsed: f64,
    fade_length: f64,
    fade_from: f32,
    fade_to: f32,
    starts_in: f64,
    line_gain: f32,
    pan_now: f32,
}

/// 鳴っている音の状態（秒に直して返す）
#[tauri::command]
fn snapshot(state: State<AppState>) -> Vec<Status> {
    let sr = state.info.sample_rate;
    state
        .mixer
        .snapshot()
        .into_iter()
        .map(|v| Status {
            token: v.token,
            owner: id_string(v.owner),
            tag: id_string(v.tag),
            position: v.position as f64 / sr,
            start: v.start_frame as f64 / sr,
            end: v.end_frame as f64 / sr,
            armed: v.armed,
            stopping: v.stopping,
            looping: v.looping,
            remaining: v.remaining_frames as f64 / sr,
            level: v.level,
            fading: v.fading,
            fading_down: v.fading_down,
            fade_elapsed: v.fade_elapsed as f64 / sr,
            fade_length: v.fade_length as f64 / sr,
            fade_from: v.fade_from,
            fade_to: v.fade_to,
            starts_in: if v.starts_in < 0 { -1.0 } else { v.starts_in as f64 / sr },
            line_gain: v.line_gain,
            pan_now: v.pan_now,
        })
        .collect()
}

// MARK: - 言語ファイル（%APPDATA%\\CacaoSoundCues\\Languages に置いた JSON）

fn language_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().data_dir().map_err(|e| e.to_string())?.join("CacaoSoundCues").join("Languages");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

#[derive(Serialize, serde::Deserialize)]
struct LanguageFile {
    name: String,
    code: String,
    strings: HashMap<String, String>,
}

#[derive(Serialize)]
struct LanguageEntry {
    name: String,
    code: String,
    path: String,
}

/// 言語のフォルダにある言語ファイルの一覧
#[tauri::command]
fn list_languages(app: tauri::AppHandle) -> Vec<LanguageEntry> {
    let Ok(dir) = language_dir(&app) else { return vec![] };
    let mut files: Vec<_> = std::fs::read_dir(dir)
        .map(|r| r.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    files.sort();
    files
        .into_iter()
        .filter(|p| p.extension().map(|e| e.eq_ignore_ascii_case("json")).unwrap_or(false))
        .filter_map(|p| {
            let f: LanguageFile = serde_json::from_slice(&std::fs::read(&p).ok()?).ok()?;
            Some(LanguageEntry { name: f.name, code: f.code, path: p.to_string_lossy().to_string() })
        })
        .collect()
}

#[tauri::command]
fn read_language(path: String) -> Result<HashMap<String, String>, String> {
    let f: LanguageFile = serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    Ok(f.strings)
}

/// 翻訳用のひな形（英語の訳）を言語のフォルダに書き出して、フォルダを開く
#[tauri::command]
fn export_language_template(app: tauri::AppHandle, strings: HashMap<String, String>) -> Result<String, String> {
    let dir = language_dir(&app)?;
    let mut path = dir.join("my-language.json");
    let mut n = 2;
    while path.exists() {
        path = dir.join(format!("my-language-{n}.json"));
        n += 1;
    }
    let sorted: std::collections::BTreeMap<_, _> = strings.into_iter().collect();
    let json = serde_json::json!({ "name": "My Language", "code": "xx", "strings": sorted });
    std::fs::write(&path, serde_json::to_vec_pretty(&json).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    let _ = app.opener().reveal_item_in_dir(&path);
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
fn open_language_folder(app: tauri::AppHandle) -> Result<(), String> {
    let dir = language_dir(&app)?;
    app.opener().open_path(dir.to_string_lossy(), None::<&str>).map_err(|e| e.to_string())
}

/// 本番中に Windows がスリープして音が途切れないようにする（Mac 版の beginActivity と同じ役目）
fn keep_awake() {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::System::Power::{SetThreadExecutionState, ES_CONTINUOUS, ES_SYSTEM_REQUIRED};
        SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
    }
}

/// 開発版だけ: マニュアルの画面写真・確認用に、起動時の選択などを環境変数 CSC_DEBUG で渡す
/// （例 CSC_DEBUG="key:18" / "step:0" / "settings" / "keylist"。カンマで区切って複数）
#[tauri::command]
fn debug_options() -> Option<String> {
    if cfg!(debug_assertions) {
        std::env::var("CSC_DEBUG").ok()
    } else {
        None
    }
}

/// 起動時に渡されたキューシート（ダブルクリック・コマンドライン）
#[tauri::command]
fn startup_file() -> Option<String> {
    std::env::args().skip(1).find(|a| {
        let p = std::path::Path::new(a.trim_end_matches(['/', '\\']));
        p.extension().map(|e| e.eq_ignore_ascii_case("ccsc")).unwrap_or(false) && p.join("show.json").exists()
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let (mixer, info) = start_audio().expect("音の出力を開始できません");
    keep_awake();
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState { mixer, info, sounds: Mutex::new(HashMap::new()) })
        .invoke_handler(tauri::generate_handler![
            output_info, open_show, save_show, load_sound, probe_sound, unload_all, play, stop_owner,
            stop_token, stop_all, set_master, seek, start_now, live_update, snapshot, startup_file,
            unload_sound, list_languages, read_language, export_language_template, open_language_folder, debug_options
        ])
        .run(tauri::generate_context!())
        .expect("アプリを起動できません");
}
