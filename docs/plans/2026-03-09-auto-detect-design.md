# Auto-Detect Survey Markers Design

## Goal

Automatically detect red circle survey markers on the game map by periodically scanning the screen capture video frames, and place them on the overlay without manual clicking.

## Architecture

The JS hook periodically captures a frame from the video as a PNG, sends it to the server via `pushEvent`. The server uses the `image` hex package to detect red circles (color filter + clustering), converts pixel coordinates to percentage positions, then matches detected circles to unplaced surveys in order and places them automatically. A toggle in the sidebar enables/disables the scanning loop.

## Data Flow

```
JS: video frame → canvas.toDataURL("image/png") → pushEvent("scan_frame", base64)
    ↓
Server: decode PNG → Image color filter (R>150, G<80, B<80) → cluster red pixels → circle centers
    ↓
Server: sort circles (left-to-right, top-to-bottom) → match to unplaced surveys in order → place_survey for each
    ↓
Server: broadcast state_updated → JS redraws markers
```

## Components

- **JS hook** — `setInterval` (3s) for frame capture when auto-detect is on. Listens for `start_auto_detect` / `stop_auto_detect` push events. Sends frame as base64 PNG via `pushEvent("scan_frame")`.
- **LiveView** — `auto_detect` assign (boolean). Handles `toggle_auto_detect` and `scan_frame` events. Detection runs synchronously in the event handler.
- **SurveyDetector module** — Takes PNG binary, returns list of `{x_pct, y_pct}` circle centers. Uses `Image` for color filtering, clustering, centroid calculation.
- **Template** — "Auto Detect" toggle button in sidebar.
- **Dependencies** — `image` hex package.

## Decisions

- **Detection in server, not client** — Uses `image` (libvips) for fast NIF-based image processing.
- **Periodic scanning (3s interval)** — Runs while toggle is on, not continuously.
- **Match by order** — Detected circles assigned to unplaced surveys in list order.
- **No new GenServer** — Detection is fast enough to run in the LiveView process.
