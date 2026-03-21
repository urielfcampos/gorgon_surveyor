use tauri::AppHandle;
use tauri::{Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

use crate::OVERLAY_CLICK_THROUGH;

pub fn register_default_hotkey(app: &AppHandle) -> Result<(), String> {
    let shortcut: Shortcut = "F12"
        .parse()
        .map_err(|e| format!("Invalid shortcut: {:?}", e))?;

    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _shortcut, event| {
            if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                if let Some(overlay) = app.get_webview_window("overlay") {
                    let was_click_through =
                        OVERLAY_CLICK_THROUGH.load(std::sync::atomic::Ordering::SeqCst);
                    let new_click_through = !was_click_through;

                    let result = overlay.set_ignore_cursor_events(new_click_through);
                    println!(
                        "[tauri] F12 pressed: click_through={} -> {}, result={:?}",
                        was_click_through, new_click_through, result
                    );

                    OVERLAY_CLICK_THROUGH
                        .store(new_click_through, std::sync::atomic::Ordering::SeqCst);

                    let interactive = !new_click_through;
                    let _ = overlay.emit("interaction_toggled", interactive);
                } else {
                    println!("[tauri] F12 pressed but no overlay window found");
                }
            }
        })
        .map_err(|e| format!("Failed to register hotkey: {}", e))?;

    Ok(())
}
