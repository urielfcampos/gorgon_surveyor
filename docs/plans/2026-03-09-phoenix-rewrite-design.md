# Gorgon Survey — Phoenix LiveView Rewrite

## Overview

Companion web app for Project Gorgon that mirrors the game screen via browser screen capture and overlays survey/motherlode markers on top. Built with Elixir, Phoenix Framework, and LiveView. Runs locally on the same machine as the game.

## Architecture

Three main components:

1. **LogWatcher GenServer** — tails the game's `chat.log`, parses events, maintains app state, broadcasts via PubSub.
2. **LiveView UI** — single page with video mirror, canvas overlay, and sidebar controls.
3. **JS Hook** — handles screen capture, canvas rendering, click-to-place interactions. Communicates with LiveView via `pushEvent`/`handleEvent`.

### Data Flow

```
chat.log → LogWatcher GenServer → PubSub → LiveView process → JS Hook → canvas render
```

## LogWatcher GenServer

- Finds the latest log file in the configured folder on startup.
- Seeks to end of file, watches for modifications using `:fs` or periodic polling.
- Parses new lines into events:
  - **Survey**: `"The Good Metal Slab is 815m west and 1441m north."` → `{dx, dy}` offset
  - **Motherlode**: `"The treasure is 1000 meters away"` → distance
  - **Collected**: `"You collected the survey reward"` → event
- Maintains app state (surveys, motherlode, zone, route) in process state.
- Broadcasts updates via `Phoenix.PubSub`.

## Frontend — Screen Capture + Canvas Overlay

### Screen Capture

- User clicks "Share Screen", browser prompts `getDisplayMedia`.
- Video stream feeds into a `<video>` element sized to fit the main area.
- Purely visual mirror — no frame analysis.

### Canvas Overlay (LiveView JS Hook)

- `<canvas>` absolutely positioned over `<video>`, same dimensions.
- Draws: survey markers (numbered dots), route lines, motherlode triangulation circles.
- User clicks canvas to place a survey marker → `pushEvent("place_survey", {x, y})` to LiveView.
- LiveView stores placement, pushes state back, hook redraws.

### Placement Flow

1. New survey arrives from LogWatcher → LiveView pushes "place this survey" prompt.
2. User clicks on the mirrored game map in the video feed.
3. Click coordinates stored as percentages of canvas dimensions (stable across resizes).
4. Canvas redraws with the new marker.

## State & Data Model

No database. State lives in the LogWatcher GenServer process. Surveys are transient.

### Survey

- `id` — auto-increment
- `survey_number` — display order
- `dx, dy` — directional offset from log parser
- `x_pct, y_pct` — placement on canvas (nil until placed)
- `collected` — boolean, toggled manually

### Motherlode

- `readings` — list of `{x_pct, y_pct, distance_meters}`
- `estimated_location` — triangulated from 3+ readings (nil until enough data)

### AppState

- `surveys` — list of active surveys
- `motherlode` — motherlode data
- `zone` — currently selected zone
- `log_folder` — path to game logs
- `route_order` — optimized visit order (nearest-neighbor TSP)

## UI Layout

Single LiveView page at `/` with sidebar + main area.

### Main Area

- "Share Screen" button (before capture).
- Video + canvas overlay (after capture).

### Sidebar

- Zone selector dropdown.
- Survey list (numbered, click to highlight, right-click to mark collected).
- Motherlode panel (readings, player position entry, triangulation result).
- Settings (log folder path, start/stop watcher).

## Deployment

Local only. `mix phx.server` on the gaming machine, access via `localhost:4000`.

## Future Enhancements (Not In Scope)

- OCR-based detection from video frames.
- Automatic player position detection.
- Remote server deployment.
