# Calibration Redesign: Two-Point Scale Calibration

## Problem

The current single-point calibration computes scale from one survey click, making it sensitive to click imprecision. With short baselines, small click errors produce large scale errors, placing subsequent survey dots incorrectly.

## Solution

Require 2 survey points during calibration. The user clicks their player position (anchor) and the locations of 2 surveys on the game map. The system computes pixels-per-meter scale by averaging across both points, reducing error.

## Calibration Flow

1. Wait until at least 2 uncollected surveys exist
2. "Click YOUR position on the map" -> store as `anchor`
3. "Click where Survey #N is" (show survey number + offset) -> store `surveyClick1`
4. "Click where Survey #N is" (show second survey) -> store `surveyClick2`
5. Compute scale, save to localStorage, enter calibrated state

## Scale Computation

For each survey click `i`:
- `pixelDx_i = surveyClick_i.x - anchor.x`
- `pixelDy_i = anchor.y - surveyClick_i.y` (screen Y inverted)
- `meterDx_i = survey_i.x` (dx from log parser)
- `meterDy_i = survey_i.y` (dy from log parser)

Per-axis scale (skip if meter value near zero, abs < 1):
- `scaleX_i = pixelDx_i / meterDx_i`
- `scaleY_i = pixelDy_i / meterDy_i`

Final: average valid scaleX values, average valid scaleY values. If one axis has no valid measurements, fall back to the other axis value.

## Data Model

```ts
interface Calibration {
  anchor: { x: number; y: number };
  scaleX: number;
  scaleY: number;
}
```

Stored in localStorage under the existing `CALIBRATION_KEY`. Same structure as current — backward compatible.

## CalibrationStep States

```ts
type CalibrationStep =
  | "waiting_for_surveys"  // need >= 2 surveys
  | "click_player"
  | "click_survey_1"
  | "click_survey_2"
  | "calibrated"
```

## Rendering (unchanged)

```
canvasX = anchor.x + survey.x * scaleX
canvasY = anchor.y - survey.y * scaleY
```

## Changes

- `Overlay.tsx`: New calibration steps, 2-point scale computation, UI showing which survey to click
- No backend changes needed
- No changes to data flow or state management
