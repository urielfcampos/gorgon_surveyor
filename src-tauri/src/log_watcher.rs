use crate::log_parser::{parse_line, LogEvent};
use crate::state::AppState;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::fs::File;
use std::io::{BufRead, BufReader, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter};

pub fn start_watching(
    log_path: PathBuf,
    state: Arc<Mutex<AppState>>,
    app: AppHandle,
) -> Result<RecommendedWatcher, Box<dyn std::error::Error + Send + Sync>> {
    let file = File::open(&log_path)?;
    let mut reader = BufReader::new(file);
    // Seek to end so we only see new lines going forward
    reader.seek(SeekFrom::End(0))?;
    let reader = Arc::new(Mutex::new(reader));

    let reader_clone = reader.clone();
    let log_path_clone = log_path.clone();

    let mut watcher = notify::recommended_watcher(move |res: notify::Result<Event>| {
        if let Ok(event) = res {
            if matches!(event.kind, EventKind::Modify(_)) {
                let mut r = reader_clone.lock().unwrap();
                let mut line = String::new();
                while r.read_line(&mut line).unwrap_or(0) > 0 {
                    if let Some(evt) = parse_line(line.trim()) {
                        handle_log_event(evt, &state, &app);
                    }
                    line.clear();
                }
            }
        }
    })?;

    watcher.watch(&log_path_clone, RecursiveMode::NonRecursive)?;
    Ok(watcher)
}

fn handle_log_event(event: LogEvent, state: &Arc<Mutex<AppState>>, app: &AppHandle) {
    let mut s = state.lock().unwrap();
    match event {
        LogEvent::SurveyOffset { dx, dy } => {
            let (px, py) = s.player_position.unwrap_or((0.0, 0.0));
            s.add_survey("".into(), px + dx, py + dy);
        }
        LogEvent::MotherlodeDistance { meters } => {
            if let Some(pos) = s.player_position {
                s.add_motherlode_reading(pos, meters);
            }
        }
        LogEvent::SurveyCollected => {
            // Mark the first active survey (lowest route order) as collected
            if let Some(id) = s
                .surveys
                .iter()
                .filter(|s| !s.collected)
                .min_by_key(|s| s.route_order.unwrap_or(usize::MAX))
                .map(|s| s.id)
            {
                s.mark_collected(id);
            }
        }
    }
    let _ = app.emit("state-updated", s.clone());
}
