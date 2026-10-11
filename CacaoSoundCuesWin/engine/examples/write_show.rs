//! Mac 版のサンプルを読み、書き出す（Mac 版が読めるかの確かめ用）
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let show: cacaosoundcues_engine::model::Show = serde_json::from_str(&std::fs::read_to_string(&args[1]).unwrap()).unwrap();
    std::fs::write(&args[2], serde_json::to_vec_pretty(&show).unwrap()).unwrap();
}
