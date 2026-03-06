# Gorgon Survey Tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a cross-platform Tauri desktop app that reads Project Gorgon chat logs, displays a transparent overlay with survey locations, and provides an optimized collection route with motherlode triangulation.

**Architecture:** Rust backend with log watching/parsing/computation modules; React/TypeScript frontend with two Tauri windows — a transparent click-through overlay and a control panel. App state lives in a shared `Arc<Mutex<AppState>>` managed by Tauri; the log watcher runs in a background thread and emits `state-updated` events to the frontend.

**Tech Stack:** Rust, Tauri 2.x, React 18, TypeScript, `notify` crate (file watching), `serde`/`toml` (config), `regex` crate (log parsing)

---

## Prerequisites Check

Before starting, verify:
```bash
rustc --version     # >= 1.75
cargo --version
node --version      # >= 18
npm --version
```

Install Tauri CLI if needed:
```bash
cargo install tauri-cli --version "^2"
```

---

### Task 1: Scaffold Tauri + React project with two windows

**Files:**
- Create: entire project structure via `npm create tauri-app`
- Modify: `src-tauri/tauri.conf.json` (two-window config)

**Step 1: Create the project**

```bash
cd /home/urielfcampos/projects/gorgon-survey
npm create tauri-app@latest . -- --template react-ts --manager npm
```

Accept prompts. This creates `src/` (React), `src-tauri/` (Rust), `package.json`, `vite.config.ts`.

**Step 2: Replace `src-tauri/tauri.conf.json` windows array**

Open `src-tauri/tauri.conf.json` and replace the `windows` array with:

```json
"windows": [
  {
    "label": "control-panel",
    "title": "Gorgon Survey Tool",
    "width": 420,
    "height": 720,
    "resizable": true,
    "visible": true,
    "url": "index.html"
  },
  {
    "label": "overlay",
    "title": "",
    "width": 500,
    "height": 500,
    "x": 100,
    "y": 100,
    "decorations": false,
    "transparent": true,
    "alwaysOnTop": true,
    "skipTaskbar": true,
    "url": "index.html#/overlay"
  }
]
```

**Step 3: Verify it builds and both windows appear**

```bash
npm run tauri dev
```

Expected: Two windows open — one normal control panel and one frameless/transparent overlay.

**Step 4: Commit**

```bash
git init
git add .
git commit -m "feat: scaffold Tauri + React project with two windows"
```

---

### Task 2: Config module (Rust)

**Files:**
- Create: `src-tauri/src/config.rs`
- Modify: `src-tauri/Cargo.toml` (add deps)
- Modify: `src-tauri/src/main.rs` (add `mod config;`)

**Step 1: Add dependencies to `src-tauri/Cargo.toml`**

In `[dependencies]`:
```toml
serde = { version = "1", features = ["derive"] }
toml = "0.8"
dirs = "5"
```

In `[dev-dependencies]`:
```toml
tempfile = "3"
```

**Step 2: Write the failing tests at the bottom of `src-tauri/src/config.rs`**

Create the file with just the test module first:

```rust
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
    fn test_default_config_log_path_empty() {
        let config = Config::default();
        assert!(config.log_path.is_empty());
    }

    #[test]
    fn test_round_trip_save_load() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("settings.toml");

        let mut config = Config::default();
        config.current_zone = "Kur Mountains".to_string();
        config.log_path = "/some/path/chat.log".to_string();
        config.save_to(&path).unwrap();

        let loaded = Config::load_from(&path).unwrap();
        assert_eq!(loaded.current_zone, "Kur Mountains");
        assert_eq!(loaded.log_path, "/some/path/chat.log");
    }
}
```

**Step 3: Run the tests to verify they fail**

```bash
cd src-tauri && cargo test config -- --nocapture
```

Expected: FAIL — `Config` not defined.

**Step 4: Implement `src-tauri/src/config.rs`**

Replace the file with the full implementation:

```rust
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
    pub log_path: String,
    pub current_zone: String,
    pub overlay: OverlayConfig,
    pub colors: ColorsConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_path: String::new(),
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
    fn test_default_config_log_path_empty() {
        let config = Config::default();
        assert!(config.log_path.is_empty());
    }

    #[test]
    fn test_round_trip_save_load() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("settings.toml");

        let mut config = Config::default();
        config.current_zone = "Kur Mountains".to_string();
        config.log_path = "/some/path/chat.log".to_string();
        config.save_to(&path).unwrap();

        let loaded = Config::load_from(&path).unwrap();
        assert_eq!(loaded.current_zone, "Kur Mountains");
        assert_eq!(loaded.log_path, "/some/path/chat.log");
    }
}
```

**Step 5: Run tests to verify they pass**

```bash
cd src-tauri && cargo test config
```

Expected: 3 tests PASS.

**Step 6: Add `mod config;` to `src-tauri/src/main.rs`**

Add at the top of `main.rs`:
```rust
mod config;
```

**Step 7: Commit**

```bash
git add src-tauri/src/config.rs src-tauri/src/main.rs src-tauri/Cargo.toml
git commit -m "feat: add config module with TOML save/load"
```

---

### Task 3: Log parser (Rust)

**Files:**
- Create: `src-tauri/src/log_parser.rs`
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/main.rs`

> **Important:** The regex patterns below are based on PgSurveyor's description of the game output. The exact message format MUST be validated against a real game log in Task 13. If patterns don't match, update the regex in `parse_line()`.

**Step 1: Add `regex` to `src-tauri/Cargo.toml`**

```toml
regex = "1"
```

**Step 2: Write the failing tests**

Create `src-tauri/src/log_parser.rs` with just tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_survey_placement() {
        // Placeholder format — update after validating real game log
        let line = "Survey marked at Serbule (123, 456)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Serbule".into(), x: 123.0, y: 456.0 })
        );
    }

    #[test]
    fn test_parse_motherlode_distance() {
        let line = "The motherlode is 347 meters away.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::MotherlodeDistance { meters: 347.0 }));
    }

    #[test]
    fn test_parse_survey_collected() {
        let line = "You collected the survey reward.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::SurveyCollected));
    }

    #[test]
    fn test_unrelated_line_returns_none() {
        assert_eq!(parse_line("You say: Hello world!"), None);
        assert_eq!(parse_line(""), None);
    }

    #[test]
    fn test_negative_coordinates() {
        let line = "Survey marked at Eltibule (-500, -123)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Eltibule".into(), x: -500.0, y: -123.0 })
        );
    }
}
```

**Step 3: Run tests to verify they fail**

```bash
cd src-tauri && cargo test log_parser
```

Expected: FAIL — `parse_line` and `LogEvent` not defined.

**Step 4: Implement `src-tauri/src/log_parser.rs`**

```rust
use regex::Regex;
use std::sync::OnceLock;

#[derive(Debug, PartialEq, Clone)]
pub enum LogEvent {
    SurveyPlaced { zone: String, x: f64, y: f64 },
    MotherlodeDistance { meters: f64 },
    SurveyCollected,
}

fn survey_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        // Format: "Survey marked at <Zone> (<x>, <y>)"
        // TODO: Validate against real game logs and update if needed
        Regex::new(r"Survey marked at (.+?) \((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)").unwrap()
    })
}

fn motherlode_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"The motherlode is (\d+(?:\.\d+)?) meters away").unwrap()
    })
}

fn collected_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"You collected the survey reward").unwrap()
    })
}

pub fn parse_line(line: &str) -> Option<LogEvent> {
    if let Some(caps) = survey_re().captures(line) {
        return Some(LogEvent::SurveyPlaced {
            zone: caps[1].to_string(),
            x: caps[2].parse().ok()?,
            y: caps[3].parse().ok()?,
        });
    }
    if let Some(caps) = motherlode_re().captures(line) {
        return Some(LogEvent::MotherlodeDistance {
            meters: caps[1].parse().ok()?,
        });
    }
    if collected_re().is_match(line) {
        return Some(LogEvent::SurveyCollected);
    }
    None
}

#[cfg(test)]
mod tests {
    // (tests from Step 2 go here)
    use super::*;

    #[test]
    fn test_parse_survey_placement() {
        let line = "Survey marked at Serbule (123, 456)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Serbule".into(), x: 123.0, y: 456.0 })
        );
    }

    #[test]
    fn test_parse_motherlode_distance() {
        let line = "The motherlode is 347 meters away.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::MotherlodeDistance { meters: 347.0 }));
    }

    #[test]
    fn test_parse_survey_collected() {
        let line = "You collected the survey reward.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::SurveyCollected));
    }

    #[test]
    fn test_unrelated_line_returns_none() {
        assert_eq!(parse_line("You say: Hello world!"), None);
        assert_eq!(parse_line(""), None);
    }

    #[test]
    fn test_negative_coordinates() {
        let line = "Survey marked at Eltibule (-500, -123)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Eltibule".into(), x: -500.0, y: -123.0 })
        );
    }
}
```

**Step 5: Run tests to verify they pass**

```bash
cd src-tauri && cargo test log_parser
```

Expected: 5 tests PASS.

**Step 6: Add `mod log_parser;` to `main.rs`**

**Step 7: Commit**

```bash
git add src-tauri/src/log_parser.rs src-tauri/Cargo.toml src-tauri/src/main.rs
git commit -m "feat: add log parser with survey and motherlode regex patterns"
```

---

### Task 4: Path optimizer (Rust)

**Files:**
- Create: `src-tauri/src/path_optimizer.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Write the failing tests**

Create `src-tauri/src/path_optimizer.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_input() {
        assert_eq!(optimize_path((0.0, 0.0), &[]), vec![]);
    }

    #[test]
    fn test_single_point() {
        assert_eq!(optimize_path((0.0, 0.0), &[(5.0, 5.0)]), vec![0]);
    }

    #[test]
    fn test_nearest_neighbor_ordering() {
        // Start at origin.
        // Points: A(1,0), B(10,0), C(2,0)
        // nearest to origin → A(idx 0), nearest to A → C(idx 2), nearest to C → B(idx 1)
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((0.0, 0.0), &points);
        assert_eq!(result, vec![0, 2, 1]);
    }

    #[test]
    fn test_start_position_affects_order() {
        // Start far right — B(10,0) should be first
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((12.0, 0.0), &points);
        assert_eq!(result[0], 1); // B is closest to start (12,0)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd src-tauri && cargo test path_optimizer
```

Expected: FAIL — `optimize_path` not defined.

**Step 3: Implement `src-tauri/src/path_optimizer.rs`**

```rust
/// Returns the indices of `points` in the order a nearest-neighbor TSP heuristic visits them,
/// starting from `start`.
pub fn optimize_path(start: (f64, f64), points: &[(f64, f64)]) -> Vec<usize> {
    if points.is_empty() {
        return vec![];
    }

    let mut unvisited: Vec<usize> = (0..points.len()).collect();
    let mut order = Vec::with_capacity(points.len());
    let mut current = start;

    while !unvisited.is_empty() {
        let nearest_pos = unvisited
            .iter()
            .enumerate()
            .min_by(|(_, &a), (_, &b)| {
                euclidean(current, points[a])
                    .partial_cmp(&euclidean(current, points[b]))
                    .unwrap()
            })
            .map(|(i, _)| i)
            .unwrap();

        let point_idx = unvisited.remove(nearest_pos);
        current = points[point_idx];
        order.push(point_idx);
    }

    order
}

fn euclidean(a: (f64, f64), b: (f64, f64)) -> f64 {
    let dx = a.0 - b.0;
    let dy = a.1 - b.1;
    (dx * dx + dy * dy).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_input() {
        assert_eq!(optimize_path((0.0, 0.0), &[]), vec![]);
    }

    #[test]
    fn test_single_point() {
        assert_eq!(optimize_path((0.0, 0.0), &[(5.0, 5.0)]), vec![0]);
    }

    #[test]
    fn test_nearest_neighbor_ordering() {
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((0.0, 0.0), &points);
        assert_eq!(result, vec![0, 2, 1]);
    }

    #[test]
    fn test_start_position_affects_order() {
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((12.0, 0.0), &points);
        assert_eq!(result[0], 1);
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
cd src-tauri && cargo test path_optimizer
```

Expected: 4 tests PASS.

**Step 5: Add `mod path_optimizer;` to `main.rs`**

**Step 6: Commit**

```bash
git add src-tauri/src/path_optimizer.rs src-tauri/src/main.rs
git commit -m "feat: add nearest-neighbor path optimizer"
```

---

### Task 5: Motherlode triangulator (Rust)

**Files:**
- Create: `src-tauri/src/triangulator.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Write the failing tests**

Create `src-tauri/src/triangulator.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
        ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
    }

    #[test]
    fn test_needs_three_readings() {
        assert!(triangulate(&[((0.0, 0.0), 100.0), ((50.0, 0.0), 60.0)]).is_none());
    }

    #[test]
    fn test_triangulates_known_point() {
        // Target at (100.0, 100.0)
        let target = (100.0f64, 100.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((200.0, 0.0), dist(target, (200.0, 0.0))),
            ((100.0, 200.0), dist(target, (100.0, 200.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01, "x off: {}", result.0);
        assert!((result.1 - target.1).abs() < 0.01, "y off: {}", result.1);
    }

    #[test]
    fn test_triangulates_negative_coords() {
        let target = (-300.0f64, -150.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((-600.0, 0.0), dist(target, (-600.0, 0.0))),
            ((-300.0, -400.0), dist(target, (-300.0, -400.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01);
        assert!((result.1 - target.1).abs() < 0.01);
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd src-tauri && cargo test triangulator
```

Expected: FAIL.

**Step 3: Implement `src-tauri/src/triangulator.rs`**

```rust
/// Given 3+ (position, distance) readings, return the estimated target point.
/// Uses circle-circle intersection. Returns None if geometry fails or < 3 readings.
pub fn triangulate(readings: &[((f64, f64), f64)]) -> Option<(f64, f64)> {
    if readings.len() < 3 {
        return None;
    }
    let candidates = circle_intersections(readings[0], readings[1])?;
    let ((x3, y3), r3) = readings[2];
    candidates
        .into_iter()
        .min_by(|&(ax, ay), &(bx, by)| {
            let da = (euclidean((ax, ay), (x3, y3)) - r3).abs();
            let db = (euclidean((bx, by), (x3, y3)) - r3).abs();
            da.partial_cmp(&db).unwrap()
        })
}

fn circle_intersections(
    ((x1, y1), r1): ((f64, f64), f64),
    ((x2, y2), r2): ((f64, f64), f64),
) -> Option<Vec<(f64, f64)>> {
    let d = euclidean((x1, y1), (x2, y2));
    if d > r1 + r2 || d < (r1 - r2).abs() || d < 1e-9 {
        return None;
    }
    let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d);
    let h_sq = r1 * r1 - a * a;
    if h_sq < 0.0 {
        return None;
    }
    let h = h_sq.sqrt();
    let mx = x1 + a * (x2 - x1) / d;
    let my = y1 + a * (y2 - y1) / d;

    if h < 1e-9 {
        return Some(vec![(mx, my)]);
    }

    Some(vec![
        (mx + h * (y2 - y1) / d, my - h * (x2 - x1) / d),
        (mx - h * (y2 - y1) / d, my + h * (x2 - x1) / d),
    ])
}

fn euclidean(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
        ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
    }

    #[test]
    fn test_needs_three_readings() {
        assert!(triangulate(&[((0.0, 0.0), 100.0), ((50.0, 0.0), 60.0)]).is_none());
    }

    #[test]
    fn test_triangulates_known_point() {
        let target = (100.0f64, 100.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((200.0, 0.0), dist(target, (200.0, 0.0))),
            ((100.0, 200.0), dist(target, (100.0, 200.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01, "x off: {}", result.0);
        assert!((result.1 - target.1).abs() < 0.01, "y off: {}", result.1);
    }

    #[test]
    fn test_triangulates_negative_coords() {
        let target = (-300.0f64, -150.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((-600.0, 0.0), dist(target, (-600.0, 0.0))),
            ((-300.0, -400.0), dist(target, (-300.0, -400.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01);
        assert!((result.1 - target.1).abs() < 0.01);
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
cd src-tauri && cargo test triangulator
```

Expected: 3 tests PASS.

**Step 5: Add `mod triangulator;` to `main.rs`**

**Step 6: Commit**

```bash
git add src-tauri/src/triangulator.rs src-tauri/src/main.rs
git commit -m "feat: add motherlode triangulator with circle intersection math"
```

---

### Task 6: App state + Tauri IPC commands

**Files:**
- Create: `src-tauri/src/state.rs`
- Create: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Write failing tests**

Create `src-tauri/src/state.rs` with just tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_survey_appends() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        assert_eq!(s.surveys.len(), 1);
        assert_eq!(s.surveys[0].x, 100.0);
        assert_eq!(s.surveys[0].y, 200.0);
        assert!(!s.surveys[0].collected);
    }

    #[test]
    fn test_mark_collected() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        let id = s.surveys[0].id;
        s.mark_collected(id);
        assert!(s.surveys[0].collected);
    }

    #[test]
    fn test_route_order_assigned_after_add() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 10.0, 0.0);
        s.add_survey("Serbule".into(), 5.0, 0.0);
        // nearest to (0,0): idx1 (5,0) → order 1; idx0 (10,0) → order 2
        assert_eq!(s.surveys[1].route_order, Some(1)); // (5,0) is closer
        assert_eq!(s.surveys[0].route_order, Some(2));
    }

    #[test]
    fn test_add_motherlode_reading() {
        let mut s = AppState::default();
        s.add_motherlode_reading((0.0, 0.0), 100.0);
        assert_eq!(s.motherlode_readings.len(), 1);
        assert!(s.motherlode_location.is_none()); // need 3 to triangulate
    }

    #[test]
    fn test_clear_surveys() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 1.0, 2.0);
        s.clear_surveys();
        assert!(s.surveys.is_empty());
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd src-tauri && cargo test state
```

Expected: FAIL.

**Step 3: Implement `src-tauri/src/state.rs`**

```rust
use crate::path_optimizer::optimize_path;
use crate::triangulator::triangulate;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU32, Ordering};

static NEXT_ID: AtomicU32 = AtomicU32::new(1);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Survey {
    pub id: u32,
    pub zone: String,
    pub x: f64,
    pub y: f64,
    pub collected: bool,
    pub route_order: Option<usize>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct AppState {
    pub surveys: Vec<Survey>,
    pub motherlode_readings: Vec<((f64, f64), f64)>,
    pub motherlode_location: Option<(f64, f64)>,
    pub player_position: Option<(f64, f64)>,
}

impl AppState {
    pub fn add_survey(&mut self, zone: String, x: f64, y: f64) {
        self.surveys.push(Survey {
            id: NEXT_ID.fetch_add(1, Ordering::SeqCst),
            zone,
            x,
            y,
            collected: false,
            route_order: None,
        });
        self.recalculate_route();
    }

    pub fn mark_collected(&mut self, id: u32) {
        if let Some(s) = self.surveys.iter_mut().find(|s| s.id == id) {
            s.collected = true;
        }
        self.recalculate_route();
    }

    pub fn add_motherlode_reading(&mut self, pos: (f64, f64), distance: f64) {
        self.motherlode_readings.push((pos, distance));
        if self.motherlode_readings.len() >= 3 {
            self.motherlode_location = triangulate(&self.motherlode_readings);
        }
    }

    pub fn clear_surveys(&mut self) {
        self.surveys.clear();
    }

    pub fn clear_motherlode(&mut self) {
        self.motherlode_readings.clear();
        self.motherlode_location = None;
    }

    fn recalculate_route(&mut self) {
        let active: Vec<(usize, &Survey)> = self.surveys
            .iter()
            .enumerate()
            .filter(|(_, s)| !s.collected)
            .collect();

        let points: Vec<(f64, f64)> = active.iter().map(|(_, s)| (s.x, s.y)).collect();
        let start = self.player_position.unwrap_or((0.0, 0.0));
        let order = optimize_path(start, &points);

        for s in self.surveys.iter_mut() {
            s.route_order = None;
        }
        for (route_pos, &point_idx) in order.iter().enumerate() {
            let survey_idx = active[point_idx].0;
            self.surveys[survey_idx].route_order = Some(route_pos + 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_survey_appends() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        assert_eq!(s.surveys.len(), 1);
        assert_eq!(s.surveys[0].x, 100.0);
        assert!(!s.surveys[0].collected);
    }

    #[test]
    fn test_mark_collected() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        let id = s.surveys[0].id;
        s.mark_collected(id);
        assert!(s.surveys[0].collected);
    }

    #[test]
    fn test_route_order_assigned_after_add() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 10.0, 0.0);
        s.add_survey("Serbule".into(), 5.0, 0.0);
        assert_eq!(s.surveys[1].route_order, Some(1));
        assert_eq!(s.surveys[0].route_order, Some(2));
    }

    #[test]
    fn test_add_motherlode_reading() {
        let mut s = AppState::default();
        s.add_motherlode_reading((0.0, 0.0), 100.0);
        assert_eq!(s.motherlode_readings.len(), 1);
        assert!(s.motherlode_location.is_none());
    }

    #[test]
    fn test_clear_surveys() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 1.0, 2.0);
        s.clear_surveys();
        assert!(s.surveys.is_empty());
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
cd src-tauri && cargo test state
```

Expected: 5 tests PASS.

**Step 5: Create `src-tauri/src/commands.rs`**

```rust
use crate::config::Config;
use crate::state::AppState;
use std::sync::{Arc, Mutex};
use tauri::State;

pub type SharedState = Arc<Mutex<AppState>>;
pub type SharedConfig = Arc<Mutex<Config>>;

#[tauri::command]
pub fn get_state(state: State<SharedState>) -> AppState {
    state.lock().unwrap().clone()
}

#[tauri::command]
pub fn get_config(config: State<SharedConfig>) -> Config {
    config.lock().unwrap().clone()
}

#[tauri::command]
pub fn save_config(new_config: Config, config: State<SharedConfig>) -> Result<(), String> {
    let mut c = config.lock().unwrap();
    new_config.save().map_err(|e| e.to_string())?;
    *c = new_config;
    Ok(())
}

#[tauri::command]
pub fn clear_surveys(state: State<SharedState>) {
    state.lock().unwrap().clear_surveys();
}

#[tauri::command]
pub fn clear_motherlode(state: State<SharedState>) {
    state.lock().unwrap().clear_motherlode();
}

#[tauri::command]
pub fn skip_survey(id: u32, state: State<SharedState>) {
    state.lock().unwrap().mark_collected(id);
}

#[tauri::command]
pub fn add_motherlode_reading(x: f64, y: f64, distance: f64, state: State<SharedState>) {
    state.lock().unwrap().add_motherlode_reading((x, y), distance);
}

#[tauri::command]
pub fn get_zones() -> Vec<String> {
    crate::zones::ZONES.iter().map(|(name, _)| name.to_string()).collect()
}
```

**Step 6: Update `src-tauri/src/main.rs`**

```rust
mod commands;
mod config;
mod log_parser;
mod log_watcher;
mod path_optimizer;
mod state;
mod triangulator;
mod zones;

use commands::{SharedConfig, SharedState};
use config::Config;
use state::AppState;
use std::sync::{Arc, Mutex};

fn main() {
    let config = Config::load();
    let app_state = Arc::new(Mutex::new(AppState::default()));
    let app_config = Arc::new(Mutex::new(config));

    tauri::Builder::default()
        .manage(app_state.clone())
        .manage(app_config.clone())
        .setup(move |app| {
            // Make overlay window click-through
            if let Some(overlay) = app.get_webview_window("overlay") {
                overlay.set_ignore_cursor_events(true).ok();
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_state,
            commands::get_config,
            commands::save_config,
            commands::clear_surveys,
            commands::clear_motherlode,
            commands::skip_survey,
            commands::add_motherlode_reading,
            commands::get_zones,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Note: `mod log_watcher;` and `mod zones;` are referenced here but created in Tasks 7 and 8. Create stub files first:

```bash
echo "// stub" > src-tauri/src/log_watcher.rs
echo "// stub" > src-tauri/src/zones.rs
```

**Step 7: Build to verify it compiles**

```bash
cd src-tauri && cargo build
```

Expected: Compiles without errors.

**Step 8: Commit**

```bash
git add src-tauri/src/state.rs src-tauri/src/commands.rs src-tauri/src/main.rs src-tauri/src/log_watcher.rs src-tauri/src/zones.rs
git commit -m "feat: add app state, Tauri IPC commands, and shared state management"
```

---

### Task 7: Zone definitions

**Files:**
- Modify: `src-tauri/src/zones.rs`

**Step 1: Implement `src-tauri/src/zones.rs`**

> **Note:** Coordinate bounds below are placeholders. They MUST be updated after in-game verification in Task 13.

```rust
/// Zone bounding boxes as (name, (min_x, min_y, max_x, max_y)) in game world units.
/// TODO: Validate these bounds in-game by checking coordinates at zone edges.
pub const ZONES: &[(&str, (f64, f64, f64, f64))] = &[
    ("Serbule",         (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Eltibule",        (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Kur Mountains",   (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Povus",           (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Ilmari",          (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Gazluk",          (-2048.0, -2048.0, 2048.0, 2048.0)),
];

pub fn bounds_for(zone: &str) -> (f64, f64, f64, f64) {
    ZONES.iter()
        .find(|(name, _)| *name == zone)
        .map(|(_, b)| *b)
        .unwrap_or((-2048.0, -2048.0, 2048.0, 2048.0))
}
```

**Step 2: Build to verify**

```bash
cd src-tauri && cargo build
```

**Step 3: Commit**

```bash
git add src-tauri/src/zones.rs
git commit -m "feat: add zone coordinate bounds (placeholder values pending validation)"
```

---

### Task 8: Log file watcher (Rust)

**Files:**
- Modify: `src-tauri/src/log_watcher.rs`
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Add `notify` to `src-tauri/Cargo.toml`**

```toml
notify = "6"
```

**Step 2: Implement `src-tauri/src/log_watcher.rs`**

```rust
use crate::log_parser::{parse_line, LogEvent};
use crate::state::AppState;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::fs::File;
use std::io::{BufRead, BufReader, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter};

pub fn start_watching(
    log_path: PathBuf,
    state: Arc<Mutex<AppState>>,
    app: AppHandle,
) -> Result<RecommendedWatcher, Box<dyn std::error::Error + Send + Sync>> {
    let file = File::open(&log_path)?;
    let mut reader = BufReader::new(file);
    // Seek to end so we only see new lines going forward
    reader.seek(SeekFrom::End(0))?;
    let reader = Arc::new(Mutex::new(reader));

    let reader_clone = reader.clone();
    let log_path_clone = log_path.clone();

    let mut watcher = notify::recommended_watcher(move |res: notify::Result<Event>| {
        if let Ok(event) = res {
            if matches!(event.kind, EventKind::Modify(_)) {
                let mut r = reader_clone.lock().unwrap();
                let mut line = String::new();
                while r.read_line(&mut line).unwrap_or(0) > 0 {
                    if let Some(evt) = parse_line(line.trim()) {
                        handle_log_event(evt, &state, &app);
                    }
                    line.clear();
                }
            }
        }
    })?;

    watcher.watch(&log_path_clone, RecursiveMode::NonRecursive)?;
    Ok(watcher)
}

fn handle_log_event(event: LogEvent, state: &Arc<Mutex<AppState>>, app: &AppHandle) {
    let mut s = state.lock().unwrap();
    match event {
        LogEvent::SurveyPlaced { zone, x, y } => {
            s.add_survey(zone, x, y);
        }
        LogEvent::MotherlodeDistance { meters } => {
            if let Some(pos) = s.player_position {
                s.add_motherlode_reading(pos, meters);
            }
        }
        LogEvent::SurveyCollected => {
            // Mark the first active survey (lowest route order) as collected
            if let Some(id) = s.surveys.iter()
                .filter(|s| !s.collected)
                .min_by_key(|s| s.route_order.unwrap_or(usize::MAX))
                .map(|s| s.id)
            {
                s.mark_collected(id);
            }
        }
    }
    let _ = app.emit("state-updated", s.clone());
}
```

**Step 3: Add `start_watching` command to `src-tauri/src/commands.rs`**

Add to the commands file:

```rust
#[tauri::command]
pub async fn start_log_watching(
    log_path: String,
    state: State<'_, SharedState>,
    config: State<'_, SharedConfig>,
    app: tauri::AppHandle,
) -> Result<(), String> {
    let path = std::path::PathBuf::from(&log_path);
    if !path.exists() {
        return Err(format!("File not found: {}", log_path));
    }

    // Persist log path in config
    {
        let mut c = config.lock().unwrap();
        c.log_path = log_path;
        c.save().map_err(|e| e.to_string())?;
    }

    let state_arc = state.inner().clone();
    std::thread::spawn(move || {
        match crate::log_watcher::start_watching(path, state_arc, app) {
            Ok(_watcher) => loop {
                std::thread::sleep(std::time::Duration::from_secs(60));
            },
            Err(e) => eprintln!("Log watcher error: {e}"),
        }
    });

    Ok(())
}
```

Add `commands::start_log_watching` to the `invoke_handler` list in `main.rs`.

**Step 4: Auto-start watcher in setup if log path is already configured**

In `main.rs` setup:

```rust
.setup(move |app| {
    if let Some(overlay) = app.get_webview_window("overlay") {
        overlay.set_ignore_cursor_events(true).ok();
    }
    // Auto-start watcher if log path was previously configured
    let cfg = app_config.lock().unwrap().clone();
    if !cfg.log_path.is_empty() {
        let path = std::path::PathBuf::from(&cfg.log_path);
        if path.exists() {
            let state_clone = app_state.clone();
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                match crate::log_watcher::start_watching(path, state_clone, handle) {
                    Ok(_w) => loop { std::thread::sleep(std::time::Duration::from_secs(60)); },
                    Err(e) => eprintln!("Auto-start watcher error: {e}"),
                }
            });
        }
    }
    Ok(())
})
```

**Step 5: Build to verify**

```bash
cd src-tauri && cargo build
```

Expected: Compiles.

**Step 6: Commit**

```bash
git add src-tauri/src/log_watcher.rs src-tauri/src/commands.rs src-tauri/src/main.rs src-tauri/Cargo.toml
git commit -m "feat: add log file watcher that tails chat log and emits state-updated events"
```

---

### Task 9: React frontend — routing and shared state hook

**Files:**
- Modify: `src/main.tsx`
- Create: `src/hooks/useSurveyState.ts`

**Step 1: Install React Router**

```bash
npm install react-router-dom
```

**Step 2: Update `src/main.tsx`**

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { HashRouter, Routes, Route } from 'react-router-dom';
import ControlPanel from './pages/ControlPanel';
import Overlay from './pages/Overlay';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <HashRouter>
      <Routes>
        <Route path="/" element={<ControlPanel />} />
        <Route path="/overlay" element={<Overlay />} />
      </Routes>
    </HashRouter>
  </React.StrictMode>
);
```

**Step 3: Create `src/hooks/useSurveyState.ts`**

```typescript
import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export interface Survey {
  id: number;
  zone: string;
  x: number;
  y: number;
  collected: boolean;
  route_order: number | null;
}

export interface AppState {
  surveys: Survey[];
  motherlode_readings: [[[number, number], number]];
  motherlode_location: [number, number] | null;
  player_position: [number, number] | null;
}

const EMPTY_STATE: AppState = {
  surveys: [],
  motherlode_readings: [] as any,
  motherlode_location: null,
  player_position: null,
};

export function useSurveyState() {
  const [state, setState] = useState<AppState>(EMPTY_STATE);

  useEffect(() => {
    invoke<AppState>('get_state').then(setState).catch(console.error);

    const unlisten = listen<AppState>('state-updated', (event) => {
      setState(event.payload);
    });

    return () => {
      unlisten.then(f => f());
    };
  }, []);

  return state;
}
```

**Step 4: Create `src/pages/ControlPanel.tsx` and `src/pages/Overlay.tsx` as stubs**

```tsx
// src/pages/ControlPanel.tsx
export default function ControlPanel() {
  return <div style={{ padding: 16 }}><h2>Gorgon Survey Tool</h2></div>;
}
```

```tsx
// src/pages/Overlay.tsx
export default function Overlay() {
  return <div style={{ width: '100vw', height: '100vh', background: 'transparent' }} />;
}
```

**Step 5: Run to verify routing works**

```bash
npm run tauri dev
```

Expected: Both windows open; control panel shows heading.

**Step 6: Commit**

```bash
git add src/
git commit -m "feat: add React routing and shared survey state hook"
```

---

### Task 10: Control panel UI

**Files:**
- Modify: `src/pages/ControlPanel.tsx`
- Create: `src/components/SurveyList.tsx`
- Create: `src/components/MotherlodePanel.tsx`
- Create: `src/components/Settings.tsx`

**Step 1: Create `src/components/SurveyList.tsx`**

```tsx
import { invoke } from '@tauri-apps/api/core';
import { Survey } from '../hooks/useSurveyState';

export default function SurveyList({ surveys }: { surveys: Survey[] }) {
  const active = surveys
    .filter(s => !s.collected)
    .sort((a, b) => (a.route_order ?? 999) - (b.route_order ?? 999));

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Surveys ({active.length})</h3>
        <button onClick={() => invoke('clear_surveys')}>Clear All</button>
      </div>
      {active.length === 0 && <p style={{ color: '#888', fontSize: 13 }}>No surveys detected yet</p>}
      <ul style={{ listStyle: 'none', padding: 0, margin: '8px 0' }}>
        {active.map(s => (
          <li key={s.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid #eee' }}>
            <span>
              <b style={{ color: '#FFAA00' }}>#{s.route_order}</b>{' '}
              ({Math.round(s.x)}, {Math.round(s.y)})
            </span>
            <button onClick={() => invoke('skip_survey', { id: s.id })} style={{ fontSize: 12 }}>Skip</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

**Step 2: Create `src/components/MotherlodePanel.tsx`**

```tsx
import { useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface Props {
  readings: [[[number, number], number]];
  location: [number, number] | null;
}

export default function MotherlodePanel({ readings, location }: Props) {
  const [pos, setPos] = useState({ x: '', y: '', dist: '' });

  const addManual = () => {
    invoke('add_motherlode_reading', {
      x: parseFloat(pos.x),
      y: parseFloat(pos.y),
      distance: parseFloat(pos.dist),
    });
    setPos({ x: '', y: '', dist: '' });
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Motherlode ({readings?.length ?? 0}/3)</h3>
        <button onClick={() => invoke('clear_motherlode')}>Reset</button>
      </div>

      {location && (
        <p style={{ color: '#FF44FF', fontWeight: 'bold' }}>
          Found at: ({Math.round(location[0])}, {Math.round(location[1])})
        </p>
      )}

      {(readings?.length ?? 0) < 3 && !location && (
        <p style={{ color: '#888', fontSize: 13 }}>
          Use the motherlode survey from 3 different positions.
        </p>
      )}

      <details style={{ marginTop: 8 }}>
        <summary style={{ cursor: 'pointer', fontSize: 13 }}>Add reading manually</summary>
        <div style={{ display: 'flex', gap: 4, marginTop: 6 }}>
          <input placeholder="X" value={pos.x} onChange={e => setPos(p => ({ ...p, x: e.target.value }))} style={{ width: 55 }} />
          <input placeholder="Y" value={pos.y} onChange={e => setPos(p => ({ ...p, y: e.target.value }))} style={{ width: 55 }} />
          <input placeholder="Dist" value={pos.dist} onChange={e => setPos(p => ({ ...p, dist: e.target.value }))} style={{ width: 55 }} />
          <button onClick={addManual}>Add</button>
        </div>
      </details>
    </div>
  );
}
```

**Step 3: Create `src/components/Settings.tsx`**

```tsx
import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';

export default function Settings({ onClose }: { onClose: () => void }) {
  const [logPath, setLogPath] = useState('');
  const [status, setStatus] = useState('');

  useEffect(() => {
    invoke<any>('get_config').then(c => setLogPath(c.log_path || ''));
  }, []);

  const save = async () => {
    try {
      await invoke('start_log_watching', { logPath });
      setStatus('Watching log file!');
    } catch (e) {
      setStatus(`Error: ${e}`);
    }
  };

  return (
    <div style={{ padding: 16 }}>
      <h3>Settings</h3>
      <label style={{ fontSize: 13 }}>Chat Log Path:</label>
      <input
        value={logPath}
        onChange={e => setLogPath(e.target.value)}
        style={{ width: '100%', marginTop: 4, boxSizing: 'border-box' }}
        placeholder="Path to chat log file..."
      />
      <p style={{ fontSize: 11, color: '#888', margin: '4px 0' }}>
        Proton example: ~/.steam/steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/AppData/Roaming/ProjectGorgon/chat.log
      </p>
      {status && (
        <p style={{ color: status.startsWith('Error') ? 'red' : 'green', fontSize: 13 }}>{status}</p>
      )}
      <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
        <button onClick={save}>Save & Watch</button>
        <button onClick={onClose}>Close</button>
      </div>
    </div>
  );
}
```

**Step 4: Implement the full `src/pages/ControlPanel.tsx`**

```tsx
import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { useSurveyState } from '../hooks/useSurveyState';
import SurveyList from '../components/SurveyList';
import MotherlodePanel from '../components/MotherlodePanel';
import Settings from '../components/Settings';

type Mode = 'survey' | 'motherlode';

export default function ControlPanel() {
  const state = useSurveyState();
  const [mode, setMode] = useState<Mode>('survey');
  const [showSettings, setShowSettings] = useState(false);
  const [zones, setZones] = useState<string[]>([]);
  const [zone, setZone] = useState('Serbule');

  useEffect(() => {
    invoke<string[]>('get_zones').then(setZones);
    invoke<any>('get_config').then(c => {
      if (c.current_zone) setZone(c.current_zone);
    });
  }, []);

  const onZoneChange = (z: string) => {
    setZone(z);
    invoke('get_config').then((c: any) => invoke('save_config', { newConfig: { ...c, current_zone: z } }));
  };

  return (
    <div style={{ padding: 16, fontFamily: 'sans-serif', maxWidth: 400 }}>
      {showSettings ? (
        <Settings onClose={() => setShowSettings(false)} />
      ) : (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h2 style={{ margin: 0, fontSize: 18 }}>Gorgon Survey</h2>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <select value={zone} onChange={e => onZoneChange(e.target.value)}>
                {zones.map(z => <option key={z}>{z}</option>)}
              </select>
              <button onClick={() => setShowSettings(true)}>⚙</button>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <button
              onClick={() => setMode('survey')}
              style={{ flex: 1, fontWeight: mode === 'survey' ? 'bold' : 'normal' }}
            >
              Regular Survey
            </button>
            <button
              onClick={() => setMode('motherlode')}
              style={{ flex: 1, fontWeight: mode === 'motherlode' ? 'bold' : 'normal' }}
            >
              Motherlode
            </button>
          </div>

          <hr style={{ margin: '0 0 12px' }} />

          {mode === 'survey'
            ? <SurveyList surveys={state.surveys} />
            : <MotherlodePanel readings={state.motherlode_readings} location={state.motherlode_location} />
          }
        </>
      )}
    </div>
  );
}
```

**Step 5: Run and visually verify the control panel**

```bash
npm run tauri dev
```

Expected: Zone dropdown, mode tabs, empty survey list, settings gear button all visible.

**Step 6: Commit**

```bash
git add src/
git commit -m "feat: implement full control panel UI with survey list and motherlode panel"
```

---

### Task 11: Overlay canvas rendering

**Files:**
- Modify: `src/pages/Overlay.tsx`

**Step 1: Implement `src/pages/Overlay.tsx`**

```tsx
import { useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useSurveyState, AppState } from '../hooks/useSurveyState';

// Coordinate mapping: game world → canvas pixels
function gameToCanvas(
  gx: number, gy: number,
  bounds: [number, number, number, number],
  W: number, H: number
): [number, number] {
  const [minX, minY, maxX, maxY] = bounds;
  return [
    ((gx - minX) / (maxX - minX)) * W,
    ((gy - minY) / (maxY - minY)) * H,
  ];
}

interface Config {
  current_zone: string;
  overlay: { width: number; height: number };
  colors: { uncollected: string; collected: string; waypoint: string; motherlode: string };
}

// Zone bounds - kept in sync with src-tauri/src/zones.rs
const ZONE_BOUNDS: Record<string, [number, number, number, number]> = {
  'Serbule':       [-2048, -2048, 2048, 2048],
  'Eltibule':      [-2048, -2048, 2048, 2048],
  'Kur Mountains': [-2048, -2048, 2048, 2048],
  'Povus':         [-2048, -2048, 2048, 2048],
  'Ilmari':        [-2048, -2048, 2048, 2048],
  'Gazluk':        [-2048, -2048, 2048, 2048],
};

export default function Overlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [config, setConfig] = useState<Config | null>(null);

  useEffect(() => {
    invoke<Config>('get_config').then(setConfig);
    const unlisten = listen<Config>('config-updated', e => setConfig(e.payload));
    return () => { unlisten.then(f => f()); };
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !config) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    const zone = config.current_zone;
    const bounds = ZONE_BOUNDS[zone] ?? [-2048, -2048, 2048, 2048];
    const { uncollected, waypoint, motherlode } = config.colors;

    // Draw dashed route lines
    const ordered = state.surveys
      .filter(s => !s.collected && s.route_order !== null)
      .sort((a, b) => a.route_order! - b.route_order!);

    if (ordered.length > 1) {
      ctx.strokeStyle = waypoint;
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      const [fx, fy] = gameToCanvas(ordered[0].x, ordered[0].y, bounds, W, H);
      ctx.moveTo(fx, fy);
      for (let i = 1; i < ordered.length; i++) {
        const [nx, ny] = gameToCanvas(ordered[i].x, ordered[i].y, bounds, W, H);
        ctx.lineTo(nx, ny);
      }
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Draw survey dots
    for (const survey of state.surveys) {
      if (survey.collected) continue;
      const [cx, cy] = gameToCanvas(survey.x, survey.y, bounds, W, H);
      ctx.beginPath();
      ctx.arc(cx, cy, 9, 0, Math.PI * 2);
      ctx.fillStyle = uncollected;
      ctx.fill();
      if (survey.route_order !== null) {
        ctx.fillStyle = '#000';
        ctx.font = 'bold 10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(String(survey.route_order), cx, cy);
      }
    }

    // Draw motherlode distance circles
    if (state.motherlode_readings?.length > 0) {
      const span = bounds[2] - bounds[0];
      for (const [[px, py], dist] of state.motherlode_readings) {
        const [cx, cy] = gameToCanvas(px, py, bounds, W, H);
        const scaledR = (dist / span) * W;
        ctx.beginPath();
        ctx.arc(cx, cy, scaledR, 0, Math.PI * 2);
        ctx.strokeStyle = motherlode + '88';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
    }

    // Draw triangulated motherlode location
    if (state.motherlode_location) {
      const [mx, my] = state.motherlode_location;
      const [cx, cy] = gameToCanvas(mx, my, bounds, W, H);
      ctx.beginPath();
      ctx.arc(cx, cy, 11, 0, Math.PI * 2);
      ctx.fillStyle = motherlode;
      ctx.fill();
      // X marker
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(cx - 6, cy - 6); ctx.lineTo(cx + 6, cy + 6);
      ctx.moveTo(cx + 6, cy - 6); ctx.lineTo(cx - 6, cy + 6);
      ctx.stroke();
    }
  }, [state, config]);

  return (
    <div style={{ width: '100vw', height: '100vh', background: 'transparent', pointerEvents: 'none' }}>
      <canvas
        ref={canvasRef}
        width={window.innerWidth}
        height={window.innerHeight}
        style={{ display: 'block' }}
      />
    </div>
  );
}
```

**Step 2: Run and verify the overlay renders**

```bash
npm run tauri dev
```

Expected: Transparent overlay window. If you inject test state (via Rust test or direct command), dots and lines should appear.

**Step 3: Commit**

```bash
git add src/pages/Overlay.tsx
git commit -m "feat: implement overlay canvas with survey dots, route lines, and motherlode visualization"
```

---

### Task 12: End-to-end testing and log pattern validation

> This task is done manually in-game. It validates and fixes the log parser regex patterns.

**Step 1: Enable chat logging in Project Gorgon**

1. Launch the game via Steam (Proton)
2. Open Settings → VIP tab → enable "Log chat to file"
3. Find the log file. Common path: `~/.steam/steam/steamapps/compatdata/<APPID>/pfx/drive_c/users/steamuser/AppData/Roaming/ProjectGorgon/`

List files to find the log:
```bash
find ~/.steam -name "*.log" -path "*/ProjectGorgon/*" 2>/dev/null
find ~/.local/share/Steam -name "*.log" -path "*/ProjectGorgon/*" 2>/dev/null
```

**Step 2: Configure the tool**

Open the control panel. Enter the log path in Settings and click "Save & Watch".

**Step 3: Test regular survey parsing**

1. Have survey maps in inventory
2. Right-click a survey map in-game
3. Check: does a new entry appear in the survey list?

If not, open the log file and look at the actual message format:
```bash
tail -f /path/to/chat.log
```

Compare the actual lines to the regex patterns in `src-tauri/src/log_parser.rs`. Update the patterns to match.

**Step 4: Re-run Rust tests after updating patterns**

```bash
cd src-tauri && cargo test log_parser
```

Update the test strings to match the real format, then make the implementation pass.

**Step 5: Test motherlode triangulation**

1. Use a motherlode survey map in-game from 3 different positions
2. Check: do distance readings appear in the Motherlode panel?
3. Check: after 3 readings, does a pink dot appear on the overlay?

**Step 6: Validate and update zone coordinate bounds**

1. Enable coordinate display in-game (check settings or use `/pos` if available)
2. Note coordinates at the edges of each zone
3. Update `ZONES` in `src-tauri/src/zones.rs` with real values
4. Update `ZONE_BOUNDS` in `src/pages/Overlay.tsx` to match

**Step 7: Commit validated patterns and bounds**

```bash
git add src-tauri/src/log_parser.rs src-tauri/src/zones.rs src/pages/Overlay.tsx
git commit -m "fix: update log parser patterns and zone bounds from in-game validation"
```

---

## Summary

| Task | Builds | Test command |
|------|--------|--------------|
| 1 | Tauri + React scaffold, two windows | `npm run tauri dev` |
| 2 | Config TOML load/save | `cargo test config` |
| 3 | Log parser (regex) | `cargo test log_parser` |
| 4 | Path optimizer (TSP) | `cargo test path_optimizer` |
| 5 | Motherlode triangulator | `cargo test triangulator` |
| 6 | App state + IPC commands | `cargo test state` + `cargo build` |
| 7 | Zone definitions | `cargo build` |
| 8 | Log file watcher | `cargo build` |
| 9 | React routing + state hook | `npm run tauri dev` |
| 10 | Control panel UI | `npm run tauri dev` |
| 11 | Overlay canvas | `npm run tauri dev` |
| 12 | E2E validation (manual) | In-game testing |

All Rust unit tests:
```bash
cd src-tauri && cargo test
```
