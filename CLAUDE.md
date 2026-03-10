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
```

## Architecture

Phoenix LiveView game companion for Project Gorgon. Single page at `/`, no database. Multi-session: each browser tab gets its own isolated session with independent LogWatcher and state.

### Data Flow

```
chat.log → FileSystem watcher → LogWatcher GenServer (per session) → LogParser (regex)
  → AppState (pure struct) → PubSub ("game_state:#{session_id}")
  → SurveyLive LiveView → push_event → ScreenCapture JS Hook → canvas
```

### Key Modules

| Module | Responsibility |
|---|---|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into structured events |
| `GorgonSurvey.AppState` | Pure state struct — survey/motherlode management, no side effects |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file via FileSystem, maintains AppState, broadcasts via scoped PubSub |
| `GorgonSurvey.SessionManager` | Tracks active sessions, manages per-session LogWatcher lifecycle, config overrides, 30s cleanup timers |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json`, session-aware get/put |
| `GorgonSurvey.SurveyDetector` | Image processing via Vix/VIPS — red circle detection |
| `GorgonSurveyWeb.SurveyLive` | LiveView page — sidebar + screen capture, auto-detect, zone setup, per-session state |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place, frame capture, route visualization |

### Supervision Tree

```
Application Supervisor (one_for_one)
├── Telemetry
├── DNSCluster (conditional)
├── Phoenix.PubSub
├── Registry (SessionRegistry)
├── SessionManager
├── SessionSupervisor (DynamicSupervisor)
│   └── LogWatcher (per session)
└── Endpoint
```

### Frontend

- Screen capture via `getDisplayMedia` API
- Canvas overlay for survey markers drawn over mirrored video
- Click to place surveys, right-click to toggle collected
- Click-to-mark inventory items in inventory zone
- Auto-detect on survey: scan_once triggered with 500ms delay when log detects new survey
- Detection zone / inventory zone: two-click rectangle selection for targeted scanning
- Optimized route visualization (nearest-neighbor TSP)
- Collected markers drawn at reduced opacity behind uncollected markers
- State pushed from server via LiveView `push_event`

### SurveyDetector Image Processing

- **detect/1** — Red circle detection (R>150, G<80, B<80), clustering, returns centroids as percentages
- Accepts PNG binary, returns percentage-based coordinates
