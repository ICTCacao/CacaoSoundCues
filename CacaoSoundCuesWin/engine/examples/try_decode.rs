//! 音ファイルを読めるか確かめる（cargo run --release --example try_decode -- ファイル）
fn main() {
    for p in std::env::args().skip(1) {
        match cacaosoundcues_engine::decode_file(std::path::Path::new(&p), 48000.0) {
            Ok(d) => println!("OK {:.2}s {}", d.duration(), p),
            Err(e) => println!("NG {e} {p}"),
        }
    }
}
