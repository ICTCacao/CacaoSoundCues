// Windows のリリース版で、黒いコンソールの窓を出さない
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    cacaosoundcueswin_lib::run()
}
