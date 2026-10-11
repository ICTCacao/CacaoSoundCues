//! 音ファイルの読み込み（Mac の上でだけ: afconvert と ffmpeg で、いろいろな形式の音を作って読む）
#![cfg(target_os = "macos")]

use std::path::{Path, PathBuf};
use std::process::Command;

use cacaosoundcues_engine::{decode_file, probe_duration};

fn tmpdir() -> PathBuf {
    let d = std::env::temp_dir().join(format!("ccsc-decode-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn make(src: &Path, out: &Path, args: &[&str]) -> bool {
    Command::new("/usr/bin/afconvert").args(args).arg(src).arg(out).status().map(|s| s.success()).unwrap_or(false)
}

fn check(path: &Path, rate: f64) {
    let original = probe_duration(path).unwrap_or(0.0);
    let s = decode_file(path, rate).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    assert_eq!(s.buffer.sample_rate, rate);
    assert!(s.peaks.iter().cloned().fold(0f32, f32::max) > 0.05, "{} が無音", path.display());
    if original > 0.0 {
        assert!((s.duration() - original).abs() < 0.08, "{}: 長さ {} と {}", path.display(), s.duration(), original);
    }
}

#[test]
fn decodes_common_formats() {
    let glass = Path::new("/System/Library/Sounds/Glass.aiff");
    let d = tmpdir();
    check(glass, 48_000.0);
    let jobs: [(&str, &[&str]); 3] = [
        ("a.m4a", &["-f", "m4af", "-d", "aac"]),
        ("b.wav", &["-f", "WAVE", "-d", "LEI16@44100", "-c", "1"]),
        ("c.caf.wav", &["-f", "WAVE", "-d", "LEF32@96000"]),
    ];
    for (name, args) in jobs {
        let out = d.join(name);
        assert!(make(glass, &out, args), "afconvert {name}");
        check(&out, 48_000.0);
    }
    // mp3（ffmpeg があれば）
    let mp3 = d.join("d.mp3");
    if Command::new("ffmpeg").args(["-v", "error", "-y", "-i"]).arg(glass).arg(&mp3).status().map(|s| s.success()).unwrap_or(false) {
        check(&mp3, 44_100.0);
    }
    let _ = std::fs::remove_dir_all(&d);
}
