use std::process::Command;

/// Capture a screenshot using the xdg-desktop-portal via D-Bus.
/// On KDE, this is fast after the first permission grant.
/// Returns the path to the captured PNG file.
pub fn capture_screenshot() -> Result<String, String> {
    let tmp = std::env::temp_dir().join("gorgon-survey-capture.png");
    let tmp_str = tmp.to_string_lossy().to_string();

    // Try grim first (wlroots compositors: Sway, Hyprland)
    let grim_result = Command::new("grim")
        .arg(&tmp_str)
        .output();

    if let Ok(output) = grim_result {
        if output.status.success() {
            return Ok(tmp_str);
        }
    }

    // Fallback: use spectacle (KDE) for full screen capture
    let spectacle_result = Command::new("spectacle")
        .args(["-f", "-b", "-n", "-o", &tmp_str])
        .output();

    if let Ok(output) = spectacle_result {
        if output.status.success() {
            return Ok(tmp_str);
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("spectacle failed: {}", stderr));
    }

    Err("No screenshot tool available (tried grim, spectacle)".to_string())
}

/// Capture a specific screen region.
/// Tries grim -g first, falls back to full screen + server-side crop.
pub fn capture_region(x: i32, y: i32, width: u32, height: u32) -> Result<String, String> {
    let tmp = std::env::temp_dir().join("gorgon-survey-capture.png");
    let tmp_str = tmp.to_string_lossy().to_string();
    let geometry = format!("{},{} {}x{}", x, y, width, height);

    // Try grim with region (wlroots compositors)
    let grim_result = Command::new("grim")
        .args(["-g", &geometry, &tmp_str])
        .output();

    if let Ok(output) = grim_result {
        if output.status.success() {
            return Ok(tmp_str);
        }
    }

    // Fallback: spectacle full screen (we'll crop server-side)
    let spectacle_result = Command::new("spectacle")
        .args(["-f", "-b", "-n", "-o", &tmp_str])
        .output();

    if let Ok(output) = spectacle_result {
        if output.status.success() {
            // Return special marker so caller knows it needs cropping
            return Ok(format!("FULLSCREEN:{}", tmp_str));
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("spectacle failed: {}", stderr));
    }

    Err("No screenshot tool available (tried grim, spectacle)".to_string())
}
