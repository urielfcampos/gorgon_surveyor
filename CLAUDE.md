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

Phoenix LiveView game companion for Project Gorgon. Single page at `/`, no database.

### Data Flow

```
chat.log → FileSystem watcher → LogWatcher GenServer → LogParser (regex)
  → AppState (pure struct) → PubSub ("game_state")
  → SurveyLive LiveView → push_event → ScreenCapture JS Hook → canvas
```

### Key Modules

| Module | Responsibility |
|---|---|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into structured events |
| `GorgonSurvey.AppState` | Pure state struct — survey/motherlode management, no side effects |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file via FileSystem, maintains AppState, broadcasts via PubSub |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json` |
| `GorgonSurvey.SurveyDetector` | Image processing via Vix/VIPS — red circle detection, player triangle detection, inventory frame detection |
| `GorgonSurveyWeb.SurveyLive` | LiveView page — sidebar + screen capture, auto-detect, zone setup, player tracking |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place, frame capture, route visualization |

### Supervision Tree

```
Application Supervisor (one_for_one)
├── Telemetry
├── DNSCluster (conditional)
├── Phoenix.PubSub
├── LogWatcher (conditional — only if log_folder configured)
└── Endpoint
```

### Frontend

- Screen capture via `getDisplayMedia` API
- Canvas overlay for survey markers drawn over mirrored video
- Click to place surveys, right-click to toggle collected
- Auto-detect mode: periodic frame capture (3s interval) sent to server for image analysis
- Detection zone / inventory zone: two-click rectangle selection for targeted scanning
- Player position marker rendering
- Optimized route visualization (nearest-neighbor TSP)
- State pushed from server via LiveView `push_event`

### SurveyDetector Image Processing

- **detect/1** — Red circle detection (R>150, G<80, B<80), clustering, returns centroids as percentages
- **detect_player/1** — Near-white player triangle detection, returns smallest bright cluster
- **detect_inventory/1** — Gold/brown inventory frame detection, returns sorted grid positions
- All functions accept PNG binary, return percentage-based coordinates
