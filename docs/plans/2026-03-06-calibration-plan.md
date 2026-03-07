# Calibration Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the manual scale/anchor system with a two-click calibration flow that computes px/m scale from a known survey offset.

**Architecture:** When a survey arrives and no calibration exists, the overlay enters a state machine: `waiting_for_survey` → `click_player` → `click_survey` → `calibrated`. Two clicks compute the scale as `pixel_distance / meter_distance`. Calibration (anchor + scale) is persisted in localStorage. The ControlPanel replaces the manual scale controls with a "Recalibrate" button.

**Tech Stack:** React (TypeScript), Tauri events, localStorage for cross-window communication

---

### Task 1: Update constants.ts

**Files:**
- Modify: `src/constants.ts`

**Step 1: Replace old constants with calibration key**

```typescript
export const CALIBRATION_KEY = 'gorgon-overlay-calibration';
```

This replaces `ANCHOR_KEY`, `SCALE_KEY`, and `DEFAULT_SCALE`. The calibration value stored will be `{ anchor: { x, y }, scale: number }`.

**Step 2: Commit**

```bash
git add src/constants.ts
git commit -m "refactor: replace anchor/scale constants with CALIBRATION_KEY"
```

---

### Task 2: Rewrite Overlay.tsx calibration state machine

**Files:**
- Modify: `src/pages/Overlay.tsx`

**Step 1: Replace state variables and imports**

Replace lines 7, 16, 64-71 (the old `ANCHOR_KEY`/`SCALE_KEY` imports, `Anchor` interface, and `anchor`/`scale` state) with:

```typescript
import { CALIBRATION_KEY } from '../constants';

// ... (keep ResizeDirection, Config, HANDLES, ResizeHandles, surveyToCanvas as-is)

interface Calibration { anchor: { x: number; y: number }; scale: number; }

type CalibrationStep = 'waiting_for_survey' | 'click_player' | 'click_survey' | 'calibrated';
```

Inside the `Overlay` component, replace the `anchor` and `scale` state with:

```typescript
const [calibration, setCalibration] = useState<Calibration | null>(() => {
  const saved = localStorage.getItem(CALIBRATION_KEY);
  return saved ? JSON.parse(saved) : null;
});
const [calStep, setCalStep] = useState<CalibrationStep>(() => {
  const saved = localStorage.getItem(CALIBRATION_KEY);
  return saved ? 'calibrated' : 'waiting_for_survey';
});
const [playerClick, setPlayerClick] = useState<{ x: number; y: number } | null>(null);
const [calibratingSurvey, setCalibratingSurvey] = useState<{ x: number; y: number } | null>(null);
```

**Step 2: Add effect to transition from `waiting_for_survey` to `click_player`**

When surveys arrive and we're in `waiting_for_survey`, pick the most recent uncollected survey and move to `click_player`:

```typescript
useEffect(() => {
  if (calStep !== 'waiting_for_survey') return;
  const uncollected = state.surveys.filter(s => !s.collected);
  if (uncollected.length > 0) {
    const latest = uncollected[uncollected.length - 1];
    setCalibratingSurvey({ x: latest.x, y: latest.y });
    setCalStep('click_player');
  }
}, [calStep, state.surveys]);
```

**Step 3: Replace `handleCanvasClick`**

Replace the old single-click handler with a calibration-aware handler:

```typescript
const handleCanvasClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
  const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
  const click = { x: e.clientX - rect.left, y: e.clientY - rect.top };

  if (calStep === 'click_player') {
    setPlayerClick(click);
    setCalStep('click_survey');
    return;
  }

  if (calStep === 'click_survey' && playerClick && calibratingSurvey) {
    const pixelDist = Math.hypot(click.x - playerClick.x, click.y - playerClick.y);
    const meterDist = Math.hypot(calibratingSurvey.x, calibratingSurvey.y);
    if (meterDist < 1) return; // avoid division by zero
    const scale = pixelDist / meterDist;
    const newCal: Calibration = { anchor: playerClick, scale };
    setCalibration(newCal);
    setCalStep('calibrated');
    localStorage.setItem(CALIBRATION_KEY, JSON.stringify(newCal));
    setPlayerClick(null);
    setCalibratingSurvey(null);
    return;
  }
}, [calStep, playerClick, calibratingSurvey]);
```

**Step 4: Update localStorage listener**

Replace lines 94-102 (the old `onStorage` effect that listened for `SCALE_KEY`/`ANCHOR_KEY`) with:

```typescript
useEffect(() => {
  const onStorage = (e: StorageEvent) => {
    if (e.key === CALIBRATION_KEY) {
      if (e.newValue) {
        setCalibration(JSON.parse(e.newValue));
        setCalStep('calibrated');
      } else {
        setCalibration(null);
        setCalStep('waiting_for_survey');
      }
    }
  };
  window.addEventListener('storage', onStorage);
  return () => window.removeEventListener('storage', onStorage);
}, []);
```

**Step 5: Update `handleContextMenu`**

Replace references to `anchor` and `scale` with `calibration.anchor` and `calibration.scale`:

```typescript
const handleContextMenu = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
  e.preventDefault();
  if (!calibration) return;
  const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
  const clickX = e.clientX - rect.left;
  const clickY = e.clientY - rect.top;
  const HIT_RADIUS = 15;
  let closest: { id: number; dist: number } | null = null;
  for (const survey of state.surveys) {
    if (survey.collected) continue;
    const [cx, cy] = surveyToCanvas(survey.x, survey.y, calibration.anchor, calibration.scale);
    const dist = Math.hypot(clickX - cx, clickY - cy);
    if (dist <= HIT_RADIUS && (!closest || dist < closest.dist)) {
      closest = { id: survey.id, dist };
    }
  }
  if (closest) {
    invoke('skip_survey', { id: closest.id }).catch(console.error);
  }
}, [calibration, state.surveys]);
```

**Step 6: Update the canvas drawing effect**

Replace the drawing `useEffect` (lines 132-225). The key changes:
- Replace `if (!anchor)` guard with calibration step prompts
- Replace all `anchor` / `scale` references with `calibration.anchor` / `calibration.scale`

```typescript
useEffect(() => {
  const canvas = canvasRef.current;
  if (!canvas || !config) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const W = canvas.width;
  const H = canvas.height;
  ctx.clearRect(0, 0, W, H);

  // Draw calibration prompts
  if (calStep !== 'calibrated' || !calibration) {
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.font = 'bold 14px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const messages: Record<string, string> = {
      waiting_for_survey: 'Waiting for survey data...',
      click_player: 'Click YOUR position on the map',
      click_survey: 'Now click the SURVEY location',
    };
    ctx.fillText(messages[calStep] ?? '', W / 2, H / 2);

    // Draw the player click marker during click_survey step
    if (calStep === 'click_survey' && playerClick) {
      ctx.beginPath();
      ctx.arc(playerClick.x, playerClick.y, 6, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,255,0,0.9)';
      ctx.fill();
      ctx.strokeStyle = '#000';
      ctx.lineWidth = 1;
      ctx.stroke();
    }
    return;
  }

  const { anchor, scale } = calibration;
  const { uncollected, waypoint, motherlode } = config.colors;

  // Route lines
  const ordered = state.surveys
    .filter(s => !s.collected && s.route_order !== null)
    .sort((a, b) => a.route_order! - b.route_order!);

  if (ordered.length > 1) {
    ctx.strokeStyle = waypoint;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    const [fx, fy] = surveyToCanvas(ordered[0].x, ordered[0].y, anchor, scale);
    ctx.moveTo(fx, fy);
    for (let i = 1; i < ordered.length; i++) {
      const [nx, ny] = surveyToCanvas(ordered[i].x, ordered[i].y, anchor, scale);
      ctx.lineTo(nx, ny);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // Survey dots
  for (const survey of state.surveys) {
    if (survey.collected) continue;
    const [cx, cy] = surveyToCanvas(survey.x, survey.y, anchor, scale);
    ctx.beginPath();
    ctx.arc(cx, cy, 9, 0, Math.PI * 2);
    ctx.fillStyle = uncollected;
    ctx.fill();
    if (survey.route_order !== null) {
      ctx.fillStyle = '#000';
      ctx.font = 'bold 10px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(survey.route_order), cx, cy);
    }
  }

  // Motherlode distance circles
  for (const [[px, py], dist] of state.motherlode_readings) {
    const [cx, cy] = surveyToCanvas(px, py, anchor, scale);
    const scaledR = dist * scale;
    ctx.beginPath();
    ctx.arc(cx, cy, scaledR, 0, Math.PI * 2);
    ctx.strokeStyle = motherlode + '88';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  // Triangulated motherlode location
  if (state.motherlode_location) {
    const [mx, my] = state.motherlode_location;
    const [cx, cy] = surveyToCanvas(mx, my, anchor, scale);
    ctx.beginPath();
    ctx.arc(cx, cy, 11, 0, Math.PI * 2);
    ctx.fillStyle = motherlode;
    ctx.fill();
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(cx - 6, cy - 6); ctx.lineTo(cx + 6, cy + 6);
    ctx.moveTo(cx + 6, cy - 6); ctx.lineTo(cx - 6, cy + 6);
    ctx.stroke();
  }

  // Anchor marker (player position)
  ctx.beginPath();
  ctx.arc(anchor.x, anchor.y, 5, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255,255,0,0.9)';
  ctx.fill();
  ctx.strokeStyle = '#000';
  ctx.lineWidth = 1;
  ctx.stroke();
}, [state, config, calibration, calStep, playerClick, size]);
```

**Step 7: Commit**

```bash
git add src/pages/Overlay.tsx
git commit -m "feat: replace anchor/scale with two-click calibration in overlay"
```

---

### Task 3: Update ControlPanel.tsx

**Files:**
- Modify: `src/pages/ControlPanel.tsx`

**Step 1: Replace scale/anchor controls with recalibrate button**

Remove:
- Import of `ANCHOR_KEY`, `SCALE_KEY`, `DEFAULT_SCALE` from constants (line 7)
- `scale` state (line 16)
- `applyScale` function (lines 27-32)
- `clearAnchor` function (lines 34-36)
- The scale/anchor controls `<div>` (lines 91-99)

Add:
- Import of `CALIBRATION_KEY` from constants
- A `recalibrate` function:

```typescript
const recalibrate = () => {
  localStorage.removeItem(CALIBRATION_KEY);
};
```

- A recalibrate button in place of the old scale controls:

```typescript
<div style={{ display: 'flex', gap: 4, alignItems: 'center', marginBottom: 8, fontSize: 12 }}>
  <button onClick={recalibrate} style={{ fontSize: 12, padding: '2px 8px' }}>Recalibrate Overlay</button>
</div>
```

**Step 2: Commit**

```bash
git add src/pages/ControlPanel.tsx
git commit -m "feat: replace manual scale controls with recalibrate button"
```

---

### Task 4: Verify build and test manually

**Step 1: Run TypeScript type check**

```bash
mise exec -- npx tsc --noEmit
```

Expected: No errors.

**Step 2: Run Rust tests (ensure no regressions)**

```bash
cd src-tauri && mise exec -- cargo test
```

Expected: All 21 tests pass (no Rust changes in this feature).

**Step 3: Commit any fixes if needed**

---

### Task 5: Final commit and cleanup

**Step 1: Verify no leftover references to old constants**

Search for `ANCHOR_KEY`, `SCALE_KEY`, `DEFAULT_SCALE` in `src/` — should only appear in `constants.ts` if at all (they should be removed).

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat: implement two-click calibration for overlay positioning"
```
