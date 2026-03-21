use tauri::Manager;
use tauri::WebviewUrl;
use tauri::webview::WebviewWindowBuilder;

use crate::OVERLAY_CLICK_THROUGH;

#[tauri::command]
pub async fn capture_screenshot() -> Result<String, String> {
    crate::portal::capture_screenshot().await
}

#[tauri::command]
pub async fn capture_and_detect(session_id: String) -> Result<serde_json::Value, String> {
    let screenshot_path = crate::portal::capture_screenshot().await?;

    let client = reqwest::Client::new();
    let form = reqwest::multipart::Form::new()
        .text("path", screenshot_path);

    let response = client
        .post(format!("http://localhost:4840/api/capture/{}", session_id))
        .multipart(form)
        .send()
        .await
        .map_err(|e| format!("Failed to send capture: {}", e))?;

    let body: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    Ok(body)
}

#[tauri::command]
pub fn create_overlay_window(app: tauri::AppHandle) -> Result<(), String> {
    // If overlay already exists, just show it
    if let Some(overlay) = app.get_webview_window("overlay") {
        overlay.show().map_err(|e| e.to_string())?;
        return Ok(());
    }

    let url = WebviewUrl::External("http://localhost:4840/overlay".parse().unwrap());

    let overlay = WebviewWindowBuilder::new(&app, "overlay", url)
        .title("Gorgon Survey Overlay")
        .inner_size(800.0, 600.0)
        .transparent(true)
        .decorations(false)
        .always_on_top(true)
        .build()
        .map_err(|e| format!("Failed to create overlay window: {}", e))?;

    overlay
        .set_ignore_cursor_events(true)
        .map_err(|e| format!("Failed to set click-through: {}", e))?;

    OVERLAY_CLICK_THROUGH.store(true, std::sync::atomic::Ordering::SeqCst);

    Ok(())
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
