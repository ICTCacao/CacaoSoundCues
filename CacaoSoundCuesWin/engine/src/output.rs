//! 音の出力（cpal。Windows は WASAPI、Mac は CoreAudio）。Mac 版 AudioOutput.swift と同じ役目。
//! 出力機器のサンプルレートでミキサーを作り、できるだけ小さいバッファで鳴らす。

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig, SupportedBufferSize};

use crate::mixer::{Mixer, MixerHandle};

/// 鳴らしている出力。stream を手放すと音が止まる
pub struct AudioOutput {
    _stream: cpal::Stream,
    pub sample_rate: f64,
    pub channels: u16,
    pub device_name: String,
    /// 実際に頼んだバッファの大きさ（フレーム）。機器が決める場合は None
    pub requested_buffer: Option<u32>,
    /// 1回に求められたフレーム数（最新）と、これまでに出したフレームの合計（動いているかの確かめ用）
    pub last_callback_frames: Arc<AtomicU32>,
    pub frames_rendered: Arc<AtomicU64>,
}

/// 既定の出力機器で鳴らし始める。preferred_frames は希望のバッファの大きさ（例 128 や 256）
pub fn start_output(preferred_frames: u32) -> Result<(AudioOutput, MixerHandle), String> {
    let host = cpal::default_host();
    let device = host.default_output_device().ok_or("音の出力機器が見つかりません")?;
    let device_name = device.name().unwrap_or_default();
    let supported = device.default_output_config().map_err(|e| e.to_string())?;
    let sample_rate = supported.sample_rate().0 as f64;
    let channels = supported.channels();
    let format = supported.sample_format();

    // バッファを小さくできるなら頼む（機器の範囲に収める）
    let requested = match supported.buffer_size() {
        SupportedBufferSize::Range { min, max } => Some(preferred_frames.clamp(*min, *max)),
        SupportedBufferSize::Unknown => None,
    };

    let last = Arc::new(AtomicU32::new(0));
    let total = Arc::new(AtomicU64::new(0));

    let build = |buffer: BufferSize| -> Result<(cpal::Stream, MixerHandle), String> {
        let config = StreamConfig { channels, sample_rate: supported.sample_rate(), buffer_size: buffer };
        let (mixer, handle) = Mixer::new(sample_rate);
        let stream = match format {
            SampleFormat::F32 => build_stream::<f32>(&device, &config, mixer, last.clone(), total.clone(), |x| x),
            SampleFormat::I16 => build_stream::<i16>(&device, &config, mixer, last.clone(), total.clone(), |x| {
                (x.clamp(-1.0, 1.0) * i16::MAX as f32) as i16
            }),
            SampleFormat::I32 => build_stream::<i32>(&device, &config, mixer, last.clone(), total.clone(), |x| {
                (x.clamp(-1.0, 1.0) as f64 * i32::MAX as f64) as i32
            }),
            other => return Err(format!("この出力の形式には対応していません: {other:?}")),
        }?;
        Ok((stream, handle))
    };

    // 希望の大きさで作れなければ、機器にまかせる
    let (stream, handle, used) = match requested.map(|f| build(BufferSize::Fixed(f))) {
        Some(Ok((s, h))) => (s, h, requested),
        _ => {
            let (s, h) = build(BufferSize::Default)?;
            (s, h, None)
        }
    };
    stream.play().map_err(|e| e.to_string())?;
    Ok((
        AudioOutput {
            _stream: stream,
            sample_rate,
            channels,
            device_name,
            requested_buffer: used,
            last_callback_frames: last,
            frames_rendered: total,
        },
        handle,
    ))
}

fn build_stream<T: cpal::SizedSample + Send + 'static>(
    device: &cpal::Device,
    config: &StreamConfig,
    mut mixer: Mixer,
    last: Arc<AtomicU32>,
    total: Arc<AtomicU64>,
    convert: fn(f32) -> T,
) -> Result<cpal::Stream, String> {
    let channels = config.channels as usize;
    // 音声スレッドでメモリを確保しないよう、作業用の場所を先に用意する
    const SCRATCH: usize = 8192;
    let mut l = vec![0f32; SCRATCH];
    let mut r = vec![0f32; SCRATCH];
    device
        .build_output_stream(
            config,
            move |data: &mut [T], _| {
                let frames = data.len() / channels.max(1);
                last.store(frames as u32, Ordering::Relaxed);
                let mut done = 0;
                while done < frames {
                    let n = (frames - done).min(SCRATCH);
                    mixer.render(&mut l[..n], &mut r[..n]);
                    for k in 0..n {
                        let base = (done + k) * channels;
                        for c in 0..channels {
                            data[base + c] = convert(match c {
                                0 => l[k],
                                1 => r[k],
                                _ => 0.0,
                            });
                        }
                    }
                    done += n;
                }
                total.fetch_add(frames as u64, Ordering::Relaxed);
            },
            |e| eprintln!("音の出力でエラー: {e}"),
            None,
        )
        .map_err(|e| e.to_string())
}
