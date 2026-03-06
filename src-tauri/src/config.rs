use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct OverlayConfig {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub opacity: f32,
}

impl Default for OverlayConfig {
    fn default() -> Self {
        Self { x: 100, y: 100, width: 500, height: 500, opacity: 0.9 }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ColorsConfig {
    pub uncollected: String,
    pub collected: String,
    pub waypoint: String,
    pub motherlode: String,
}

impl Default for ColorsConfig {
    fn default() -> Self {
        Self {
            uncollected: "#FF4444".into(),
            collected: "#44FF44".into(),
            waypoint: "#FFFF00".into(),
            motherlode: "#FF00FF".into(),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Config {
    pub log_folder: String,
    pub current_zone: String,
    pub overlay: OverlayConfig,
    pub colors: ColorsConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_folder: String::new(),
            current_zone: "Serbule".into(),
            overlay: OverlayConfig::default(),
            colors: ColorsConfig::default(),
        }
    }
}

impl Config {
    pub fn config_path() -> PathBuf {
        let dir = dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("gorgon-survey");
        fs::create_dir_all(&dir).ok();
        dir.join("settings.toml")
    }

    pub fn load() -> Self {
        Self::load_from(&Self::config_path()).unwrap_or_default()
    }

    pub fn load_from(path: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let content = fs::read_to_string(path)?;
        Ok(toml::from_str(&content)?)
    }

    pub fn save(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.save_to(&Self::config_path())
    }

    pub fn save_to(&self, path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let content = toml::to_string_pretty(self)?;
        fs::write(path, content)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_default_config_zone() {
        let config = Config::default();
        assert_eq!(config.current_zone, "Serbule");
    }

    #[test]
    fn test_default_config_log_folder_empty() {
        let config = Config::default();
        assert!(config.log_folder.is_empty());
    }

    #[test]
    fn test_round_trip_save_load() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("settings.toml");

        let mut config = Config::default();
        config.current_zone = "Kur Mountains".to_string();
        config.log_folder = "/some/path/ProjectGorgon".to_string();
        config.save_to(&path).unwrap();

        let loaded = Config::load_from(&path).unwrap();
        assert_eq!(loaded.current_zone, "Kur Mountains");
        assert_eq!(loaded.log_folder, "/some/path/ProjectGorgon");
    }
}
