//! 自前のミキサー。Mac 版 CueMixer.swift の移植。
//! render は音声スレッドから呼ばれ、メモリ確保もロック待ちもしない。
//! メインスレッドとは MixerHandle（コマンドの受け渡しはロックの要らないリングバッファ、
//! 状態の受け取りは try_lock のみ）でやりとりする。

use std::sync::{Arc, Mutex};

use crate::bezier::{bezier_gain, FadeBezier, FadeCurve};
use crate::envelope::Envelope;

pub const MAX_VOICES: usize = 32;

/// メモリに展開済みの音（左右別の f32、出力のサンプルレートに変換済み）
#[derive(Debug)]
pub struct SampleBuffer {
    pub left: Vec<f32>,
    pub right: Vec<f32>,
    pub sample_rate: f64,
}

impl SampleBuffer {
    pub fn frames(&self) -> usize {
        self.left.len()
    }
}

/// 1回の再生の指定。メインスレッドで作り、コマンドで音声スレッドへ渡す
#[derive(Clone, Debug)]
pub struct VoiceSpec {
    pub token: u64,
    /// 持ち主（キーの音なら KeyCue の id、リストならリストの id）
    pub owner: u128,
    /// 表示用の印（リストなら曲の id）
    pub tag: u128,
    pub buffer: Arc<SampleBuffer>,
    pub start_frame: i64,
    pub end_frame: i64,
    pub looping: bool,
    /// looping のときの再生回数。0 は止めるまでくり返す
    pub loop_count: i64,
    pub gain: f32,
    pub fade_in_frames: i64,
    pub fade_out_frames: i64,
    pub fade_out_at_end: bool,
    pub curve: FadeCurve,
    pub fade_in_bezier: [f32; 4],
    pub fade_out_bezier: [f32; 4],
    /// 音量ライン（dB）。空なら変えない
    pub envelope: Envelope,
    /// 左右（-1〜1）
    pub pan: f32,
    /// PANライン（-1〜1）。pan に足し合わせる
    pub pan_envelope: Envelope,
    /// 0 以外なら、この token の音の終わりを待ってから鳴らす（リストの次の曲）
    pub follow: u64,
    /// follow のとき、先の音の終わりからの間隔。マイナスなら重ねる
    pub gap_frames: i64,
    /// 重ねるとき、先の音を重なりの長さで自動フェードアウトさせる
    pub crossfade: bool,
    /// follow が 0 のとき、このフレーム数だけ待ってから鳴らす（Return を押してから n 秒）
    pub delay_frames: i64,
}

impl VoiceSpec {
    pub fn new(token: u64, owner: u128, tag: u128, buffer: Arc<SampleBuffer>, start_frame: i64, end_frame: i64) -> Self {
        Self {
            token,
            owner,
            tag,
            buffer,
            start_frame,
            end_frame,
            looping: false,
            loop_count: 0,
            gain: 1.0,
            fade_in_frames: 0,
            fade_out_frames: 0,
            fade_out_at_end: false,
            curve: FadeCurve::EqualPower,
            fade_in_bezier: FadeBezier::preset(FadeCurve::EqualPower, true).simd(),
            fade_out_bezier: FadeBezier::preset(FadeCurve::EqualPower, false).simd(),
            envelope: Envelope::default(),
            pan: 0.0,
            pan_envelope: Envelope::default(),
            follow: 0,
            gap_frames: 0,
            crossfade: false,
            delay_frames: 0,
        }
    }
}

#[derive(Clone, Debug)]
pub enum Command {
    /// 鳴らす（重ねる）
    Play(VoiceSpec),
    /// 同じ持ち主が鳴っていればフェードアウトで止め、鳴っていなければ鳴らす
    Toggle(VoiceSpec),
    /// 同じ持ち主の音を止めて頭から鳴らし直す
    Restart(VoiceSpec),
    /// 同じ持ち主が鳴っていなければ鳴らす
    PlayIfIdle(VoiceSpec),
    /// 持ち主の音を止める（待機中の次の曲も取り消す）。fade_frames < 0 なら各音のフェードアウト設定
    StopOwner { owner: u128, fade_frames: i64 },
    StopToken { token: u64, fade_frames: i64 },
    StopAll { fade_frames: i64 },
    SetMasterGain(f32),
    /// 鳴っている音の再生位置を移す
    Seek { token: u64, frame: i64 },
    /// 待っている音を、待たずにすぐ鳴らす
    StartNow(u64),
    SetGain { id: u128, gain: f32 },
    SetEnvelope { id: u128, envelope: Envelope },
    SetPan { id: u128, pan: f32 },
    SetPanEnvelope { id: u128, envelope: Envelope },
}

#[derive(Clone, Debug, Default)]
pub struct VoiceStatus {
    pub token: u64,
    pub owner: u128,
    pub tag: u128,
    pub position: i64,
    pub start_frame: i64,
    pub end_frame: i64,
    pub armed: bool,
    pub stopping: bool,
    pub looping: bool,
    pub remaining_frames: i64,
    pub level: f32,
    pub fading: bool,
    pub fading_down: bool,
    pub fade_elapsed: i64,
    pub fade_length: i64,
    pub fade_from: f32,
    pub fade_to: f32,
    pub starts_in: i64,
    pub line_gain: f32,
    pub pan_now: f32,
}

#[derive(Clone)]
struct Voice {
    in_use: bool,
    armed: bool,
    spec: Option<VoiceSpec>,
    pos: i64,
    env: f32,
    env_from: f32,
    env_to: f32,
    env_pos: i64,
    env_len: i64,
    stopping: bool,
    end_fading: bool,
    crossfade_frames: i64,
    gain_now: f32,
    pan_l_now: f32,
    pan_r_now: f32,
    pan_now: f32,
    pan_block: i32,
    line_gain: f32,
    line_slope: f32,
    line_block: i32,
    repeats_left: i64,
    countdown: i64,
    render_from: usize,
}

impl Default for Voice {
    fn default() -> Self {
        Self {
            in_use: false,
            armed: false,
            spec: None,
            pos: 0,
            env: 0.0,
            env_from: 0.0,
            env_to: 0.0,
            env_pos: 0,
            env_len: 0,
            stopping: false,
            end_fading: false,
            crossfade_frames: 0,
            gain_now: 1.0,
            pan_l_now: 1.0,
            pan_r_now: 1.0,
            pan_now: 0.0,
            pan_block: 0,
            line_gain: 1.0,
            line_slope: 0.0,
            line_block: 0,
            repeats_left: 0,
            countdown: i64::MIN,
            render_from: 0,
        }
    }
}

/// メインスレッド側の窓口
pub struct MixerHandle {
    producer: Mutex<rtrb::Producer<Command>>,
    status: Arc<Mutex<Vec<VoiceStatus>>>,
    pub sample_rate: f64,
}

impl MixerHandle {
    pub fn send(&self, command: Command) {
        if let Ok(mut p) = self.producer.lock() {
            let _ = p.push(command);
        }
    }

    pub fn snapshot(&self) -> Vec<VoiceStatus> {
        self.status.lock().map(|s| s.clone()).unwrap_or_default()
    }
}

/// 音声スレッド側（render を呼ぶ）
pub struct Mixer {
    consumer: rtrb::Consumer<Command>,
    status: Arc<Mutex<Vec<VoiceStatus>>>,
    voices: Vec<Voice>,
    master_target: f32,
    master_current: f32,
    /// カット時のクリック防止（2ms）
    min_fade: i64,
}

impl Mixer {
    /// ミキサーと、メインスレッド用の窓口を作る
    pub fn new(sample_rate: f64) -> (Mixer, MixerHandle) {
        let (producer, consumer) = rtrb::RingBuffer::new(1024);
        let status = Arc::new(Mutex::new(Vec::with_capacity(MAX_VOICES)));
        let mixer = Mixer {
            consumer,
            status: status.clone(),
            voices: vec![Voice::default(); MAX_VOICES],
            master_target: 1.0,
            master_current: 1.0,
            min_fade: ((sample_rate * 0.002) as i64).max(1),
        };
        (mixer, MixerHandle { producer: Mutex::new(producer), status, sample_rate })
    }

    // MARK: 音声スレッド側

    pub fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        while let Ok(c) = self.consumer.pop() {
            self.apply(c);
        }
        left[..n].fill(0.0);
        right[..n].fill(0.0);

        self.activate_armed(n);
        for i in 0..MAX_VOICES {
            if self.voices[i].in_use && !self.voices[i].armed {
                self.render_voice(i, n, left, right);
            }
        }

        let step = (self.master_target - self.master_current) / n.max(1) as f32;
        for f in 0..n {
            self.master_current += step;
            left[f] *= self.master_current;
            right[f] *= self.master_current;
        }
        self.master_current = self.master_target;

        if let Ok(mut st) = self.status.try_lock() {
            st.clear();
            for v in self.voices.iter().filter(|v| v.in_use) {
                let s = v.spec.as_ref().unwrap();
                st.push(VoiceStatus {
                    token: s.token,
                    owner: s.owner,
                    tag: s.tag,
                    position: v.pos,
                    start_frame: s.start_frame,
                    end_frame: s.end_frame,
                    armed: v.armed,
                    stopping: v.stopping,
                    looping: v.repeats_left < 0,
                    remaining_frames: remaining_frames(v),
                    level: v.env,
                    fading: v.env_pos < v.env_len,
                    fading_down: v.env_to < v.env_from,
                    fade_elapsed: v.env_pos,
                    fade_length: v.env_len,
                    fade_from: v.env_from,
                    fade_to: v.env_to,
                    starts_in: if v.armed && v.countdown != i64::MIN { v.countdown } else { -1 },
                    line_gain: v.line_gain,
                    pan_now: v.pan_now,
                });
            }
        }
    }

    fn matches(v: &Voice, id: u128) -> bool {
        v.in_use && v.spec.as_ref().map(|s| s.owner == id || s.tag == id).unwrap_or(false)
    }

    fn apply(&mut self, command: Command) {
        match command {
            Command::Play(s) => self.start(s),
            Command::Toggle(s) => {
                let mut stopped = false;
                for i in 0..MAX_VOICES {
                    if self.is_sounding(i, s.owner) {
                        self.begin_stop(i, -1);
                        stopped = true;
                    }
                }
                if !stopped {
                    self.start(s);
                }
            }
            Command::Restart(s) => {
                for i in 0..MAX_VOICES {
                    if self.is_sounding(i, s.owner) {
                        let f = self.min_fade;
                        self.begin_stop(i, f);
                    }
                }
                self.start(s);
            }
            Command::PlayIfIdle(s) => {
                if !(0..MAX_VOICES).any(|i| self.is_sounding(i, s.owner)) {
                    self.start(s);
                }
            }
            Command::StopOwner { owner, fade_frames } => {
                for i in 0..MAX_VOICES {
                    let v = &self.voices[i];
                    if v.in_use && v.spec.as_ref().map(|s| s.owner == owner).unwrap_or(false) {
                        if v.armed { self.voices[i].in_use = false } else { self.begin_stop(i, fade_frames) }
                    }
                }
            }
            Command::StopToken { token, fade_frames } => {
                for i in 0..MAX_VOICES {
                    let v = &self.voices[i];
                    if v.in_use && v.spec.as_ref().map(|s| s.token == token).unwrap_or(false) {
                        if v.armed { self.voices[i].in_use = false } else { self.begin_stop(i, fade_frames) }
                    }
                }
            }
            Command::StopAll { fade_frames } => {
                for i in 0..MAX_VOICES {
                    if self.voices[i].in_use {
                        if self.voices[i].armed { self.voices[i].in_use = false } else { self.begin_stop(i, fade_frames) }
                    }
                }
            }
            Command::SetMasterGain(g) => self.master_target = g,
            Command::SetPanEnvelope { id, envelope } => {
                for v in self.voices.iter_mut().filter(|v| Self::matches(v, id)) {
                    v.spec.as_mut().unwrap().pan_envelope = envelope;
                    v.pan_block = 0;
                }
            }
            Command::SetPan { id, pan } => {
                for v in self.voices.iter_mut().filter(|v| Self::matches(v, id)) {
                    v.spec.as_mut().unwrap().pan = pan;
                }
            }
            Command::SetEnvelope { id, envelope } => {
                for v in self.voices.iter_mut().filter(|v| Self::matches(v, id)) {
                    v.spec.as_mut().unwrap().envelope = envelope;
                    v.line_block = 0;
                }
            }
            Command::SetGain { id, gain } => {
                for v in self.voices.iter_mut().filter(|v| Self::matches(v, id)) {
                    v.spec.as_mut().unwrap().gain = gain;
                }
            }
            Command::StartNow(token) => {
                for v in self.voices.iter_mut() {
                    if v.in_use && v.armed && v.spec.as_ref().map(|s| s.token == token).unwrap_or(false) {
                        v.countdown = 0;
                    }
                }
            }
            Command::Seek { token, frame } => {
                let min_fade = self.min_fade;
                for v in self.voices.iter_mut() {
                    if v.in_use && !v.armed && v.spec.as_ref().map(|s| s.token == token).unwrap_or(false) {
                        let s = v.spec.as_ref().unwrap();
                        v.pos = frame.clamp(s.start_frame, s.end_frame - 1);
                        v.line_gain = s.envelope.gain(v.pos);
                        v.line_block = 0;
                        v.end_fading = false;
                        // 飛んだ瞬間のプツッを防ぐため、2ms で立ち上げ直す（止めている途中ならそのまま）
                        if !v.stopping {
                            v.env = 0.0;
                            set_env(v, 1.0, min_fade);
                        }
                    }
                }
            }
        }
    }

    fn is_sounding(&self, i: usize, owner: u128) -> bool {
        let v = &self.voices[i];
        v.in_use && !v.armed && !v.stopping && v.spec.as_ref().map(|s| s.owner == owner).unwrap_or(false)
    }

    fn start(&mut self, s: VoiceSpec) {
        if s.end_frame <= s.start_frame {
            return;
        }
        let Some(slot) = (0..MAX_VOICES).find(|&i| !self.voices[i].in_use) else { return };
        let mut v = Voice::default();
        v.in_use = true;
        v.pos = s.start_frame;
        v.repeats_left = if s.looping { if s.loop_count > 0 { s.loop_count - 1 } else { -1 } } else { 0 };
        v.gain_now = s.gain;
        v.pan_now = (s.pan + s.pan_envelope.value(s.start_frame)).clamp(-1.0, 1.0);
        let (l, r) = pan_gains(v.pan_now);
        v.pan_l_now = l;
        v.pan_r_now = r;
        v.line_gain = s.envelope.gain(s.start_frame);
        if s.follow != 0 {
            v.armed = true;
        } else if s.delay_frames > 0 {
            v.armed = true;
            v.countdown = s.delay_frames;
        } else {
            set_env(&mut v, 1.0, self.min_fade.max(s.fade_in_frames));
        }
        v.spec = Some(s);
        // 前の音の spec（Arc）をここで手放す。音データ本体はメインスレッドが持っているので、解放は起きない
        self.voices[slot] = v;
    }

    fn begin_stop(&mut self, i: usize, fade: i64) {
        let v = &mut self.voices[i];
        let own = v.spec.as_ref().map(|s| s.fade_out_frames).unwrap_or(0);
        let len = self.min_fade.max(if fade < 0 { own } else { fade });
        // すでに止めている途中なら、より短い方を採る（Esc 2度押しでカットするため）
        if v.stopping && v.env_len - v.env_pos <= len {
            return;
        }
        set_env(v, 0.0, len);
        v.stopping = true;
    }

    /// 前の曲の残りフレームから、次の曲を鳴らし始める位置を決める（サンプル単位で正確）
    fn activate_armed(&mut self, n: usize) {
        let n = n as i64;
        for i in 0..MAX_VOICES {
            if !(self.voices[i].in_use && self.voices[i].armed) {
                continue;
            }
            let (follow, gap, crossfade, fade_in) = {
                let s = self.voices[i].spec.as_ref().unwrap();
                (s.follow, s.gap_frames, s.crossfade, s.fade_in_frames)
            };
            // 先の音もまだ待っているなら、それが鳴り始めるまで待つ
            if follow != 0
                && self.voices.iter().any(|v| v.in_use && v.armed && v.spec.as_ref().map(|s| s.token == follow).unwrap_or(false))
            {
                continue;
            }
            let leader = (0..MAX_VOICES).find(|&j| {
                let v = &self.voices[j];
                v.in_use && !v.armed && v.spec.as_ref().map(|s| s.token == follow).unwrap_or(false)
            });
            let start_in;
            if let (true, Some(j)) = (follow != 0, leader) {
                // クロスフェード: 先の曲に「終わりで自動フェードアウト」が無ければ、重なりの長さで消えていくようにする
                if crossfade && gap < 0 && !self.voices[j].spec.as_ref().unwrap().fade_out_at_end {
                    self.voices[j].crossfade_frames = -gap;
                }
                let l = &self.voices[j];
                if l.stopping || l.repeats_left < 0 {
                    self.voices[i].countdown = i64::MIN;
                    continue;
                }
                start_in = remaining_frames(l) + gap;
            } else {
                let c = self.voices[i].countdown;
                start_in = if c == i64::MIN { gap.max(0) } else { c };
            }
            if start_in < n {
                let min_fade = self.min_fade;
                let v = &mut self.voices[i];
                v.armed = false;
                v.render_from = start_in.max(0) as usize;
                set_env(v, 1.0, min_fade.max(fade_in));
            } else {
                self.voices[i].countdown = start_in - n;
            }
        }
    }

    fn render_voice(&mut self, i: usize, n: usize, left: &mut [f32], right: &mut [f32]) {
        let v = &mut self.voices[i];
        let spec = v.spec.clone().unwrap();
        let src_l = &spec.buffer.left;
        let src_r = &spec.buffer.right;
        let frames = src_l.len().min(src_r.len()) as i64;
        let gain_target = spec.gain;
        // PANラインが無ければ、このサイクルのあいだに pan へ滑らかに近づける。あれば 8 フレームごとに計算する
        let has_pan_line = !spec.pan_envelope.is_empty();
        let (pan_l_target, pan_r_target) = pan_gains(spec.pan);
        let pan_frames = ((n - v.render_from).max(1)) as f32;
        let mut pan_l_step = if has_pan_line { 0.0 } else { (pan_l_target - v.pan_l_now) / pan_frames };
        let mut pan_r_step = if has_pan_line { 0.0 } else { (pan_r_target - v.pan_r_now) / pan_frames };
        if !has_pan_line {
            v.pan_now = spec.pan;
        }
        let gain_step = (gain_target - v.gain_now) / pan_frames;
        let mut f = v.render_from;
        v.render_from = 0;
        while f < n {
            if v.pos >= spec.end_frame {
                if v.repeats_left != 0 {
                    v.pos = spec.start_frame;
                    v.line_gain = spec.envelope.gain(v.pos);
                    v.line_block = 0;
                    if v.repeats_left > 0 {
                        v.repeats_left -= 1;
                    }
                } else {
                    v.in_use = false;
                    break;
                }
            }
            // 自動フェードアウトはくり返しの最後の回だけ（自分の設定が優先、無ければクロスフェード）
            let end_fade = if spec.fade_out_at_end { spec.fade_out_frames } else { v.crossfade_frames };
            if end_fade > 0 && v.repeats_left == 0 && !v.stopping && !v.end_fading {
                let remain = spec.end_frame - v.pos;
                if remain <= end_fade {
                    set_env(v, 0.0, remain);
                    v.end_fading = true;
                }
            }
            let mut g = v.env_to;
            if v.env_pos < v.env_len {
                let p = v.env_pos as f32 / v.env_len as f32;
                let rising = v.env_to > v.env_from;
                let s = if spec.curve == FadeCurve::Custom {
                    if rising { bezier_gain(spec.fade_in_bezier, true, p) } else { 1.0 - bezier_gain(spec.fade_out_bezier, false, p) }
                } else {
                    shape(p, rising, spec.curve)
                };
                g = v.env_from + (v.env_to - v.env_from) * s;
                v.env_pos += 1;
            } else if v.stopping {
                v.in_use = false;
                break;
            }
            v.env = g;
            v.gain_now += gain_step;
            if !spec.envelope.is_empty() {
                if v.line_block == 0 {
                    let target = spec.envelope.gain(v.pos + 8);
                    v.line_slope = (target - v.line_gain) / 8.0;
                    v.line_block = 8;
                }
                v.line_gain += v.line_slope;
                v.line_block -= 1;
            }
            let a = g * v.gain_now * v.line_gain;
            if has_pan_line {
                if v.pan_block == 0 {
                    let p = (spec.pan + spec.pan_envelope.value(v.pos + 8)).clamp(-1.0, 1.0);
                    let (tl, tr) = pan_gains(p);
                    pan_l_step = (tl - v.pan_l_now) / 8.0;
                    pan_r_step = (tr - v.pan_r_now) / 8.0;
                    v.pan_now = p;
                    v.pan_block = 8;
                }
                v.pan_block -= 1;
            }
            v.pan_l_now += pan_l_step;
            v.pan_r_now += pan_r_step;
            if v.pos >= 0 && v.pos < frames {
                let k = v.pos as usize;
                left[f] += src_l[k] * a * v.pan_l_now;
                right[f] += src_r[k] * a * v.pan_r_now;
            }
            v.pos += 1;
            f += 1;
        }
        v.gain_now = gain_target;
        if !has_pan_line {
            v.pan_l_now = pan_l_target;
            v.pan_r_now = pan_r_target;
        }
        // 手元の spec の写し（Arc の参照）はここで手放す。本体は voice 側に残っている
        drop(spec);
    }
}

fn set_env(v: &mut Voice, target: f32, len: i64) {
    v.env_from = v.env;
    v.env_to = target;
    v.env_pos = 0;
    v.env_len = len;
}

fn remaining_frames(v: &Voice) -> i64 {
    let s = v.spec.as_ref().unwrap();
    (s.end_frame - v.pos) + v.repeats_left.max(0) * (s.end_frame - s.start_frame)
}

/// 左右の釣り合い（バランス）。中央は左右とも 1、片側に寄せると反対側が下がる
#[inline(always)]
fn pan_gains(pan: f32) -> (f32, f32) {
    let p = pan.clamp(-1.0, 1.0);
    let half_pi = std::f32::consts::FRAC_PI_2;
    let l = if p <= 0.0 { 1.0 } else { (p * half_pi).cos() };
    let r = if p >= 0.0 { 1.0 } else { (-p * half_pi).cos() };
    (l, r)
}

#[inline(always)]
fn shape(p: f32, rising: bool, curve: FadeCurve) -> f32 {
    let pi = std::f32::consts::PI;
    match curve {
        FadeCurve::Linear | FadeCurve::Custom => p,
        FadeCurve::EqualPower => if rising { (p * pi / 2.0).sin() } else { 1.0 - (p * pi / 2.0).cos() },
        FadeCurve::SCurve => 0.5 - 0.5 * (p * pi).cos(),
    }
}
