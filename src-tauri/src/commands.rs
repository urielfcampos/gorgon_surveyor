use crate::config::Config;
use crate::state::AppState;
use std::sync::{Arc, Mutex};
use tauri::State;

pub type SharedState = Arc<Mutex<AppState>>;
pub type SharedConfig = Arc<Mutex<Config>>;

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
pub fn clear_surveys(state: State<SharedState>) {
    state.lock().unwrap().clear_surveys();
}

#[tauri::command]
pub fn clear_motherlode(state: State<SharedState>) {
    state.lock().unwrap().clear_motherlode();
}

#[tauri::command]
pub fn skip_survey(id: u32, state: State<SharedState>) {
    state.lock().unwrap().mark_collected(id);
}

#[tauri::command]
pub fn add_motherlode_reading(x: f64, y: f64, distance: f64, state: State<SharedState>) {
    state.lock().unwrap().add_motherlode_reading((x, y), distance);
}

#[tauri::command]
pub fn get_zones() -> Vec<String> {
    crate::zones::ZONES.iter().map(|(name, _)| name.to_string()).collect()
}
