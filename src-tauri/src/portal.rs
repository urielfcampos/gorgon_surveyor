use std::process::Command;

/// Capture a screen region using grim (Wayland screenshot tool).
/// geometry is "x,y widthxheight" format.
/// Returns the path to the captured PNG file.
pub fn capture_region(x: i32, y: i32, width: u32, height: u32) -> Result<String, String> {
    let tmp = std::env::temp_dir().join("gorgon-survey-capture.png");
    let geometry = format!("{},{} {}x{}", x, y, width, height);

    let output = Command::new("grim")
        .arg("-g")
        .arg(&geometry)
        .arg(tmp.to_str().unwrap())
        .output()
        .map_err(|e| format!("Failed to run grim: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("grim failed: {}", stderr));
    }

    Ok(tmp.to_string_lossy().to_string())
}

