pub mod commands;
pub mod config;
pub mod log_parser;
pub mod path_optimizer;
pub mod state;
pub mod triangulator;
pub mod zones;

use commands::{SharedConfig, SharedState};
use config::Config;
use state::AppState;
use std::sync::{Arc, Mutex};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app_state: SharedState = Arc::new(Mutex::new(AppState::default()));
    let app_config: SharedConfig = Arc::new(Mutex::new(Config::load()));

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(app_state.clone())
        .manage(app_config.clone())
        .setup(move |app| {
            // Make overlay window click-through
            if let Some(overlay) = app.get_webview_window("overlay") {
                overlay.set_ignore_cursor_events(true).ok();
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_state,
            commands::get_config,
            commands::save_config,
            commands::clear_surveys,
            commands::clear_motherlode,
            commands::skip_survey,
            commands::add_motherlode_reading,
            commands::get_zones,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
