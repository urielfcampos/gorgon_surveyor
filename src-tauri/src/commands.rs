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

    // Calculate screen region to capture
    let (cap_x, cap_y, cap_w, cap_h) =
        if let (Some(x1), Some(y1), Some(x2), Some(y2)) = (zone_x1, zone_y1, zone_x2, zone_y2) {
            // Capture just the detect zone region (zone coords are overlay percentages)
            let ox = pos.x as f64;
            let oy = pos.y as f64;
            let ow = size.width as f64;
            let oh = size.height as f64;

            let zx = ox + x1 / 100.0 * ow;
            let zy = oy + y1 / 100.0 * oh;
            let zw = (x2 - x1) / 100.0 * ow;
            let zh = (y2 - y1) / 100.0 * oh;

            (zx as i32, zy as i32, zw.max(1.0) as u32, zh.max(1.0) as u32)
        } else {
            // Capture the full overlay region
            (pos.x, pos.y, size.width, size.height)
        };

    println!(
        "[tauri] grim capture: region {},{} {}x{}",
        cap_x, cap_y, cap_w, cap_h
    );

    let screenshot_path = crate::portal::capture_region(cap_x, cap_y, cap_w, cap_h)?;

    // Send to Phoenix — the image is already cropped to the zone,
    // so pass zone coords for coordinate mapping back to overlay space
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
    // If overlay already exists, just show it
    if let Some(overlay) = app.get_webview_window("overlay") {
        overlay.show().map_err(|e| e.to_string())?;
        return Ok(());
    }

    let url_str = format!("http://localhost:4840/overlay?session_id={}", session_id);
    let url = WebviewUrl::External(url_str.parse().unwrap());

    let _overlay = WebviewWindowBuilder::new(&app, "overlay", url)
        .title("Overlay — F12 to interact")
        .inner_size(800.0, 600.0)
        .transparent(true)
        .decorations(true)
        .always_on_top(true)
        .build()
        .map_err(|e| format!("Failed to create overlay window: {}", e))?;

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
