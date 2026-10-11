//! 出力が動くかを、音を出さずに確かめる（全体の音量 0 で 1 秒間）
use std::sync::atomic::Ordering;

fn main() {
    let (out, handle) = cacaosoundcues_engine::start_output(128).expect("出力を開始できません");
    handle.send(cacaosoundcues_engine::Command::SetMasterGain(0.0));
    std::thread::sleep(std::time::Duration::from_millis(1000));
    let frames = out.frames_rendered.load(Ordering::Relaxed);
    let last = out.last_callback_frames.load(Ordering::Relaxed);
    println!("出力機器: {}", out.device_name);
    println!("サンプルレート: {} Hz / {} ch", out.sample_rate, out.channels);
    println!("頼んだバッファ: {:?} フレーム / 実際に1回で求められた: {} フレーム（{:.1} ms）",
             out.requested_buffer, last, last as f64 / out.sample_rate * 1000.0);
    println!("1 秒間に出したフレーム: {frames}");
}
