//! フェードの形。Mac 版 FadeBezier.swift と同じ計算。

/// フェードのカーブ
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum FadeCurve {
    Linear,
    #[default]
    EqualPower,
    SCurve,
    Custom,
}

/// ベジエ曲線（CSS の cubic-bezier と同じく両端は固定、制御点2つ）。x は時間の進み、y は音量
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FadeBezier {
    pub x1: f64,
    pub y1: f64,
    pub x2: f64,
    pub y2: f64,
}

impl FadeBezier {
    pub const fn new(x1: f64, y1: f64, x2: f64, y2: f64) -> Self {
        Self { x1, y1, x2, y2 }
    }

    /// 決まった形（直線・等パワー・S字）に近いベジエ
    pub fn preset(curve: FadeCurve, rising: bool) -> Self {
        let third = 1.0 / 3.0;
        let pi6 = std::f64::consts::PI / 6.0;
        match (curve, rising) {
            (FadeCurve::Linear, true) => Self::new(third, third, 2.0 * third, 2.0 * third),
            (FadeCurve::Linear, false) => Self::new(third, 2.0 * third, 2.0 * third, third),
            (FadeCurve::SCurve, true) => Self::new(third, 0.0, 2.0 * third, 1.0),
            (FadeCurve::SCurve, false) => Self::new(third, 1.0, 2.0 * third, 0.0),
            (_, true) => Self::new(third, pi6, 2.0 * third, 1.0),
            (_, false) => Self::new(third, 1.0, 2.0 * third, 1.0 - pi6),
        }
    }

    pub fn simd(&self) -> [f32; 4] {
        [self.x1 as f32, self.y1 as f32, self.x2 as f32, self.y2 as f32]
    }

    /// 進み p（0〜1）のときの音量（0〜1）
    pub fn gain(&self, p: f64, rising: bool) -> f64 {
        bezier_gain(self.simd(), rising, p as f32) as f64
    }
}

/// ベジエの音量（音声スレッドから呼ぶのでメモリ確保なし）。x(t) = p を二分法で解いて y(t) を返す
#[inline(always)]
pub fn bezier_gain(b: [f32; 4], rising: bool, p: f32) -> f32 {
    let x = p.clamp(0.0, 1.0);
    let (y0, y3) = if rising { (0.0, 1.0) } else { (1.0, 0.0) };
    let (mut lo, mut hi, mut t) = (0.0f32, 1.0f32, x);
    for _ in 0..16 {
        let u = 1.0 - t;
        let xt = 3.0 * u * u * t * b[0] + 3.0 * u * t * t * b[2] + t * t * t;
        if xt < x { lo = t } else { hi = t }
        t = (lo + hi) / 2.0;
    }
    let u = 1.0 - t;
    let y = u * u * u * y0 + 3.0 * u * u * t * b[1] + 3.0 * u * t * t * b[3] + t * t * t * y3;
    y.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 決まった形のベジエが元の式に近いか（Mac 版と同じテスト）
    #[test]
    fn presets_match_formulas() {
        let pi = std::f64::consts::PI;
        let cases: Vec<(FadeCurve, bool, Box<dyn Fn(f64) -> f64>)> = vec![
            (FadeCurve::Linear, true, Box::new(|p| p)),
            (FadeCurve::Linear, false, Box::new(|p| 1.0 - p)),
            (FadeCurve::EqualPower, true, Box::new(move |p| (p * pi / 2.0).sin())),
            (FadeCurve::EqualPower, false, Box::new(move |p| (p * pi / 2.0).cos())),
            (FadeCurve::SCurve, true, Box::new(move |p| 0.5 - 0.5 * (p * pi).cos())),
            (FadeCurve::SCurve, false, Box::new(move |p| 0.5 + 0.5 * (p * pi).cos())),
        ];
        for (curve, rising, f) in cases {
            let b = FadeBezier::preset(curve, rising);
            for i in 0..=20 {
                let p = i as f64 / 20.0;
                assert!((b.gain(p, rising) - f(p)).abs() < 0.03, "{curve:?} {rising} p={p}");
            }
        }
    }
}
