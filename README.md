# Gorgon Survey

A Phoenix LiveView game companion for [Project Gorgon](https://projectgorgon.com/) that tracks survey and motherlode locations by capturing your game screen and parsing chat logs in real time.

## Features

- **Screen capture overlay** -- mirrors your game via the browser `getDisplayMedia` API with a canvas overlay for marking locations
- **Chat log parsing** -- watches Project Gorgon's `chat.log` for survey/motherlode detection events in real time
- **Click-to-mark** -- left-click the overlay to place survey markers; right-click to toggle collected status
- **Auto-detect mode** -- periodically captures frames and uses image processing (Vix/libvips) to detect red survey circles, player position, and inventory state
- **Detection zones** -- two-click rectangle selection to target scanning areas
- **Route visualization** -- optimized nearest-neighbor path through uncollected surveys
- **Player position tracking** -- detects and displays player triangle marker
- **Persistent config** -- settings saved to `~/.config/gorgon-survey/settings.json`

## Tech Stack

- **Elixir** / **Phoenix** / **LiveView** -- server and real-time UI
- **Vix (libvips)** via the `image` hex package -- image processing for survey detection
- **file_system** -- native filesystem watcher for chat log tailing
- **Tailwind CSS** -- styling
- **esbuild** -- JS bundling
- **No database** -- all state is in-memory (GenServer) or persisted as JSON config files; Ecto is not used

## Prerequisites

- [mise](https://mise.jdx.dev/) -- manages tool versions via `.mise.toml`

The `.mise.toml` specifies:

| Tool   | Version          |
|--------|------------------|
| Elixir | 1.20.0-rc.3-otp-28 |
| Erlang | 28.4             |
| Node   | 24.6.0           |

You also need **libvips** installed on your system (used by the `image` / Vix dependency for survey detection).

## Setup

```bash
# Install tool versions
mise install

# Install dependencies and build assets
mise exec -- mix setup

# Start the dev server (visit http://localhost:4000)
mise exec -- mix phx.server

# Or start with an interactive console
mise exec -- iex -S mix phx.server
```

## Running Tests

```bash
# Run all tests
mise exec -- mix test

# Run a specific test file
mise exec -- mix test test/gorgon_survey/log_parser_test.exs

# Compile check (warnings as errors)
mise exec -- mix compile --warnings-as-errors

# Pre-commit (compile check + unlock unused deps + format + test)
mise exec -- mix precommit
```

## Architecture

### Data Flow

```
chat.log --> FileSystem watcher --> LogWatcher GenServer --> LogParser (regex)
  --> AppState (pure struct) --> PubSub ("game_state")
  --> SurveyLive LiveView --> push_event --> ScreenCapture JS Hook --> canvas
```

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into structured events |
| `GorgonSurvey.AppState` | Pure state struct for survey/motherlode management (no side effects) |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file via FileSystem, maintains AppState, broadcasts via PubSub |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json` |
| `GorgonSurvey.SurveyDetector` | Image processing via Vix/libvips -- red circle detection, player triangle detection, inventory frame detection |
| `GorgonSurveyWeb.SurveyLive` | LiveView page -- sidebar controls, screen capture, auto-detect, zone setup |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place, frame capture, route visualization |

### Supervision Tree

```
Application Supervisor (one_for_one)
+-- Telemetry
+-- DNSCluster (conditional)
+-- Phoenix.PubSub
+-- LogWatcher (conditional -- only starts if log_folder is configured)
+-- Endpoint
```

## License

Private project.
