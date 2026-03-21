use std::sync::Mutex;

use tauri::AppHandle;
use tauri::{Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

use crate::OVERLAY_CLICK_THROUGH;

static COLLECT_HOTKEY_STR: Mutex<Option<String>> = Mutex::new(None);

pub const DEFAULT_INTERACT_KEY: &str = "F12";
pub const DEFAULT_COLLECT_KEY: &str = "F11";

fn register_interact_hotkey(app: &AppHandle, key: &str) -> Result<(), String> {
    let shortcut: Shortcut = key
        .parse()
        .map_err(|e| format!("Invalid shortcut '{}': {:?}", key, e))?;

    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _shortcut, event| {
            if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                if let Some(overlay) = app.get_webview_window("overlay") {
                    let was_click_through =
                        OVERLAY_CLICK_THROUGH.load(std::sync::atomic::Ordering::SeqCst);
                    let new_click_through = !was_click_through;

                    let result = overlay.set_ignore_cursor_events(new_click_through);
                    println!(
                        "[tauri] interact hotkey: click_through={} -> {}, result={:?}",
                        was_click_through, new_click_through, result
                    );

                    OVERLAY_CLICK_THROUGH
                        .store(new_click_through, std::sync::atomic::Ordering::SeqCst);

                    let interactive = !new_click_through;
                    let _ = overlay.emit("interaction_toggled", interactive);
                }
            }
        })
        .map_err(|e| format!("Failed to register interact hotkey '{}': {}", key, e))?;

    Ok(())
}

fn register_collect_hotkey(app: &AppHandle, key: &str) -> Result<(), String> {
    let shortcut: Shortcut = key
        .parse()
        .map_err(|e| format!("Invalid shortcut '{}': {:?}", key, e))?;

    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _shortcut, event| {
            if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                if let Some(overlay) = app.get_webview_window("overlay") {
                    let result =
                        overlay.eval("if(window._collectNearest) window._collectNearest()");
                    println!("[tauri] collect hotkey: eval={:?}", result);
                }
            }
        })
        .map_err(|e| format!("Failed to register collect hotkey '{}': {}", key, e))?;

    Ok(())
}

pub fn register_default_hotkey(app: &AppHandle) -> Result<(), String> {
    register_interact_hotkey(app, DEFAULT_INTERACT_KEY)?;
    register_collect_hotkey(app, DEFAULT_COLLECT_KEY)?;
    Ok(())
}

pub fn register_hotkeys(app: &AppHandle, interact_key: &str, collect_key: &str) -> Result<(), String> {
    // Unregister all existing shortcuts before re-registering
    app.global_shortcut()
        .unregister_all()
        .map_err(|e| format!("Failed to unregister shortcuts: {}", e))?;

    register_interact_hotkey(app, interact_key)?;
    register_collect_hotkey(app, collect_key)?;

    println!(
        "[tauri] hotkeys registered: interact='{}', collect='{}'",
        interact_key, collect_key
    );

    Ok(())
}

/// Register (or re-register) a standalone collect hotkey with cursor-based collection.
/// Tracks the current hotkey string so it can unregister the previous one.
pub fn register_collect_hotkey_standalone(app: &AppHandle, key: &str) -> Result<(), String> {
    let mut stored = COLLECT_HOTKEY_STR
        .lock()
        .map_err(|e| format!("Mutex poisoned: {}", e))?;

    // Unregister previous hotkey if one was set
    if let Some(ref prev_key) = *stored {
        if let Ok(prev_shortcut) = prev_key.parse::<Shortcut>() {
            let _ = app.global_shortcut().unregister(prev_shortcut);
        }
    }

    *stored = None;

    // If key is empty, just clear
    if key.is_empty() {
        println!("[tauri] collect hotkey cleared");
        return Ok(());
    }

    let shortcut: Shortcut = key
        .parse()
        .map_err(|e| format!("Invalid shortcut '{}': {:?}", key, e))?;

    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _shortcut, event| {
            if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                if let Err(e) = crate::commands::emit_collect_at_cursor(app) {
                    eprintln!("[tauri] collect hotkey error: {}", e);
                }
            }
        })
        .map_err(|e| format!("Failed to register collect hotkey '{}': {}", key, e))?;

    *stored = Some(key.to_string());
    println!("[tauri] collect hotkey registered: '{}'", key);

    Ok(())
}
