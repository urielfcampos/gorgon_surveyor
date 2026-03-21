use tauri::Manager;

use crate::OVERLAY_CLICK_THROUGH;

#[tauri::command]
pub async fn capture_screenshot() -> Result<String, String> {
    crate::portal::capture_screenshot().await
}

#[tauri::command]
pub fn toggle_overlay_interaction(app: tauri::AppHandle) -> Result<bool, String> {
    let overlay = app
        .get_webview_window("overlay")
        .ok_or_else(|| "Overlay window not found".to_string())?;

    let was_click_through = OVERLAY_CLICK_THROUGH.load(std::sync::atomic::Ordering::SeqCst);
    let new_click_through = !was_click_through;

    overlay
        .set_ignore_cursor_events(new_click_through)
        .map_err(|e| format!("Failed to toggle cursor events: {}", e))?;

    OVERLAY_CLICK_THROUGH.store(new_click_through, std::sync::atomic::Ordering::SeqCst);

    // Return whether the overlay is now interactive (i.e., NOT ignoring cursor events)
    Ok(!new_click_through)
}

#[tauri::command]
pub fn set_overlay_geometry(
    app: tauri::AppHandle,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> Result<(), String> {
    let overlay = app
        .get_webview_window("overlay")
        .ok_or_else(|| "Overlay window not found".to_string())?;

    overlay
        .set_position(tauri::Position::Physical(tauri::PhysicalPosition {
            x: x as i32,
            y: y as i32,
        }))
        .map_err(|e| format!("Failed to set overlay position: {}", e))?;

    overlay
        .set_size(tauri::Size::Physical(tauri::PhysicalSize {
            width: width as u32,
            height: height as u32,
        }))
        .map_err(|e| format!("Failed to set overlay size: {}", e))?;

    Ok(())
}
