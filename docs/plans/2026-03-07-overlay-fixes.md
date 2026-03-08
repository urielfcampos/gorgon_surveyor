# Overlay Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 5 issues with the overlay windows: tag centering, text ghosting, right-click skip, click-through, and window titles.

**Architecture:** Each fix is independent. Issues span both `InventoryOverlay.tsx` and `Overlay.tsx` (frontend) and `tauri.conf.json` (config).

**Tech Stack:** React, Tauri 2.x, Canvas API, TypeScript

---

### Task 1: Fix inventory tag not centered in slot

The calibration captures `{x, y, w, h}` where `(x,y)` is the top-left of the first slot and `(w,h)` is the slot dimensions. Tags are drawn at `cal.x + col * cal.w + cal.w / 2` which centers within each slot. However, the calibration click captures the top-left of whichever slot the user clicks — if they click a slot that isn't slot 0, the offset is wrong.

The real issue: the calibration defines one slot's size and position. The tag center calculation is correct for slot (0,0) being at `(cal.x, cal.y)`. But the user may be clicking imprecisely, or the canvas coordinates may have an offset from the drag bar height (22px).

**Files:**
- Modify: `src/pages/InventoryOverlay.tsx`

**Step 1: Add a visual grid preview after calibration so centering can be verified**

After calibration completes, draw grid lines on the canvas so the user can see if slots align. This helps debug centering issues.

In the canvas rendering `useEffect` (line 135), after drawing tags, add a faint grid overlay:

```tsx
// Draw calibration grid preview (faint lines showing slot boundaries)
const maxCols = columns;
const maxRows = Math.ceil(active.length / columns) + 1;
ctx.strokeStyle = 'rgba(255, 255, 0, 0.15)';
ctx.lineWidth = 1;
for (let c = 0; c <= maxCols; c++) {
  const x = cal.x + c * cal.w;
  ctx.beginPath();
  ctx.moveTo(x, cal.y);
  ctx.lineTo(x, cal.y + maxRows * cal.h);
  ctx.stroke();
}
for (let r = 0; r <= maxRows; r++) {
  const y = cal.y + r * cal.h;
  ctx.beginPath();
  ctx.moveTo(cal.x, y);
  ctx.lineTo(cal.x + maxCols * cal.w, y);
  ctx.stroke();
}
```

**Step 2: Verify and test**

Run: `WEBKIT_DISABLE_DMABUF_RENDERER=1 mise exec -- npm run tauri dev`

Calibrate the inventory overlay by clicking top-left and bottom-right of a slot. The grid lines should align with the game's inventory grid. Tags should sit centered in cells.

**Step 3: Commit**

```bash
git add src/pages/InventoryOverlay.tsx
git commit -m "fix: add calibration grid preview for inventory overlay"
```

---

### Task 2: Fix text ghosting on transparent WebKitGTK windows

Both overlays already use the pattern of showing DOM elements for calibration text and only mounting the canvas when calibrated. The ghosting happens because WebKitGTK doesn't properly composite transparent windows — once text is painted, previous frames bleed through.

The current code already uses conditional rendering (canvas only when `calStep === 'calibrated'`). The issue is that the calibration instruction text is rendered as a `<div>` with `pointerEvents: 'none'` and a transparent background, but WebKitGTK still ghosts it.

**Fix:** Force the calibration text div to have an opaque background so there's no transparency compositing issue. Also ensure the click overlay div has a semi-transparent background to force a repaint.

**Files:**
- Modify: `src/pages/InventoryOverlay.tsx`
- Modify: `src/pages/Overlay.tsx`

**Step 1: Update calibration text styling in InventoryOverlay.tsx**

Change the calibration instruction div (around line 204) to have an opaque background:

```tsx
<div style={{
  position: 'absolute', top: '50%', left: '50%',
  transform: 'translate(-50%, -50%)',
  color: '#fff',
  font: 'bold 14px sans-serif',
  textAlign: 'center',
  pointerEvents: 'none',
  zIndex: 5,
  background: 'rgba(0, 0, 0, 0.75)',
  padding: '8px 16px',
  borderRadius: 6,
}}>
```

**Step 2: Apply same fix in Overlay.tsx**

Change the calibration instruction div (around line 291) to match:

```tsx
<div style={{
  position: 'absolute', top: '50%', left: '50%',
  transform: 'translate(-50%, -50%)',
  color: '#fff',
  font: 'bold 14px sans-serif',
  textAlign: 'center',
  pointerEvents: 'none',
  zIndex: 5,
  background: 'rgba(0, 0, 0, 0.75)',
  padding: '8px 16px',
  borderRadius: 6,
}}>
```

**Step 3: Verify text doesn't ghost**

Run the app, trigger recalibration on both overlays. Verify the instruction text appears cleanly without ghosting/overlapping.

**Step 4: Commit**

```bash
git add src/pages/InventoryOverlay.tsx src/pages/Overlay.tsx
git commit -m "fix: use opaque background on calibration text to prevent WebKitGTK ghosting"
```

---

### Task 3: Add right-click to skip/clear tags on inventory overlay

The map overlay (`Overlay.tsx`) already has `handleContextMenu` that finds the closest survey dot within `HIT_RADIUS` and calls `invoke('skip_survey', { id })`. The inventory overlay needs the same but mapped to grid positions.

**Files:**
- Modify: `src/pages/InventoryOverlay.tsx`

**Step 1: Disable passthrough when right-clicking is needed**

The inventory overlay currently enables passthrough (`set_ignore_cursor_events(true)`) when calibrated. This means right-clicks pass through to the game. We need to keep passthrough enabled but the canvas won't receive events.

This is a conflict: the user wants click-through (Task 4) AND right-click skip. These are mutually exclusive on the same window with `set_ignore_cursor_events`.

**Resolution:** Right-click skip on the inventory overlay is not feasible while click-through is enabled. Instead, surveys should be skipped from the control panel or map overlay. The inventory tags auto-update when surveys are marked collected/skipped.

**Alternative approach:** Add a keyboard shortcut or use the control panel's skip button. The inventory overlay tags already disappear when surveys are collected because the canvas re-renders from `state.surveys`.

Skip this task — the map overlay's right-click skip already works, and inventory tags update reactively. Document this as a known limitation.

**Step 2: Commit documentation note**

No code changes needed. The map overlay right-click skip handles this use case.

---

### Task 4: Enable click-through to game underneath overlay windows

Both overlays already toggle `set_ignore_cursor_events` based on calibration state:
- During calibration: passthrough disabled (clicks go to overlay for calibration)
- After calibration: passthrough enabled (clicks go to game)

This is already implemented in both `Overlay.tsx` (line 99) and `InventoryOverlay.tsx` (line 89). The `useEffect` calls `invoke('set_inventory_overlay_passthrough', { enabled: calStep === 'calibrated' })`.

However, the `Overlay.tsx` canvas has `pointerEvents: 'auto'` (line 325) which may interfere. When passthrough is enabled at the Tauri level, the web content shouldn't receive events anyway, but let's make sure.

**Files:**
- Modify: `src/pages/Overlay.tsx`
- Modify: `src/pages/InventoryOverlay.tsx`

**Step 1: Verify passthrough is working after calibration**

Run the app, calibrate both overlays, then try clicking on the game underneath. If clicks pass through, this is already working.

If clicks don't pass through, check the browser console for errors from `set_overlay_passthrough` / `set_inventory_overlay_passthrough`.

**Step 2: Ensure canvas pointerEvents don't interfere**

In `InventoryOverlay.tsx`, the canvas (line 232-237) doesn't have `pointerEvents` set explicitly. In `Overlay.tsx`, it has `pointerEvents: 'auto'` (line 325). Since Tauri-level passthrough overrides CSS pointer-events, this should be fine. But for clarity, remove the explicit `pointerEvents: 'auto'` from the map overlay canvas since passthrough handles it:

In `Overlay.tsx` line 325, change:
```tsx
style={{ display: 'block', pointerEvents: 'auto', cursor: 'default' }}
```
to:
```tsx
style={{ display: 'block' }}
```

Also remove `onContextMenu={handleContextMenu}` since right-click won't work through passthrough. Wait — the map overlay's right-click skip needs to work. This creates the same conflict as Task 3.

**Resolution:** The map overlay needs passthrough disabled to support right-click skip on survey dots. Keep `pointerEvents: 'auto'` on the map overlay canvas. The inventory overlay should have passthrough enabled (no right-click needed).

Actually, re-reading the Tauri code: `set_ignore_cursor_events(true)` makes the entire window click-through at the OS level. CSS `pointerEvents` is irrelevant when this is enabled. The right-click on the map overlay only works during calibration (when passthrough is off).

**The user wants click-through AND right-click skip.** These are fundamentally incompatible with `set_ignore_cursor_events`. We need a different approach for the map overlay.

**Approach:** Keep passthrough DISABLED on the map overlay (so right-click works), but set the container div to `pointerEvents: 'none'` so left-clicks fall through via CSS. Only the canvas captures right-clicks via `pointerEvents: 'auto'`. But on Linux/WebKitGTK, CSS pointer-events may not allow clicks to pass through to the underlying OS window — they'll just hit the transparent window background.

**Final resolution for map overlay:** Keep current behavior. The map overlay is positioned/sized over just the game map area, so it doesn't block the whole screen. Right-click skip is more valuable than click-through for the map overlay.

**For inventory overlay:** Enable passthrough after calibration (already implemented). No right-click needed since tags auto-update.

**Step 3: Confirm inventory overlay passthrough works**

Verify `InventoryOverlay.tsx` line 89 correctly enables passthrough after calibration. This should already work.

**Step 4: Commit**

No code changes needed if passthrough already works. If the canvas `pointerEvents` cleanup is desired:

```bash
git add src/pages/Overlay.tsx
git commit -m "fix: clarify pointer events behavior on overlay windows"
```

---

### Task 5: Add overlay name to window titles

**Files:**
- Modify: `src-tauri/tauri.conf.json`

**Step 1: Set meaningful window titles**

In `tauri.conf.json`, change the `title` fields:

- Line 26 (overlay): Change `""` to `"Survey Overlay"`
- Line 39 (inventory-overlay): Change `""` to `"Inventory Overlay"`

```json
{
  "label": "overlay",
  "title": "Survey Overlay",
  ...
},
{
  "label": "inventory-overlay",
  "title": "Inventory Overlay",
  ...
}
```

**Step 2: Verify titles appear**

Run the app. The window titles should appear in the taskbar/window switcher. Since `decorations: false`, the title bar won't show, but the title appears in OS window lists and taskbar tooltips.

Note: `skipTaskbar: true` means these won't appear in the taskbar. The title is still useful for window switchers (Alt+Tab) and system tools.

**Step 3: Commit**

```bash
git add src-tauri/tauri.conf.json
git commit -m "feat: add descriptive titles to overlay windows"
```
