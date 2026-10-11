//! キューシート（.ccsc）のデータ。Mac 版 Model.swift / ShowPackage.swift と同じ形の JSON を読み書きする。
//! Mac で作ったキューシートを Windows でそのまま開け、その逆もできる。
//!
//! .ccsc はフォルダ: show.json と Audio/（音ファイルのコピー。名前は「ID-元の名前」）。

use std::collections::HashSet;
use std::fmt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use uuid::Uuid;

pub const FILE_EXTENSION: &str = "ccsc";
pub const AUDIO_FOLDER: &str = "Audio";
pub const SHOW_FILE: &str = "show.json";

/// ID（Mac 版の UUID と同じく、大文字の文字列で書く）
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Id(pub Uuid);

impl Id {
    pub fn new() -> Self {
        Id(Uuid::new_v4())
    }
    /// ミキサーで使う数値
    pub fn as_u128(&self) -> u128 {
        self.0.as_u128()
    }
}

impl Default for Id {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Debug for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self)
    }
}

impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.hyphenated().to_string().to_uppercase())
    }
}

impl Serialize for Id {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for Id {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Uuid::parse_str(&s).map(Id).map_err(serde::de::Error::custom)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum FadeCurve {
    Linear,
    #[default]
    EqualPower,
    SCurve,
    Custom,
}

impl From<FadeCurve> for crate::bezier::FadeCurve {
    fn from(c: FadeCurve) -> Self {
        match c {
            FadeCurve::Linear => Self::Linear,
            FadeCurve::EqualPower => Self::EqualPower,
            FadeCurve::SCurve => Self::SCurve,
            FadeCurve::Custom => Self::Custom,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum RetriggerMode {
    #[default]
    FadeOut,
    Restart,
    Layer,
    Ignore,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum StepStart {
    AfterPrevious,
    Overlap,
    /// 以前の "manual"（自動再生しない）も Return 待ちとして読む
    #[default]
    #[serde(alias = "manual")]
    ReturnKey,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct FadeBezier {
    pub x1: f64,
    pub y1: f64,
    pub x2: f64,
    pub y2: f64,
}

impl From<FadeBezier> for crate::bezier::FadeBezier {
    fn from(b: FadeBezier) -> Self {
        Self::new(b.x1, b.y1, b.x2, b.y2)
    }
}

/// 音量ライン・PANライン の点（db に、音量ラインは dB、PANライン は -1〜1 を入れる）
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct VolumePoint {
    pub id: Id,
    pub time: f64,
    pub db: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub shape: Option<FadeBezier>,
}

/// 点と点をつなぐ最初の形（S字）
pub const DEFAULT_LINE_SHAPE: FadeBezier = FadeBezier { x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0 };

fn d_zero() -> f64 {
    0.0
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaySettings {
    #[serde(rename = "soundID")]
    pub sound_id: Id,
    #[serde(default = "d_zero")]
    pub in_point: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub out_point: Option<f64>,
    #[serde(default)]
    pub fade_in: f64,
    #[serde(default)]
    pub fade_out: f64,
    #[serde(default)]
    pub fade_out_at_end: bool,
    #[serde(default, rename = "loop")]
    pub looping: bool,
    #[serde(default)]
    pub loop_count: i64,
    #[serde(default, rename = "volumeDB")]
    pub volume_db: f64,
    #[serde(default)]
    pub curve: FadeCurve,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fade_in_bezier: Option<FadeBezier>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fade_out_bezier: Option<FadeBezier>,
    #[serde(default)]
    pub volume_points: Vec<VolumePoint>,
    #[serde(default)]
    pub pan: f64,
    #[serde(default)]
    pub pan_points: Vec<VolumePoint>,
}

impl PlaySettings {
    pub fn new(sound_id: Id) -> Self {
        Self {
            sound_id,
            in_point: 0.0,
            out_point: None,
            fade_in: 0.0,
            fade_out: 0.0,
            fade_out_at_end: false,
            looping: false,
            loop_count: 0,
            volume_db: 0.0,
            curve: FadeCurve::EqualPower,
            fade_in_bezier: None,
            fade_out_bezier: None,
            volume_points: vec![],
            pan: 0.0,
            pan_points: vec![],
        }
    }

    /// 実際に使うフェードの形（custom 以外は決まった形）
    pub fn bezier(&self, rising: bool) -> crate::bezier::FadeBezier {
        use crate::bezier::FadeBezier as B;
        if self.curve == FadeCurve::Custom {
            if let Some(b) = if rising { self.fade_in_bezier } else { self.fade_out_bezier } {
                return b.into();
            }
        }
        let c = if self.curve == FadeCurve::Custom { FadeCurve::EqualPower } else { self.curve };
        B::preset(c.into(), rising)
    }

    /// 何回鳴るか。None は止めるまでくり返す
    pub fn plays(&self) -> Option<i64> {
        if !self.looping {
            Some(1)
        } else if self.loop_count > 0 {
            Some(self.loop_count)
        } else {
            None
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SoundRef {
    pub id: Id,
    pub file_name: String,
    pub display_name: String,
    pub duration: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyCue {
    pub id: Id,
    /// Mac のキーコード（Windows では画面側で KeyboardEvent.code と読み替える）
    pub key_code: u16,
    pub name: String,
    #[serde(default)]
    pub color_index: i64,
    #[serde(default)]
    pub retrigger: RetriggerMode,
    pub play: PlaySettings,
    #[serde(default, rename = "groupID", skip_serializing_if = "Option::is_none")]
    pub group_id: Option<Id>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KeyGroup {
    pub id: Id,
    pub name: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SequenceStep {
    pub id: Id,
    pub name: String,
    pub play: PlaySettings,
    #[serde(default)]
    pub start: StepStart,
    #[serde(default)]
    pub start_seconds: f64,
}

fn d_stop_fade() -> f64 {
    3.0
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CueSequence {
    pub id: Id,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub toggle_key: Option<u16>,
    #[serde(default)]
    pub steps: Vec<SequenceStep>,
    #[serde(default, rename = "loop")]
    pub looping: bool,
    #[serde(default = "d_stop_fade")]
    pub stop_fade: f64,
}

fn d_version() -> i64 {
    1
}
fn d_panic() -> f64 {
    2.0
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Show {
    #[serde(default = "d_version")]
    pub format_version: i64,
    pub name: String,
    #[serde(default)]
    pub sounds: Vec<SoundRef>,
    #[serde(default)]
    pub key_cues: Vec<KeyCue>,
    #[serde(default)]
    pub key_groups: Vec<KeyGroup>,
    #[serde(default)]
    pub sequences: Vec<CueSequence>,
    #[serde(default, rename = "masterVolumeDB")]
    pub master_volume_db: f64,
    #[serde(default = "d_panic")]
    pub panic_fade: f64,
}

impl Show {
    pub fn new(name: &str) -> Self {
        Self {
            format_version: 1,
            name: name.to_string(),
            sounds: vec![],
            key_cues: vec![],
            key_groups: vec![],
            sequences: vec![],
            master_volume_db: 0.0,
            panic_fade: 2.0,
        }
    }
}

/// 音量ラインの、ある時刻（秒）の値。点が無ければ 0（Mac 版 volumeLineDB と同じ）
pub fn line_value(points: &[VolumePoint], t: f64) -> f64 {
    let Some(first) = points.first() else { return 0.0 };
    if t <= first.time {
        return first.db;
    }
    for w in points.windows(2) {
        let (a, b) = (&w[0], &w[1]);
        if t < b.time {
            let p = (t - a.time) / (b.time - a.time).max(1e-9);
            let shape: crate::bezier::FadeBezier = a.shape.unwrap_or(DEFAULT_LINE_SHAPE).into();
            return a.db + (b.db - a.db) * shape.gain(p, true);
        }
    }
    points.last().unwrap().db
}

/// 点をミキサー用の線にする
pub fn envelope(points: &[VolumePoint], sample_rate: f64) -> crate::envelope::Envelope {
    let pts: Vec<_> = points
        .iter()
        .map(|p| {
            let s: crate::bezier::FadeBezier = p.shape.unwrap_or(DEFAULT_LINE_SHAPE).into();
            (p.time, p.db, s.simd())
        })
        .collect();
    crate::envelope::Envelope::from_points(&pts, sample_rate)
}

// MARK: - 読み書き

pub fn load(package: &Path) -> Result<Show, String> {
    let data = std::fs::read(package.join(SHOW_FILE)).map_err(|e| format!("開けません: {e}"))?;
    serde_json::from_slice(&data).map_err(|e| format!("開けません: {e}"))
}

pub fn audio_path(sound: &SoundRef, package: &Path) -> PathBuf {
    package.join(AUDIO_FOLDER).join(&sound.file_name)
}

/// 保存する。まだパッケージに無い音は source から Audio/ にコピーし、使っていない音ファイルは消す。
/// file_name を書き換えた Show を返す（Mac 版 ShowPackage.save と同じ）
pub fn save(show: &Show, package: &Path, source: impl Fn(&SoundRef) -> Option<PathBuf>) -> Result<Show, String> {
    let mut out = show.clone();
    let audio_dir = package.join(AUDIO_FOLDER);
    std::fs::create_dir_all(&audio_dir).map_err(|e| format!("保存できません: {e}"))?;
    let mut keep = HashSet::new();
    for s in out.sounds.iter_mut() {
        let prefix = format!("{}-", s.id);
        let name = if s.file_name.starts_with(&prefix) { s.file_name.clone() } else { format!("{prefix}{}", s.file_name) };
        let dest = audio_dir.join(&name);
        if !dest.exists() {
            let src = source(s).filter(|p| p.exists()).ok_or(format!("音ファイルが見つかりません: {}", s.display_name))?;
            std::fs::copy(&src, &dest).map_err(|e| format!("保存できません: {e}"))?;
        }
        s.file_name = name.clone();
        keep.insert(name);
    }
    if let Ok(entries) = std::fs::read_dir(&audio_dir) {
        for e in entries.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if !keep.contains(&name) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    let json = serde_json::to_vec_pretty(&out).map_err(|e| e.to_string())?;
    let tmp = package.join(format!("{SHOW_FILE}.tmp"));
    std::fs::write(&tmp, json).map_err(|e| format!("保存できません: {e}"))?;
    std::fs::rename(&tmp, package.join(SHOW_FILE)).map_err(|e| format!("保存できません: {e}"))?;
    Ok(out)
}
