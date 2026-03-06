# Gorgon Survey Tool

A cross-platform desktop companion for the [Surveying](https://wiki.projectgorgon.com/wiki/Surveying) skill in Project Gorgon. Reads the game's chat log to detect survey locations, displays a transparent overlay on the game map with an optimized collection route, and triangulates motherlode positions from distance readings.

Inspired by [PgSurveyor](https://github.com/dlebansais/PgSurveyor-Disclosed).

---

## Features

- **Transparent overlay** — click-through window sits on top of the game map, showing survey dots numbered in optimal collection order
- **Path optimization** — nearest-neighbor route calculation so you visit surveys in the shortest order
- **Motherlode triangulation** — click the motherlode survey from 3 positions to pin-point its location using circle intersection math
- **Chat log parsing** — reads the game's log file in real time; no client modification or packet sniffing
- **Zone support** — Serbule, Eltibule, Kur Mountains, Povus, Ilmari, Gazluk

---

## Requirements

### System (Linux)

Install these via your package manager before building:

**Arch Linux:**
```bash
sudo pacman -S webkit2gtk-4.1 libayatana-appindicator librsvg
```

**Ubuntu/Debian:**
```bash
sudo apt install libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev
```

**Fedora:**
```bash
sudo dnf install webkit2gtk4.1-devel libayatana-appindicator-gtk3-devel librsvg2-devel
```

### Tools (managed via mise)

The project uses [mise](https://mise.jdx.dev/) to manage tool versions. Install mise first:

```bash
curl https://mise.run | sh
```

Then install project tools from the project root:

```bash
mise trust
mise install
```

This installs:
- `rust` (latest stable)
- `node` (LTS)
- `cargo:tauri-cli` (v2)

---

## Running in Development

```bash
# Install npm dependencies
mise exec -- npm install

# Start the dev server (hot-reload for the frontend, rebuilds Rust on change)
mise exec -- npm run tauri dev
```

Two windows will open:
- **Control Panel** — zone selector, survey list, motherlode panel, settings
- **Overlay** — transparent, click-through window (position this over your game map)

---

## Building for Production

```bash
mise exec -- npm run tauri build
```

The compiled binary and installer are placed in `src-tauri/target/release/bundle/`.

---

## First-Time Setup

### 1. Enable chat logging in Project Gorgon

In-game: **Menu → Settings → VIP tab → Enable chat logging**

### 2. Find your log file path

**If running via Steam + Proton (Linux):**

```bash
find ~/.steam -name "*.log" -path "*/ProjectGorgon/*" 2>/dev/null
# or
find ~/.local/share/Steam -name "*.log" -path "*/ProjectGorgon/*" 2>/dev/null
```

The path is typically:
```
~/.steam/steam/steamapps/compatdata/<APPID>/pfx/drive_c/users/steamuser/AppData/Roaming/ProjectGorgon/chat.log
```

**If running natively on Windows:**
```
%APPDATA%\ProjectGorgon\chat.log
```

### 3. Configure the tool

1. Launch the tool (`mise exec -- npm run tauri dev` or the compiled binary)
2. Click the **⚙** (gear) button in the Control Panel
3. Paste your log file path into the **Chat Log Path** field
4. Click **Save & Watch**

The status message will confirm the tool is watching the file.

---

## Using Regular Surveys

1. Select your current zone from the dropdown
2. Right-click survey maps in-game — each one adds a numbered dot to the overlay
3. Visit the surveys in the numbered order shown on the overlay
4. Collected surveys are removed automatically from the route
5. Use **Skip** to manually remove a survey from the list, **Clear All** to reset

---

## Using Motherlode Surveys

Motherlode surveys only tell you the distance to the resource, not the location. The tool triangulates the position from 3 readings.

1. Switch to **Motherlode** mode in the Control Panel
2. Click the motherlode survey map from your first position — the tool records the distance
3. Move to a different location and click again
4. Move to a third location and click a final time
5. After 3 readings the tool pins the location on the overlay with a pink marker

> **Note:** Auto-detection from the log requires the game to output player coordinates alongside the distance message. If auto-detection doesn't work, use **Add reading manually** in the Motherlode panel — enter your current X, Y coordinates and the distance shown in chat.

---

## Calibrating the Overlay

The overlay window is a transparent, always-on-top window. Position and resize it using your window manager to align with the game's map area. The game must run in **windowed or borderless-windowed mode** — fullscreen is not supported.

Config is stored at `~/.config/gorgon-survey/settings.toml` and overlay position is restored on next launch.

---

## Configuration File

Settings are saved automatically. You can also edit `~/.config/gorgon-survey/settings.toml` directly:

```toml
log_path = "/path/to/ProjectGorgon/chat.log"
current_zone = "Serbule"

[overlay]
x = 100
y = 200
width = 500
height = 500
opacity = 0.9

[colors]
uncollected = "#FF4444"
collected = "#44FF44"
waypoint = "#FFFF00"
motherlode = "#FF00FF"
```

---

## Known Limitations (v0.1.0)

- **Log parser patterns are placeholder** — the exact chat message format for survey placement has not been validated against a live game session. If surveys are not detected automatically, open the log file and check the actual format, then update the regex patterns in `src-tauri/src/log_parser.rs`.
- **Zone coordinate bounds are approximate** — survey dots may appear in incorrect positions until real bounds are measured in-game and updated in `src-tauri/src/zones.rs` and `src/pages/Overlay.tsx`.
- **Motherlode auto-detection requires player coordinates** — the tool needs to know where you are standing when you click the motherlode survey. Use the manual entry form as a workaround until the player position log format is confirmed.
- **Windowed mode only** — the transparent overlay requires the game to run in windowed or borderless-windowed mode.
- **One log file at a time** — changing the log path requires restarting the app.

---

## Development

### Running tests

```bash
# Rust unit tests
cd src-tauri && mise exec -- cargo test

# Frontend type check + build
mise exec -- npx vite build
```

### Project structure

```
gorgon-survey/
├── src/                        # React frontend
│   ├── pages/
│   │   ├── ControlPanel.tsx    # Main control panel window
│   │   └── Overlay.tsx         # Transparent canvas overlay
│   ├── components/
│   │   ├── SurveyList.tsx
│   │   ├── MotherlodePanel.tsx
│   │   └── Settings.tsx
│   └── hooks/
│       └── useSurveyState.ts   # Shared Tauri state hook
├── src-tauri/                  # Rust backend
│   └── src/
│       ├── lib.rs              # Tauri app setup and wiring
│       ├── state.rs            # AppState: surveys, motherlode, routing
│       ├── commands.rs         # Tauri IPC commands
│       ├── log_watcher.rs      # File watcher (notify crate)
│       ├── log_parser.rs       # Chat log regex parser
│       ├── path_optimizer.rs   # Nearest-neighbor TSP
│       ├── triangulator.rs     # Circle intersection math
│       ├── zones.rs            # Zone coordinate bounds
│       └── config.rs           # TOML config load/save
└── docs/
    └── plans/                  # Design and implementation docs
```

### Updating log parser patterns

Open `src-tauri/src/log_parser.rs` and update the regex strings. Run tests after:

```bash
cd src-tauri && mise exec -- cargo test log_parser
```

Update the test strings in the same file to match the real game format before running.

### Updating zone bounds

Measure coordinates at zone edges in-game, then update both files (they must stay in sync):
- `src-tauri/src/zones.rs` — `ZONES` constant
- `src/pages/Overlay.tsx` — `ZONE_BOUNDS` object
