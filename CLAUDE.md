# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tool Management

All commands must be prefixed with `mise exec --`. Tools (Rust, Node, tauri-cli) are managed via `.mise.toml` — run `mise trust && mise install` once to set up the environment.

## Commands

```bash
# Install npm dependencies
mise exec -- npm install

# Dev server (hot-reload frontend + Rust rebuild on change)
mise exec -- npm run tauri dev

# On Wayland (if WebKit crashes with protocol errors)
GDK_BACKEND=x11 mise exec -- npm run tauri dev

# Production build
mise exec -- npm run tauri build

# Rust unit tests (all)
cd src-tauri && mise exec -- cargo test

# Rust unit tests (single module)
cd src-tauri && mise exec -- cargo test log_parser

# TypeScript type check + frontend build
mise exec -- npx vite build
```

## Architecture

This is a Tauri 2.x desktop app with two windows that serve different routes of the same React SPA:

- **`control-panel`** (`index.html` → route `/`): User-facing panel for zone selection, survey list, motherlode readings, settings.
- **`overlay`** (`index.html#/overlay` → route `/overlay`): Transparent, always-on-top, click-through canvas window positioned over the game map.

The overlay is made click-through in `lib.rs` setup via `overlay.set_ignore_cursor_events(true)`.

### Data Flow

```
Game chat.log → notify watcher → log_parser → AppState mutation → "state-updated" Tauri event → React re-render
```

1. `log_watcher::start_watching` opens the file, seeks to end, and uses the `notify` crate to watch for `Modify` events.
2. New lines are parsed by `log_parser::parse_line` into `LogEvent` variants.
3. `handle_log_event` updates `AppState` (held in `Arc<Mutex<AppState>>`).
4. After every mutation, the backend emits the `"state-updated"` event with the full state payload.
5. The `useSurveyState` hook (`src/hooks/useSurveyState.ts`) subscribes to this event and calls `get_state` on mount.

### Rust Backend (`src-tauri/src/`)

| Module | Responsibility |
|---|---|
| `state.rs` | `AppState`: surveys, motherlode readings/location, player position; `recalculate_route` calls `optimize_path` |
| `commands.rs` | All Tauri IPC commands; type aliases `SharedState`, `SharedConfig`, `WatcherRunning` |
| `log_parser.rs` | Regex parsing; `SurveyOffset {dx, dy}` and `MotherlodeDistance {meters}` from chat messages |
| `log_watcher.rs` | File tail using `notify`; calls `handle_log_event` on new lines |
| `path_optimizer.rs` | Nearest-neighbor TSP returning index order |
| `triangulator.rs` | Circle-circle intersection for motherlode triangulation (requires 3 readings) |
| `zones.rs` | `ZONES` constant with 6 zone name → bounding box mappings |
| `config.rs` | TOML config at `~/.config/gorgon-survey/settings.toml` via `dirs` crate |

`WatcherRunning` (`Arc<AtomicBool>`) guards against starting duplicate watcher threads — checked in `start_log_watching` and set during auto-start in `lib.rs`.

### Log Parser

Game message formats:
- **Survey**: `"The Good Metal Slab is 815m west and 1441m north."` → `SurveyOffset { dx, dy }` (directional offset from player to resource)
- **Motherlode**: `"The treasure is 1000 meters away"` → `MotherlodeDistance { meters }` (raw distance only)
- **Collected**: `"You collected the survey reward"` → `SurveyCollected`

Motherlode regex is checked first in `parse_line` to prevent the survey pattern from matching it. After changing patterns, run `cd src-tauri && mise exec -- cargo test log_parser`.

### Frontend (`src/`)

- Entry point is `src/main.tsx` (not `App.tsx`, which is unused scaffold).
- `HashRouter` routes: `/` → `ControlPanel`, `/overlay` → `Overlay`.
- `Overlay.tsx` renders a `<canvas>` with survey dots, route lines, and motherlode circles. Game-to-canvas coordinate mapping uses `ZONE_BOUNDS` (hardcoded in `Overlay.tsx`).

## Known Limitations

- **`player_position` is never set from logs** — the game message format for player coordinates is unknown. Both `SurveyOffset` auto-detection and `MotherlodeDistance` auto-detection depend on this being populated. Manual entry in `MotherlodePanel` is the current workaround.
- **Zone bounds are placeholder** — all 6 zones use `(-2048, -2048, 2048, 2048)`. These must be measured in-game. **When updating, both `src-tauri/src/zones.rs` AND `src/pages/Overlay.tsx` (`ZONE_BOUNDS`) must be kept in sync.**
- **Watcher cannot be restarted** — changing the log path requires restarting the app; `WatcherRunning` never resets to `false`.
