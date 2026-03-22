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

## Desktop App (Tauri)

The project includes a Tauri v2 desktop wrapper that runs the Phoenix server as a sidecar process. It provides two windows: a sidebar control panel and a transparent click-through overlay. Requires X11 (Wayland does not support the overlay features).

### Additional Prerequisites

- [Rust](https://rustup.rs/) -- needed for Tauri and target-triple detection
- Tauri v2 system dependencies (on Arch: `webkit2gtk-4.1`, `libappindicator-gtk3`, etc. -- see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/))

### Development

```bash
# Install JS dependencies (first time)
npm install

# Run in dev mode (starts Phoenix + Tauri with hot-reload)
npx tauri dev
```

### Production Build

```bash
# 1. Build the Phoenix release sidecar
./scripts/build-desktop.sh

# 2. Build the Tauri desktop app
npm run tauri build
```

The build script compiles a Mix release named `desktop`, then creates a wrapper script at `src-tauri/binaries/phoenix-server-<target-triple>` that Tauri bundles as a sidecar. The Phoenix server runs on port 4840 in desktop mode.

If you change templates or assets, do a clean rebuild:

```bash
rm -rf _build/prod && ./scripts/build-desktop.sh
```

## Architecture

### Data Flow

```
chat.log --> FileSystem watcher --> LogWatcher GenServer --> LogParser (regex)
  --> AppState.Server --> AppState (pure struct)
  --> PubSub ("game_state") --> SurveyLive / OverlayLive
  --> push_event --> JS Hooks --> canvas
```

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into structured events |
| `GorgonSurvey.AppState` | Pure state struct and functions for survey/motherlode management |
| `GorgonSurvey.AppState.Server` | GenServer wrapping AppState — holds state, handles mutations, broadcasts via PubSub |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file via FileSystem, forwards parsed events to AppState.Server |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json` |
| `GorgonSurvey.SurveyDetector` | Image processing via Vix/libvips -- red circle detection |
| `GorgonSurveyWeb.SurveyLive` | LiveView page -- sidebar controls, screen capture, per-session state |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place, frame capture, route visualization |

### Supervision Tree

```
Application Supervisor (one_for_one)
+-- Telemetry
+-- DNSCluster (conditional)
+-- Phoenix.PubSub
+-- AppState.Server
+-- WatcherSupervisor (DynamicSupervisor)
|   +-- LogWatcher
+-- Endpoint
```

## License

Private project.
