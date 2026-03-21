# CLAUDE.md

## Tool Management

All commands must be prefixed with `mise exec --`. Tools (Elixir, Erlang, Node) are managed via `.mise.toml`.

## Commands

```bash
# Install dependencies
mise exec -- mix deps.get

# Dev server (hot-reload)
mise exec -- mix phx.server

# Interactive console
mise exec -- iex -S mix phx.server

# Run all tests
mise exec -- mix test

# Run specific test file
mise exec -- mix test test/gorgon_survey/log_parser_test.exs

# Compile check
mise exec -- mix compile --warnings-as-errors

# Pre-commit (compile check + unlock unused deps + format + test)
mise exec -- mix precommit

# Desktop app development (requires X11)
npx tauri dev

# Build desktop release
./scripts/build-desktop.sh
```

## Architecture

Phoenix LiveView game companion for Project Gorgon with Tauri v2 desktop wrapper. Two LiveView pages: sidebar at `/` and transparent overlay at `/overlay`. No database. Multi-session: each browser tab/overlay gets its own isolated session with independent LogWatcher and state.

### Data Flow

```
chat.log → FileSystem watcher → LogWatcher GenServer (per session) → LogParser (regex)
  → AppState (pure struct) → PubSub ("game_state:#{session_id}")
  → SurveyLive/OverlayLive LiveView → push_event → JS Hooks → canvas

Tauri Commands: capture_and_detect, create_overlay_window, toggle_overlay_interaction,
  set_collect_hotkey, register_hotkeys
```

### Key Modules

| Module | Responsibility |
|---|---|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into structured events (surveys, motherlode readings) |
| `GorgonSurvey.AppState` | Pure state struct — survey/motherlode management, no side effects |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file via FileSystem (local) or WebSocket ingestion (remote), maintains AppState, broadcasts via scoped PubSub |
| `GorgonSurvey.SessionManager` | Tracks active sessions, manages per-session LogWatcher lifecycle, config overrides, 30s cleanup timers |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json`, global and session-aware get/put |
| `GorgonSurvey.SurveyDetector` | Image processing via Vix/VIPS — red circle detection + player triangle detection |
| `GorgonSurvey.Trilateration` | Least-squares trilateration from 3+ motherlode distance readings via gradient descent |
| `GorgonSurveyWeb.SurveyLive` | Main sidebar LiveView — log folder, auto-detect toggle, zone setup, survey/motherlode management |
| `GorgonSurveyWeb.OverlayLive` | Transparent overlay LiveView — receives state updates, renders markers/zones on fullscreen canvas |
| `GorgonSurveyWeb.CaptureController` | HTTP POST `/api/capture/:session_id` — receives screenshot, crops to zone, detects and places surveys |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place, zone drawing, route visualization |
| `OverlayCanvas` (JS Hook) | Fullscreen transparent canvas for overlay window — renders surveys, motherlode, routes, zones |
| `LogStreamer` (JS Hook) | Remote log ingestion over WebSocket for non-desktop deployments |

### Supervision Tree

```
Application Supervisor (one_for_one)
├── Telemetry
├── DNSCluster (conditional)
├── Phoenix.PubSub
├── Registry (SessionRegistry, keys: :unique)
├── SessionManager
├── SessionSupervisor (DynamicSupervisor)
│   └── LogWatcher (per session)
└── Endpoint (Bandit adapter)
```

### Routes

```
Browser:
  GET  /              → SurveyLive (main sidebar)
  GET  /overlay       → OverlayLive (transparent overlay)

API:
  POST /api/capture/:session_id  → CaptureController.create

Dev only:
  GET  /dev/dashboard → LiveDashboard
  GET  /dev/mailbox   → Swoosh mailbox
```

### Frontend

**ScreenCapture Hook (SurveyLive):**
- Screen capture via `getDisplayMedia` API, canvas overlay over mirrored video
- Click to place surveys/motherlode readings, right-click to toggle collected
- Click-to-mark inventory items in inventory zone
- Two-click rectangle selection for detect zone and inventory zone
- Auto-detect: scan_once triggered with 500ms delay when log detects new survey
- Optimized route visualization (nearest-neighbor TSP)
- Collected markers drawn at reduced opacity behind uncollected markers

**OverlayCanvas Hook (OverlayLive):**
- Fullscreen transparent canvas (100vw x 100vh, fixed position)
- Renders collected/uncollected surveys, routes, motherlode readings, zones
- Zone setting interactions (two-click rectangles)
- Workaround: briefly hides canvas on zone clear to force WebKitGTK repaint

**Shared Drawing (canvas_drawing.js):**
- Common utilities for both hooks: surveys, routes, zones, inventory markers, motherlode rendering

### SurveyDetector Image Processing

- **detect/1** — Red circle detection (R>150, G<80, B<80), proximity clustering, returns centroids as percentage coordinates
- **detect_player/1** — Player triangle detection (near-white clusters), returns smallest cluster centroid

### Tauri Desktop Integration (src-tauri/)

- Tauri v2.10, spawns Phoenix as sidecar binary with health-check polling
- Two windows: sidebar (380x700) + transparent overlay (fullscreen, click-through)
- Forces X11 backend on Linux (`GDK_BACKEND=x11`) — Wayland incompatible
- Global hotkeys: F12 toggles overlay interactivity, F11/custom triggers collection at cursor
- Commands: `capture_and_detect`, `create_overlay_window`, `toggle_overlay_interaction`, `set_overlay_geometry`, `refresh_overlay`, `set_collect_hotkey`
- On shutdown, gracefully stops BEAM VM via release stop command

### LogWatcher Modes

- **:local** — FileSystem watcher tails `ChatLog.txt` in configured log folder
- **:remote** — WebSocket ingestion via LogStreamer hook for non-local deployments
