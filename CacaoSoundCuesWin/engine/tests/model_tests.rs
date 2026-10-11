//! キューシートの読み書き。Mac 版が保存した show.json をそのまま読めるか、書き戻しても同じか

use cacaosoundcues_engine::model::{self, *};

fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"))).unwrap()
}

#[test]
fn reads_show_saved_by_mac_app() {
    let show: Show = serde_json::from_str(&fixture("mac-saved-show.json")).expect("Mac 版の show.json を読めない");
    assert_eq!(show.name, "Mac で保存");
    assert_eq!(show.master_volume_db, -3.0);
    let cue = &show.key_cues[0];
    assert_eq!(cue.key_code, 18);
    assert_eq!(cue.retrigger, RetriggerMode::Restart);
    assert_eq!(cue.group_id, Some(show.key_groups[0].id));
    let p = &cue.play;
    assert_eq!(p.out_point, Some(3.0));
    assert_eq!(p.curve, FadeCurve::Custom);
    assert_eq!(p.fade_in_bezier.unwrap().x1, 0.1);
    assert_eq!(p.loop_count, 3);
    assert_eq!(p.volume_points.len(), 2);
    assert!(p.volume_points[0].shape.is_none());
    assert_eq!(p.volume_points[1].shape.unwrap().x2, 0.8);
    assert_eq!(p.pan, -0.3);
    assert_eq!(p.pan_points[0].db, 0.5);
    let seq = &show.sequences[0];
    assert_eq!(seq.toggle_key, Some(46));
    assert!(seq.looping);
    assert_eq!(seq.steps[0].start, StepStart::Overlap);
    assert_eq!(seq.steps[0].start_seconds, 3.0);
    assert_eq!(seq.steps[1].start, StepStart::ReturnKey);
}

#[test]
fn reads_sample_and_old_formats() {
    let show: Show = serde_json::from_str(&fixture("sample-show.json")).unwrap();
    assert_eq!(show.key_cues.len(), 7);
    assert_eq!(show.sequences[0].steps.len(), 4);
    // 項目が足りない古いキューシートと、以前の "manual"
    let old = r#"{"name":"古い","sequences":[{"id":"8B1E4F3C-0F7A-4E5B-9C2D-1A2B3C4D5E6F","name":"L",
        "steps":[{"id":"8B1E4F3C-0F7A-4E5B-9C2D-1A2B3C4D5E60","name":"s","start":"manual",
        "play":{"soundID":"8B1E4F3C-0F7A-4E5B-9C2D-1A2B3C4D5E61"}}]}]}"#;
    let s: Show = serde_json::from_str(old).unwrap();
    assert_eq!(s.panic_fade, 2.0);
    assert_eq!(s.sequences[0].stop_fade, 3.0);
    assert_eq!(s.sequences[0].steps[0].start, StepStart::ReturnKey);
}

#[test]
fn round_trip_keeps_everything() {
    let show: Show = serde_json::from_str(&fixture("mac-saved-show.json")).unwrap();
    let json = serde_json::to_string(&show).unwrap();
    assert!(json.contains(&show.key_cues[0].id.to_string()), "ID は大文字のまま");
    assert!(!json.contains("\"outPoint\":null"), "空の項目は書かない");
    let back: Show = serde_json::from_str(&json).unwrap();
    assert_eq!(back, show);
}

#[test]
fn save_copies_audio_into_package() {
    let dir = std::env::temp_dir().join(format!("ccsc-save-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let original = dir.join("ベル.wav");
    std::fs::write(&original, b"RIFF....").unwrap();
    let mut show = Show::new("テスト");
    let snd = SoundRef { id: Id::new(), file_name: "ベル.wav".into(), display_name: "ベル".into(), duration: 1.0 };
    show.sounds.push(snd.clone());
    let pkg = dir.join("テスト.ccsc");
    let saved = model::save(&show, &pkg, |_| Some(original.clone())).unwrap();
    std::fs::remove_file(&original).unwrap();
    let loaded = model::load(&pkg).unwrap();
    assert_eq!(loaded.sounds[0].file_name, saved.sounds[0].file_name);
    assert!(model::audio_path(&loaded.sounds[0], &pkg).exists(), "元を消してもパッケージの中にある");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn line_value_matches_envelope() {
    let pts = vec![
        VolumePoint { id: Id::new(), time: 1.0, db: -6.0, shape: None },
        VolumePoint { id: Id::new(), time: 3.0, db: -18.0, shape: None },
    ];
    let env = model::envelope(&pts, 1000.0);
    for t in [0.0, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0] {
        let want = 10f64.powf(model::line_value(&pts, t) / 20.0);
        assert!((env.gain((t * 1000.0) as i64) as f64 - want).abs() < 0.01, "t={t}");
    }
}
