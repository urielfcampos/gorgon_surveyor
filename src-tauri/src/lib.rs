use std::sync::atomic::AtomicBool;

use tauri::Manager;

mod commands;
mod hotkey;
mod portal;

/// Tracks whether the overlay window is in click-through mode.
/// `true` means click-through (ignoring cursor events), `false` means interactive.
pub static OVERLAY_CLICK_THROUGH: AtomicBool = AtomicBool::new(true);

const SERVER_PORT: u16 = 4840;
const HEALTH_CHECK_URL: &str = "http://localhost:4840";
const HEALTH_CHECK_INTERVAL_MS: u64 = 500;
const HEALTH_CHECK_TIMEOUT_MS: u64 = 15000;

fn wait_for_server() -> bool {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_millis(500))
        .build()
        .unwrap();

    let start = std::time::Instant::now();
    let timeout = std::time::Duration::from_millis(HEALTH_CHECK_TIMEOUT_MS);

    while start.elapsed() < timeout {
        if let Ok(resp) = client.get(HEALTH_CHECK_URL).send() {
            if resp.status().is_success() || resp.status().is_redirection() {
                return true;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(HEALTH_CHECK_INTERVAL_MS));
    }

    false
}

fn resolve_sidecar_path() -> std::path::PathBuf {
    let exe_dir = std::env::current_exe()
        .expect("Failed to get current exe path")
        .parent()
        .expect("Failed to get exe directory")
        .to_path_buf();

    let sidecar = exe_dir.join("phoenix-server");
    if sidecar.exists() {
        return sidecar;
    }

    let project_sidecar = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("binaries")
        .join(format!(
            "phoenix-server-{}",
            std::env::consts::ARCH
        ));
    if project_sidecar.exists() {
        return project_sidecar;
    }

    panic!(
        "Sidecar not found at {:?} or {:?}",
        sidecar, project_sidecar
    );
}

/// Holds the sidecar path so we can call `<release> stop` on shutdown.
/// This gracefully stops the BEAM VM and all its children.
struct SidecarGuard {
    sidecar_path: std::path::PathBuf,
}

impl Drop for SidecarGuard {
    fn drop(&mut self) {
        println!("[tauri] Stopping Phoenix server...");
        // The release `stop` command gracefully shuts down the BEAM
        let _ = std::process::Command::new(&self.sidecar_path)
            .env("RELEASE_COMMAND", "stop")
            .status();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            commands::capture_screenshot,
            commands::capture_and_detect,
            commands::create_overlay_window,
            commands::toggle_overlay_interaction,
            commands::set_overlay_geometry,
        ])
        .setup(|app| {
            let sidecar_path = resolve_sidecar_path();
            println!("[tauri] Spawning sidecar: {:?}", sidecar_path);

            let _child = std::process::Command::new(&sidecar_path)
                .stdout(std::process::Stdio::inherit())
                .stderr(std::process::Stdio::inherit())
                .spawn()
                .unwrap_or_else(|e| {
                    panic!("Failed to spawn Phoenix sidecar at {:?}: {}", sidecar_path, e)
                });

            println!("[tauri] Sidecar PID: {}", _child.id());

            app.manage(SidecarGuard {
                sidecar_path: sidecar_path.clone(),
            });

            let window = app.get_webview_window("main").unwrap();
            let app_handle = app.handle().clone();

            std::thread::spawn(move || {
                if wait_for_server() {
                    println!("[tauri] Phoenix server is ready!");
                    let url = format!("http://localhost:{}", SERVER_PORT);
                    let _ = window.navigate(url.parse().unwrap());

                    // Register global hotkey
                    if let Err(e) = hotkey::register_default_hotkey(&app_handle) {
                        eprintln!("[tauri] Failed to register hotkey: {}", e);
                    }
                } else {
                    eprintln!("[tauri] Phoenix server failed to start within timeout");
                    let _ = window.navigate(
                        "data:text/html,<h1>Failed to start server</h1><p>The Phoenix server did not respond within 15 seconds.</p>"
                            .parse()
                            .unwrap(),
                    );
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Error while running Gorgon Survey");
}
