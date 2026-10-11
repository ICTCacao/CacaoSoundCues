//! 音量ライン・PANライン（音声スレッド用）。Mac 版 VolumeEnvelope.swift と同じ計算。
//! メモリ確保をしないよう、点は決まった数（64）までを値の中に持つ。

use crate::bezier::bezier_gain;

pub const CAPACITY: usize = 64;

#[derive(Clone, Copy, Debug)]
pub struct EnvPoint {
    /// 音ファイルの頭からのフレーム
    pub frame: i64,
    /// その時点の値（音量ラインなら dB、PANラインなら -1〜1）
    pub value: f32,
    /// 次の点までの形（ベジエの制御点 x1,y1,x2,y2）
    pub shape: [f32; 4],
}

impl Default for EnvPoint {
    fn default() -> Self {
        Self { frame: 0, value: 0.0, shape: [0.42, 0.0, 0.58, 1.0] }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Envelope {
    count: usize,
    points: [EnvPoint; CAPACITY],
}

impl Default for Envelope {
    fn default() -> Self {
        Self { count: 0, points: [EnvPoint::default(); CAPACITY] }
    }
}

impl Envelope {
    /// (秒, 値, 形) の並びから作る（時間の順に並べ、64 個まで）
    pub fn from_points(points: &[(f64, f64, [f32; 4])], sample_rate: f64) -> Self {
        let mut sorted: Vec<_> = points.to_vec();
        sorted.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        let mut e = Self::default();
        for (t, v, shape) in sorted.into_iter().take(CAPACITY) {
            e.points[e.count] = EnvPoint { frame: (t * sample_rate) as i64, value: v as f32, shape };
            e.count += 1;
        }
        e
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    pub fn len(&self) -> usize {
        self.count
    }

    /// あるフレームでの線の値。点が無ければ 0
    #[inline(always)]
    pub fn value(&self, frame: i64) -> f32 {
        if self.count == 0 {
            return 0.0;
        }
        let first = self.points[0];
        if frame <= first.frame {
            return first.value;
        }
        for k in 0..self.count - 1 {
            let a = self.points[k];
            let b = self.points[k + 1];
            if frame < b.frame {
                let p = (frame - a.frame) as f32 / ((b.frame - a.frame).max(1)) as f32;
                let s = bezier_gain(a.shape, true, p);
                return a.value + (b.value - a.value) * s;
            }
        }
        self.points[self.count - 1].value
    }

    /// あるフレームでの音量（倍率）。値を dB として扱う。点が無ければ 1
    #[inline(always)]
    pub fn gain(&self, frame: i64) -> f32 {
        if self.count == 0 {
            return 1.0;
        }
        10f32.powf(self.value(frame) / 20.0)
    }
}
