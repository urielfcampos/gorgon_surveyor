use crate::config::Config;
use crate::state::AppState;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;
use tauri::{Emitter, Manager, State};

/// Returns the most recently modified `.log` file inside `folder`, or `None`.
pub fn find_latest_log(folder: &Path) -> Option<std::path::PathBuf> {
    std::fs::read_dir(folder).ok()?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "log"))
        .max_by_key(|e| {
            e.metadata()
                .and_then(|m| m.modified())
                .unwrap_or(SystemTime::UNIX_EPOCH)
        })
        .map(|e| e.path())
}

pub type SharedState = Arc<Mutex<AppState>>;
pub type SharedConfig = Arc<Mutex<Config>>;
pub type WatcherRunning = Arc<AtomicBool>;

#[tauri::command]
pub fn get_state(state: State<SharedState>) -> AppState {
    state.lock().unwrap().clone()
}

#[tauri::command]
pub fn get_config(config: State<SharedConfig>) -> Config {
    config.lock().unwrap().clone()
}

#[tauri::command]
pub fn save_config(new_config: Config, config: State<SharedConfig>) -> Result<(), String> {
    let mut c = config.lock().unwrap();
    new_config.save().map_err(|e| e.to_string())?;
    *c = new_config;
    Ok(())
}

#[tauri::command]
pub fn clear_surveys(state: State<SharedState>, app: tauri::AppHandle) {
    let mut s = state.lock().unwrap();
    s.clear_surveys();
    let _ = app.emit("state-updated", s.clone());
}

#[tauri::command]
pub fn clear_motherlode(state: State<SharedState>, app: tauri::AppHandle) {
    let mut s = state.lock().unwrap();
    s.clear_motherlode();
    let _ = app.emit("state-updated", s.clone());
}

#[tauri::command]
pub fn skip_survey(id: u32, state: State<SharedState>, app: tauri::AppHandle) {
    let mut s = state.lock().unwrap();
    s.mark_collected(id);
    let _ = app.emit("state-updated", s.clone());
}

#[tauri::command]
pub fn add_motherlode_reading(x: f64, y: f64, distance: f64, state: State<SharedState>, app: tauri::AppHandle) {
    let mut s = state.lock().unwrap();
    s.add_motherlode_reading((x, y), distance);
    let _ = app.emit("state-updated", s.clone());
}

#[tauri::command]
pub fn get_zones() -> Vec<String> {
    crate::zones::ZONES.iter().map(|(name, _)| name.to_string()).collect()
}

#[tauri::command]
pub fn set_player_position(x: f64, y: f64, state: State<SharedState>, app: tauri::AppHandle) {
    let mut s = state.lock().unwrap();
    s.player_position = Some((x, y));
    let _ = app.emit("state-updated", s.clone());
}

#[tauri::command]
pub fn set_overlay_passthrough(enabled: bool, app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("overlay") {
        window.set_ignore_cursor_events(enabled).map_err(|e| e.to_string())?;
        let _ = app.emit("overlay-passthrough-changed", enabled);
        Ok(())
    } else {
        Err("Overlay window not found".to_string())
    }
}

#[tauri::command]
pub fn toggle_overlay_visible(app: tauri::AppHandle) -> Result<bool, String> {
    if let Some(window) = app.get_webview_window("overlay") {
        let visible = window.is_visible().map_err(|e| e.to_string())?;
        if visible {
            window.hide().map_err(|e| e.to_string())?;
        } else {
            window.show().map_err(|e| e.to_string())?;
        }
        Ok(!visible)
    } else {
        Err("Overlay window not found".to_string())
    }
}

#[tauri::command]
pub async fn start_log_watching(
    log_folder: String,
    state: State<'_, SharedState>,
    config: State<'_, SharedConfig>,
    watching: State<'_, WatcherRunning>,
    app: tauri::AppHandle,
) -> Result<(), String> {
    let folder = std::path::PathBuf::from(&log_folder);
    if !folder.is_dir() {
        return Err(format!("Folder not found: {}", log_folder));
    }

    let log_path = find_latest_log(&folder)
        .ok_or_else(|| format!("No .log files found in: {}", log_folder))?;

    if watching.load(Ordering::SeqCst) {
        return Err("Already watching a log file. Restart the app to change the folder.".to_string());
    }
    watching.store(true, Ordering::SeqCst);

    {
        let mut c = config.lock().unwrap();
        c.log_folder = log_folder;
        c.save().map_err(|e| e.to_string())?;
    }

    let state_arc = state.inner().clone();
    std::thread::spawn(move || {
        match crate::log_watcher::start_watching(log_path, state_arc, app) {
            Ok(_watcher) => loop {
                std::thread::sleep(std::time::Duration::from_secs(60));
            },
            Err(e) => eprintln!("Log watcher error: {e}"),
        }
    });

    Ok(())
}
