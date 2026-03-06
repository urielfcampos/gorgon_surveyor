pub mod commands;
pub mod config;
pub mod log_parser;
pub mod log_watcher;
pub mod path_optimizer;
pub mod state;
pub mod triangulator;
pub mod zones;

use commands::{SharedConfig, SharedState, WatcherRunning};
use config::Config;
use state::AppState;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app_state: SharedState = Arc::new(Mutex::new(AppState::default()));
    let app_config: SharedConfig = Arc::new(Mutex::new(Config::load()));
    let watching: WatcherRunning = Arc::new(AtomicBool::new(false));

    let setup_state = app_state.clone();
    let setup_config = app_config.clone();
    let setup_watching = watching.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(app_state.clone())
        .manage(app_config.clone())
        .manage(watching.clone())
        .setup(move |app| {
            // Make overlay window click-through
            if let Some(overlay) = app.get_webview_window("overlay") {
                overlay.set_ignore_cursor_events(true).ok();
            }
            // Auto-start watcher if log path was previously configured
            let cfg = setup_config.lock().unwrap().clone();
            if !cfg.log_path.is_empty() {
                let path = std::path::PathBuf::from(&cfg.log_path);
                if path.exists() {
                    setup_watching.store(true, Ordering::SeqCst);
                    let state_clone = setup_state.clone();
                    let handle = app.handle().clone();
                    std::thread::spawn(move || {
                        match crate::log_watcher::start_watching(path, state_clone, handle) {
                            Ok(_w) => loop {
                                std::thread::sleep(std::time::Duration::from_secs(60));
                            },
                            Err(e) => eprintln!("Auto-start watcher error: {e}"),
                        }
                    });
                }
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
            commands::start_log_watching,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
