use ashpd::desktop::screenshot::Screenshot;

pub async fn capture_screenshot() -> Result<String, String> {
    let response = Screenshot::request()
        .interactive(false)
        .modal(false)
        .send()
        .await
        .map_err(|e| format!("Portal screenshot request failed: {}", e))?
        .response()
        .map_err(|e| format!("Portal screenshot response failed: {}", e))?;

    let uri = response.uri().to_string();
    let path = uri.strip_prefix("file://").unwrap_or(&uri).to_string();
    Ok(path)
}
