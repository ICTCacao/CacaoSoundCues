//! Mac 版 CueMixerTests と同じ確かめ（サンプルレート 1000 で計算しやすくする。カットの 2ms = 2 フレーム）

use std::sync::Arc;

use cacaosoundcues_engine::*;

fn buf(values: Vec<f32>) -> Arc<SampleBuffer> {
    Arc::new(SampleBuffer { left: values.clone(), right: values, sample_rate: 1000.0 })
}
fn ones(n: usize) -> Arc<SampleBuffer> { buf(vec![1.0; n]) }
fn zeros(n: usize) -> Arc<SampleBuffer> { buf(vec![0.0; n]) }
fn ramp(n: usize) -> Arc<SampleBuffer> { buf((0..n).map(|i| i as f32).collect()) }

fn spec(token: u64, b: Arc<SampleBuffer>, start: i64, end: i64) -> VoiceSpec {
    let mut s = VoiceSpec::new(token, token as u128 + 1000, token as u128 + 1000, b, start, end);
    s.curve = FadeCurve::Linear;
    s
}

/// chunk フレームずつ total フレーム分レンダリングして左チャンネルを返す
fn render(m: &mut Mixer, total: usize, chunk: usize) -> Vec<f32> {
    let mut out = Vec::new();
    let mut done = 0;
    while done < total {
        let n = chunk.min(total - done);
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        m.render(&mut l, &mut r);
        out.extend_from_slice(&l);
        done += n;
    }
    out
}

fn close(a: f32, b: f32, eps: f32) -> bool { (a - b).abs() <= eps }

#[test]
fn fade_in_linear() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ones(1000), 0, 1000);
    s.fade_in_frames = 100;
    h.send(Command::Play(s));
    let out = render(&mut m, 200, 200);
    assert!(close(out[0], 0.0, 1e-6));
    assert!(close(out[50], 0.5, 1e-6));
    assert!(close(out[150], 1.0, 1e-6));
}

#[test]
fn in_out_points() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, ramp(100), 10, 20)));
    let out = render(&mut m, 30, 30);
    assert!(close(out[5], 15.0, 1e-6));
    assert!(close(out[9], 19.0, 1e-6));
    assert!(close(out[10], 0.0, 1e-6));
    assert!(h.snapshot().is_empty());
}

#[test]
fn looping() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ramp(100), 0, 10);
    s.looping = true;
    h.send(Command::Play(s));
    let out = render(&mut m, 25, 8);
    assert!(close(out[12], 2.0, 1e-6));
    assert!(close(out[24], 4.0, 1e-6));
    assert_eq!(h.snapshot().len(), 1);
}

#[test]
fn toggle_stops_with_fade_out() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ones(1000), 0, 1000);
    s.fade_out_frames = 10;
    h.send(Command::Toggle(s.clone()));
    render(&mut m, 20, 20);
    s.token = 2;
    h.send(Command::Toggle(s));
    let out = render(&mut m, 20, 20);
    assert!(close(out[0], 1.0, 1e-6));
    assert!(close(out[5], 0.5, 1e-6));
    assert!(close(out[15], 0.0, 1e-6));
    assert!(h.snapshot().is_empty(), "2回目の toggle は止めるだけ");
}

#[test]
fn fade_out_at_end() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ones(1000), 0, 100);
    s.fade_out_frames = 20;
    s.fade_out_at_end = true;
    h.send(Command::Play(s));
    let out = render(&mut m, 100, 100);
    assert!(close(out[79], 1.0, 1e-6));
    assert!(close(out[90], 0.5, 1e-6));
}

#[test]
fn follow_overlap_is_sample_accurate() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, zeros(100), 0, 20)));
    let mut next = spec(2, ones(100), 0, 100);
    next.follow = 1;
    next.gap_frames = -5;
    h.send(Command::Play(next));
    let out = render(&mut m, 40, 40);
    assert!(close(out[14], 0.0, 1e-6));
    assert!(close(out[15], 0.0, 1e-6));
    assert!(close(out[17], 1.0, 1e-6));
}

#[test]
fn follow_gap_across_buffers() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, zeros(100), 0, 20)));
    let mut next = spec(2, ones(100), 0, 100);
    next.follow = 1;
    next.gap_frames = 10;
    h.send(Command::Play(next));
    let out = render(&mut m, 48, 8);
    assert!(close(out[29], 0.0, 1e-6));
    assert!(close(out[30], 0.0, 1e-6));
    assert!(close(out[32], 1.0, 1e-6));
}

#[test]
fn stop_owner_cancels_armed() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut a = spec(1, ones(100), 0, 50);
    a.owner = 7;
    let mut b = spec(2, ones(100), 0, 50);
    b.owner = 7;
    b.follow = 1;
    h.send(Command::Play(a));
    h.send(Command::Play(b));
    render(&mut m, 10, 10);
    h.send(Command::StopOwner { owner: 7, fade_frames: 4 });
    render(&mut m, 100, 100);
    assert!(h.snapshot().is_empty());
}

#[test]
fn escape_twice_cuts() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, ones(1000), 0, 1000)));
    render(&mut m, 10, 10);
    h.send(Command::StopAll { fade_frames: 500 });
    render(&mut m, 10, 10);
    h.send(Command::StopAll { fade_frames: 0 });
    render(&mut m, 10, 10);
    assert!(h.snapshot().is_empty());
}

#[test]
fn seek() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, ramp(1000), 100, 900)));
    render(&mut m, 10, 10);
    h.send(Command::Seek { token: 1, frame: 500 });
    assert!(close(render(&mut m, 10, 10)[5], 505.0, 1e-3));
    h.send(Command::Seek { token: 1, frame: 0 });
    assert!(close(render(&mut m, 10, 10)[5], 105.0, 1e-3));
}

#[test]
fn loop_count_then_follower() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut a = spec(1, ramp(100), 0, 10);
    a.looping = true;
    a.loop_count = 3;
    let mut b = spec(2, ones(100), 0, 100);
    b.follow = 1;
    h.send(Command::Play(a));
    h.send(Command::Play(b));
    let out = render(&mut m, 40, 8);
    assert!(close(out[25], 5.0, 1e-6), "3回目");
    assert!(close(out[29], 9.0, 1e-6));
    assert!(close(out[35], 1.0, 1e-6), "3回鳴った後に次の曲");
}

#[test]
fn crossfade() {
    let (mut m, h) = Mixer::new(1000.0);
    h.send(Command::Play(spec(1, ones(100), 0, 40)));
    let mut next = spec(2, zeros(100), 0, 100);
    next.follow = 1;
    next.gap_frames = -20;
    next.crossfade = true;
    h.send(Command::Play(next));
    let out = render(&mut m, 50, 8);
    assert!(close(out[19], 1.0, 1e-6));
    assert!(close(out[30], 0.5, 1e-6));
    assert!(close(out[39], 0.05, 1e-6));
}

#[test]
fn delayed_start_and_start_now() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut first = spec(1, ones(100), 0, 20);
    first.delay_frames = 30;
    let mut next = spec(2, zeros(100), 0, 50);
    next.follow = 1;
    h.send(Command::Play(first));
    h.send(Command::Play(next));
    let out = render(&mut m, 64, 8);
    assert!(close(out[29], 0.0, 1e-6), "30 フレームは鳴らない");
    assert!(close(out[35], 1.0, 1e-6));
    assert!(close(out[52], 0.0, 1e-6), "次の曲は先の曲の後");

    let (mut m2, h2) = Mixer::new(1000.0);
    let mut late = spec(3, ones(100), 0, 100);
    late.delay_frames = 10_000;
    h2.send(Command::Play(late));
    render(&mut m2, 8, 8);
    h2.send(Command::StartNow(3));
    assert!(close(render(&mut m2, 8, 8)[5], 1.0, 1e-6));
}

#[test]
fn live_gain_change() {
    let (mut m, h) = Mixer::new(1000.0);
    let s = spec(1, ones(1000), 0, 1000);
    let owner = s.owner;
    h.send(Command::Play(s));
    assert!(close(render(&mut m, 16, 16)[10], 1.0, 1e-6));
    h.send(Command::SetGain { id: owner, gain: 0.5 });
    let ramp_out = render(&mut m, 16, 16);
    assert!(ramp_out[15] < 1.0);
    assert!(close(ramp_out[15], 0.5, 0.05));
    assert!(close(render(&mut m, 16, 16)[8], 0.5, 1e-6));
}

#[test]
fn volume_line() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ones(1000), 0, 1000);
    let linear = FadeBezier::preset(FadeCurve::Linear, true).simd();
    s.envelope = Envelope::from_points(&[(0.0, 0.0, linear), (0.1, -20.0, linear)], 1000.0);
    h.send(Command::Play(s));
    let out = render(&mut m, 200, 16);
    assert!(close(out[50], 10f32.powf(-10.0 / 20.0), 0.02));
    assert!(close(out[150], 0.1, 1e-4));
}

#[test]
fn pan_and_pan_line() {
    let (mut m, h) = Mixer::new(1000.0);
    let mut s = spec(1, ones(1000), 0, 1000);
    s.pan = 1.0;
    h.send(Command::Play(s));
    let mut l = vec![0.0; 16];
    let mut r = vec![0.0; 16];
    m.render(&mut l, &mut r);
    assert!(close(l[10], 0.0, 1e-4));
    assert!(close(r[10], 1.0, 1e-4));

    let (mut m2, h2) = Mixer::new(1000.0);
    let mut s2 = spec(2, ones(1000), 0, 1000);
    s2.pan_envelope = Envelope::from_points(&[(0.0, 1.0, [0.42, 0.0, 0.58, 1.0])], 1000.0);
    h2.send(Command::Play(s2));
    let mut l2 = vec![0.0; 64];
    let mut r2 = vec![0.0; 64];
    m2.render(&mut l2, &mut r2);
    assert!(close(l2[40], 0.0, 1e-3));
    assert!(close(r2[40], 1.0, 1e-3));
    assert!(close(h2.snapshot()[0].pan_now, 1.0, 1e-3));
}
