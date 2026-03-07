# Calibration Feature Design

## Problem

The overlay currently uses a manually entered scale (px/m) to position survey dots. This is a guess — there's no way to derive the correct value without trial and error.

## Solution

A two-click calibration flow that computes the correct scale from a known survey offset.

## Calibration Flow

1. App starts uncalibrated → overlay shows "Waiting for survey data..."
2. First `SurveyOffset` arrives → overlay enters calibration mode: "Click your position on the map"
3. User clicks point A (their position) → "Now click the survey location"
4. User clicks point B (survey location visible on game map beneath overlay)
5. System computes scale, stores calibration, exits calibration mode
6. All surveys render using computed scale. "Recalibrate" button in ControlPanel re-enters calibration mode.

## Scale Computation

```
pixel_dist = sqrt((px2 - px1)^2 + (py2 - py1)^2)
meter_dist = sqrt(survey.x^2 + survey.y^2)
scale = pixel_dist / meter_dist
anchor = point A (player pixel position)
```

The `surveyToCanvas` formula stays: `(anchor.x + gx * scale, anchor.y - gy * scale)`.

Survey `(x, y)` equals the raw meter offset because `player_position` is always `(0, 0)` today.

## Changes

### Overlay.tsx
- Replace single-click anchor with two-click calibration state machine: `idle` → `waiting_for_survey` → `click_player` → `click_survey` → `calibrated`
- Store calibration (anchor + scale) in localStorage under `CALIBRATION_KEY`
- Remove `SCALE_KEY` and `ANCHOR_KEY` usage
- Show prompt text during calibration steps

### ControlPanel.tsx
- Remove manual scale input, "Set" button, "Reset pos" button
- Add "Recalibrate" button that signals overlay to re-enter calibration mode (via localStorage event)

### constants.ts
- Replace `ANCHOR_KEY`, `SCALE_KEY`, `DEFAULT_SCALE` with `CALIBRATION_KEY`

### Backend (Rust)
- No changes needed. Survey offset data already flows via `state-updated` events.

## Assumptions

- `player_position` remains `(0, 0)`, so survey `(x, y)` equals the raw meter offset
- The overlay is positioned over the in-game map, so users can visually identify both their position and the survey location
