# Inventory Overlay Design

## Summary

A third Tauri window that overlays numbered tags on inventory slots so the user can identify which survey item corresponds to which survey number.

## New Window

- `inventory-overlay` — transparent, always-on-top, click-through, no decorations
- Route: `/inventory-overlay` in the existing React SPA
- Same drag bar + resize handles pattern as the map overlay

## Calibration (two-click)

- Click 1: top-left corner of any inventory slot
- Click 2: bottom-right corner of that same slot
- Derives `slotWidth` and `slotHeight` from the two clicks
- Stored in `localStorage`

## Configuration (control panel)

- **Columns**: number input, default `11`
- **Starting slot**: number input (1-based), default `1`
- Both stored in `localStorage`, synced to overlay via `StorageEvent`

## Tag Rendering

- Active (uncollected) surveys sorted by `survey_number` fill consecutive slots starting from the configured slot
- Each tag renders the `survey_number` centered in its grid cell
- When a survey is collected/skipped, remaining tags shift to fill the gap

## Backend

- No Rust state changes needed — overlay reads from existing `AppState` via `useSurveyState`
- Toggle visibility via a new `toggle_inventory_overlay_visible` command

## Files touched

- `tauri.conf.json` — add third window definition
- `src/main.tsx` — add `/inventory-overlay` route
- `src/pages/InventoryOverlay.tsx` — new page (calibration + grid rendering)
- `src/pages/ControlPanel.tsx` — add inventory config section
- `src-tauri/src/lib.rs` — set click-through on new window
- `src-tauri/src/commands.rs` — add `toggle_inventory_overlay_visible`
