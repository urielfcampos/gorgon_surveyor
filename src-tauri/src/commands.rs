use tauri::Emitter;
use tauri::Manager;
use tauri::WebviewUrl;
use tauri::webview::WebviewWindowBuilder;

use crate::OVERLAY_CLICK_THROUGH;

fn get_cursor_position() -> Result<(i32, i32), String> {
    let output = std::process::Command::new("xdotool")
        .args(["getmouselocation", "--shell"])
        .output()
        .map_err(|e| format!("Failed to run xdotool: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut x: Option<i32> = None;
    let mut y: Option<i32> = None;

    for line in stdout.lines() {
        if let Some(val) = line.strip_prefix("X=") {
            x = val.parse().ok();
        } else if let Some(val) = line.strip_prefix("Y=") {
            y = val.parse().ok();
        }
    }

    match (x, y) {
        (Some(x), Some(y)) => Ok((x, y)),
        _ => Err("Failed to parse cursor position from xdotool".to_string()),
    }
}

pub fn emit_collect_at_cursor(app: &tauri::AppHandle) -> Result<(), String> {
    let overlay = app
        .get_webview_window("overlay")
        .ok_or_else(|| "Overlay window not found".to_string())?;

    let (cursor_x, cursor_y) = get_cursor_position()?;

    let pos = overlay.inner_position().map_err(|e| e.to_string())?;
    let size = overlay.inner_size().map_err(|e| e.to_string())?;

    let rel_x = cursor_x - pos.x;
    let rel_y = cursor_y - pos.y;

    // Silently ignore if cursor is outside overlay bounds
    if rel_x < 0 || rel_y < 0 || rel_x >= size.width as i32 || rel_y >= size.height as i32 {
        return Ok(());
    }

    let x_pct = rel_x as f64 / size.width as f64 * 100.0;
    let y_pct = rel_y as f64 / size.height as f64 * 100.0;

    overlay
        .emit("collect_at_cursor", serde_json::json!({"x_pct": x_pct, "y_pct": y_pct}))
        .map_err(|e| format!("Failed to emit collect_at_cursor: {}", e))?;

    println!(
        "[tauri] collect_at_cursor: cursor=({},{}) overlay_pos=({},{}) pct=({:.1},{:.1})",
        cursor_x, cursor_y, pos.x, pos.y, x_pct, y_pct
    );

    Ok(())
}

#[tauri::command]
pub fn capture_and_detect(
    app: tauri::AppHandle,
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

    // Find which monitor the overlay is on and get monitor-relative position
    let monitors = overlay.available_monitors().map_err(|e| e.to_string())?;
    let (mon_x, mon_y) = monitors
        .iter()
        .find(|m| {
            let mp = m.position();
            let ms = m.size();
            pos.x >= mp.x
                && pos.x < mp.x + ms.width as i32
                && pos.y >= mp.y
                && pos.y < mp.y + ms.height as i32
        })
        .map(|m| (m.position().x, m.position().y))
        .unwrap_or((0, 0));

    let rel_x = pos.x - mon_x;
    let rel_y = pos.y - mon_y;

    // Capture the current monitor — overlay is transparent so game shows through
    let screenshot_path = crate::portal::capture_screenshot()?;

    println!(
        "[tauri] captured: overlay at {},{} (monitor-relative, monitor {},{}), size {}x{}",
        rel_x, rel_y, mon_x, mon_y, size.width, size.height
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

    // Pass overlay geometry relative to monitor
    form = form
        .text("overlay_x", rel_x.to_string())
        .text("overlay_y", rel_y.to_string())
        .text("overlay_w", size.width.to_string())
        .text("overlay_h", size.height.to_string());

    let response = client
        .post("http://localhost:4840/api/capture")
        .multipart(form)
        .send()
        .map_err(|e| format!("Failed to send capture: {}", e))?;

    let body: serde_json::Value = response
        .json()
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    Ok(body)
}

#[tauri::command]
pub fn create_overlay_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(overlay) = app.get_webview_window("overlay") {
        overlay.show().map_err(|e| e.to_string())?;
        return Ok(());
    }

    let url = WebviewUrl::External("http://localhost:4840/overlay".parse().unwrap());

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
pub fn refresh_overlay(app: tauri::AppHandle) -> Result<(), String> {
    let _overlay = app
        .get_webview_window("overlay")
        .ok_or_else(|| "Overlay window not found".to_string())?;

    println!("[tauri] refresh_overlay called");

    // Force WebKitGTK to recomposite by hiding and re-showing
    // the overlay window with a delay long enough for the
    // compositor to process the unmap/map cycle.
    // Save position and size before hiding
    let pos = _overlay.outer_position().map_err(|e| e.to_string())?;
    let size = _overlay.outer_size().map_err(|e| e.to_string())?;
    println!("[tauri] refresh_overlay saving pos=({},{}) size={}x{}", pos.x, pos.y, size.width, size.height);

    let handle = app.clone();
    std::thread::spawn(move || {
        if let Some(win) = handle.get_webview_window("overlay") {
            // Wait for the overlay LiveView to receive the zone clear
            // via PubSub and redraw the canvas before we hide/show
            std::thread::sleep(std::time::Duration::from_millis(300));
            let _ = win.hide();
            std::thread::sleep(std::time::Duration::from_millis(100));
            let _ = win.set_position(tauri::Position::Physical(pos));
            let _ = win.set_size(tauri::Size::Physical(size));
            let _ = win.show();
            std::thread::sleep(std::time::Duration::from_millis(50));
            let _ = win.set_position(tauri::Position::Physical(pos));
            let _ = win.set_size(tauri::Size::Physical(size));
            let _ = win.set_always_on_top(true);
            let ct = crate::OVERLAY_CLICK_THROUGH.load(std::sync::atomic::Ordering::SeqCst);
            let _ = win.set_ignore_cursor_events(ct);
            println!("[tauri] refresh_overlay complete");
        }
    });

    Ok(())
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

#[tauri::command]
pub fn update_hotkeys(
    app: tauri::AppHandle,
    interact_key: String,
    collect_key: String,
) -> Result<(), String> {
    crate::hotkey::register_hotkeys(&app, &interact_key, &collect_key)
}

#[tauri::command]
pub fn set_collect_hotkey(app: tauri::AppHandle, key: String) -> Result<(), String> {
    crate::hotkey::register_collect_hotkey_standalone(&app, &key)
}
