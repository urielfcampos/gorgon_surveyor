use tauri::Manager;
use tauri::WebviewUrl;
use tauri::webview::WebviewWindowBuilder;

use crate::OVERLAY_CLICK_THROUGH;

#[tauri::command]
pub fn capture_and_detect(
    app: tauri::AppHandle,
    session_id: String,
    zone_x1: Option<f64>,
    zone_y1: Option<f64>,
    zone_x2: Option<f64>,
    zone_y2: Option<f64>,
) -> Result<serde_json::Value, String> {
    let overlay = app
        .get_webview_window("overlay")
        .ok_or_else(|| "Overlay window not found".to_string())?;

    let pos = overlay.inner_position().map_err(|e| e.to_string())?;
    let size = overlay.inner_size().map_err(|e| e.to_string())?;

    // Hide overlay so it doesn't appear in the screenshot
    let _ = overlay.hide();
    std::thread::sleep(std::time::Duration::from_millis(100));

    let capture_result = crate::portal::capture_screenshot();

    // Show overlay again immediately
    let _ = overlay.show();

    let screenshot_path = capture_result?;

    println!(
        "[tauri] captured: overlay inner pos {},{} size {}x{}",
        pos.x, pos.y, size.width, size.height
    );

    let client = reqwest::blocking::Client::new();
    let mut form = reqwest::blocking::multipart::Form::new()
        .text("path", screenshot_path);

    if let (Some(x1), Some(y1), Some(x2), Some(y2)) = (zone_x1, zone_y1, zone_x2, zone_y2) {
        form = form
            .text("zone_x1", x1.to_string())
            .text("zone_y1", y1.to_string())
            .text("zone_x2", x2.to_string())
            .text("zone_y2", y2.to_string());
    }

    // Pass overlay geometry so server can crop correctly
    form = form
        .text("overlay_x", pos.x.to_string())
        .text("overlay_y", pos.y.to_string())
        .text("overlay_w", size.width.to_string())
        .text("overlay_h", size.height.to_string());

    let response = client
        .post(format!("http://localhost:4840/api/capture/{}", session_id))
        .multipart(form)
        .send()
        .map_err(|e| format!("Failed to send capture: {}", e))?;

    let body: serde_json::Value = response
        .json()
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    Ok(body)
}

#[tauri::command]
pub fn create_overlay_window(app: tauri::AppHandle, session_id: String) -> Result<(), String> {
    if let Some(overlay) = app.get_webview_window("overlay") {
        overlay.show().map_err(|e| e.to_string())?;
        return Ok(());
    }

    let url_str = format!("http://localhost:4840/overlay?session_id={}", session_id);
    let url = WebviewUrl::External(url_str.parse().unwrap());

    let overlay = WebviewWindowBuilder::new(&app, "overlay", url)
        .title("Overlay — F12 to interact")
        .inner_size(800.0, 600.0)
        .transparent(true)
        .decorations(true)
        .always_on_top(true)
        .build()
        .map_err(|e| format!("Failed to create overlay window: {}", e))?;

    // Start in click-through mode
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
