use std::process::Command;

/// Capture a full-screen screenshot using spectacle (KDE).
/// Returns the path to the captured PNG file.
pub fn capture_screenshot() -> Result<String, String> {
    let tmp = std::env::temp_dir().join("gorgon-survey-capture.png");
    let tmp_str = tmp.to_string_lossy().to_string();

    let output = Command::new("spectacle")
        .args(["-f", "-b", "-n", "-o", &tmp_str])
        .output()
        .map_err(|e| format!("Failed to run spectacle: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("spectacle failed: {}", stderr));
    }

    Ok(tmp_str)
}
