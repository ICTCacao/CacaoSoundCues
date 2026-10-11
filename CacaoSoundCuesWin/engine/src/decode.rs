//! 音ファイルの読み込み。wav / aiff / mp3 / m4a（AAC・ALAC）/ flac などを全部メモリに展開し、
//! 出力のサンプルレートに変換する（Mac 版 AudioDecoder.swift と同じ役目）。

use std::path::Path;
use std::sync::Arc;

use rubato::{FftFixedIn, Resampler};
use symphonia::core::audio::SampleBuffer as SymBuffer;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

use crate::mixer::SampleBuffer;

/// 読み込んだ音と、波形表示用の山（区間ごとの最大振幅）
pub struct DecodedSound {
    pub buffer: Arc<SampleBuffer>,
    pub peaks: Vec<f32>,
}

impl DecodedSound {
    pub fn duration(&self) -> f64 {
        self.buffer.frames() as f64 / self.buffer.sample_rate
    }
}

/// 音ファイルを読み、sample_rate に変換して返す
pub fn decode_file(path: &Path, sample_rate: f64) -> Result<DecodedSound, String> {
    let (left, right, src_rate) = decode_raw(path)?;
    let (left, right) = if (src_rate as f64 - sample_rate).abs() < 0.5 {
        (left, right)
    } else {
        resample(&left, &right, src_rate as usize, sample_rate as usize)?
    };
    let peaks = make_peaks(&left, &right, 4000);
    Ok(DecodedSound { buffer: Arc::new(SampleBuffer { left, right, sample_rate }), peaks })
}

/// 長さ（秒）だけを知りたいとき（読み込み前の表示用）
pub fn probe_duration(path: &Path) -> Option<f64> {
    let (format, _) = open(path).ok()?;
    let track = format.tracks().iter().find(|t| t.codec_params.codec != CODEC_TYPE_NULL)?;
    let rate = track.codec_params.sample_rate? as f64;
    let frames = track.codec_params.n_frames? as f64;
    Some(frames / rate)
}

fn open(path: &Path) -> Result<(Box<dyn symphonia::core::formats::FormatReader>, ()), String> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| format!("読み込めない形式です: {e}"))?;
    Ok((probed.format, ()))
}

/// ファイルの元のサンプルレートのまま、左右に分けて読む（モノラルは左右に同じ音、3ch 以上は最初の2ch）
fn decode_raw(path: &Path) -> Result<(Vec<f32>, Vec<f32>, u32), String> {
    let (mut format, _) = open(path)?;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or("音のトラックがありません")?;
    let track_id = track.id;
    let src_rate = track.codec_params.sample_rate.unwrap_or(44_100);
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| format!("読み込めない形式です: {e}"))?;

    let mut left = Vec::new();
    let mut right = Vec::new();
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(SymError::ResetRequired) => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        match decoder.decode(&packet) {
            Ok(decoded) => {
                let spec = *decoded.spec();
                let ch = spec.channels.count().max(1);
                let mut sb = SymBuffer::<f32>::new(decoded.capacity() as u64, spec);
                sb.copy_interleaved_ref(decoded);
                for frame in sb.samples().chunks(ch) {
                    left.push(frame[0]);
                    right.push(if ch > 1 { frame[1] } else { frame[0] });
                }
            }
            // 壊れた一部分は飛ばして続ける
            Err(SymError::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok((left, right, src_rate))
}

/// サンプルレートを変える（高品質な FFT 方式）。変換の遅れぶんは頭を詰める
fn resample(left: &[f32], right: &[f32], from: usize, to: usize) -> Result<(Vec<f32>, Vec<f32>), String> {
    let chunk = 1024;
    let mut rs = FftFixedIn::<f32>::new(from, to, chunk, 2, 2).map_err(|e| e.to_string())?;
    let expected = (left.len() as f64 * to as f64 / from as f64).round() as usize;
    let mut out_l = Vec::with_capacity(expected + chunk * 2);
    let mut out_r = Vec::with_capacity(expected + chunk * 2);
    let mut pos = 0;
    while pos + rs.input_frames_next() <= left.len() {
        let n = rs.input_frames_next();
        let out = rs.process(&[&left[pos..pos + n], &right[pos..pos + n]], None).map_err(|e| e.to_string())?;
        out_l.extend_from_slice(&out[0]);
        out_r.extend_from_slice(&out[1]);
        pos += n;
    }
    if pos < left.len() {
        let out = rs
            .process_partial(Some(&[&left[pos..], &right[pos..]]), None)
            .map_err(|e| e.to_string())?;
        out_l.extend_from_slice(&out[0]);
        out_r.extend_from_slice(&out[1]);
    }
    // 中に残っている分を出し切る
    let out = rs.process_partial::<&[f32]>(None, None).map_err(|e| e.to_string())?;
    out_l.extend_from_slice(&out[0]);
    out_r.extend_from_slice(&out[1]);
    let delay = rs.output_delay();
    let take = |v: Vec<f32>| -> Vec<f32> { v.into_iter().skip(delay).take(expected).collect() };
    Ok((take(out_l), take(out_r)))
}

/// 波形表示用（区間ごとの最大振幅）
fn make_peaks(left: &[f32], right: &[f32], bins: usize) -> Vec<f32> {
    let frames = left.len();
    let bins = bins.min(frames.max(1));
    let per = (frames / bins).max(1);
    (0..bins)
        .map(|b| {
            let s = b * per;
            let e = if b == bins - 1 { frames } else { (s + per).min(frames) };
            (s..e).fold(0f32, |m, k| m.max(left[k].abs()).max(right[k].abs()))
        })
        .collect()
}
