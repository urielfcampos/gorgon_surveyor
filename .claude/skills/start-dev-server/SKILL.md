---
name: start-dev-server
description: Use when the user asks to start, run, or launch the gorgon-survey app, or when you need to test changes by running the dev server.
---

# Start Dev Server

Start the Tauri dev server as a background task so you can continue working while the app runs.

## Command

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 mise exec -- npm run tauri dev
```

## Usage

Run via Bash with `run_in_background: true`. This returns a task ID you can use to check output later.

The `WEBKIT_DISABLE_DMABUF_RENDERER=1` env var is required on Wayland/Linux to prevent GBM buffer errors.

## Checking Output

Use `TaskOutput` with the task ID to read logs. Look for:
- `Finished dev profile` — Rust compiled successfully
- `VITE ready` — frontend is up
- `error[E...]` — Rust compilation failure
- `error TS...` — TypeScript error
