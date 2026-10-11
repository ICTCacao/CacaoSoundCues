//! CacaoSoundCues の音声エンジン（Windows 版用）。
//! Mac 版（Swift の CueMixer）と同じ計算で、フェード・再生範囲・リピート・音量ライン・PANライン・
//! リストのつなぎ（後に続く・重ねる・n 秒待つ）を、サンプル単位で処理する。

pub mod bezier;
pub mod decode;
pub mod envelope;
pub mod mixer;
pub mod model;
pub mod output;

pub use bezier::{bezier_gain, FadeBezier, FadeCurve};
pub use envelope::{EnvPoint, Envelope};
pub use decode::{decode_file, probe_duration, DecodedSound};
pub use mixer::{Command, Mixer, MixerHandle, SampleBuffer, VoiceSpec, VoiceStatus};
pub use output::{start_output, AudioOutput};
