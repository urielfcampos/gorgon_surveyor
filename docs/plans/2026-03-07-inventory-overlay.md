# Inventory Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a third Tauri window that overlays numbered survey tags on inventory grid slots.

**Architecture:** New `inventory-overlay` window (transparent, always-on-top, click-through) renders a canvas with numbered tags positioned on a calibrated grid. Two-click calibration derives slot size. Config (columns, starting slot) stored in localStorage and synced cross-window. Active surveys fill consecutive slots; collected surveys shift remaining tags.

**Tech Stack:** Tauri 2.x window config, React canvas rendering, localStorage for calibration/config sync.

---

### Task 1: Add inventory-overlay window to Tauri config

**Files:**
- Modify: `src-tauri/tauri.conf.json:13-37`
- Modify: `src-tauri/src/lib.rs:34-36`

**Step 1: Add window definition to tauri.conf.json**

Add after the existing `overlay` window entry (after line 36, before the closing `]`):

```json
,
{
  "label": "inventory-overlay",
  "title": "",
  "width": 600,
  "height": 400,
  "x": 200,
  "y": 200,
  "decorations": false,
  "transparent": true,
  "alwaysOnTop": true,
  "skipTaskbar": true,
  "resizable": true,
  "url": "index.html#/inventory-overlay"
}
```

**Step 2: Set click-through on the new window in lib.rs**

In `lib.rs` setup closure, after the existing overlay click-through block (line 36), add:

```rust
if let Some(inv_overlay) = app.get_webview_window("inventory-overlay") {
    inv_overlay.set_ignore_cursor_events(true).ok();
}
```

**Step 3: Verify it compiles**

Run: `cd src-tauri && mise exec -- cargo check`
Expected: compiles with no errors

**Step 4: Commit**

```bash
git add src-tauri/tauri.conf.json src-tauri/src/lib.rs
git commit -m "feat: add inventory-overlay window to Tauri config"
```

---

### Task 2: Add toggle command for inventory overlay

**Files:**
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs:57-70`

**Step 1: Add toggle_inventory_overlay_visible command**

In `commands.rs`, after the existing `toggle_overlay_visible` function (after line 100), add:

```rust
#[tauri::command]
pub fn toggle_inventory_overlay_visible(app: tauri::AppHandle) -> Result<bool, String> {
    if let Some(window) = app.get_webview_window("inventory-overlay") {
        let visible = window.is_visible().map_err(|e| e.to_string())?;
        if visible {
            window.hide().map_err(|e| e.to_string())?;
        } else {
            window.show().map_err(|e| e.to_string())?;
        }
        Ok(!visible)
    } else {
        Err("Inventory overlay window not found".to_string())
    }
}
```

**Step 2: Register the command in lib.rs**

Add `commands::toggle_inventory_overlay_visible,` to the `invoke_handler` list.

**Step 3: Verify it compiles**

Run: `cd src-tauri && mise exec -- cargo check`
Expected: compiles with no errors

**Step 4: Commit**

```bash
git add src-tauri/src/commands.rs src-tauri/src/lib.rs
git commit -m "feat: add toggle command for inventory overlay visibility"
```

---

### Task 3: Add route and InventoryOverlay page scaffold

**Files:**
- Modify: `src/main.tsx:1-17`
- Create: `src/pages/InventoryOverlay.tsx`

**Step 1: Create the InventoryOverlay page**

Create `src/pages/InventoryOverlay.tsx`:

```tsx
import { useCallback, useEffect, useRef, useState } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { useSurveyState } from '../hooks/useSurveyState';

type ResizeDirection = 'East' | 'North' | 'NorthEast' | 'NorthWest' | 'South' | 'SouthEast' | 'SouthWest' | 'West';

const INV_CAL_KEY = 'gorgon-inv-calibration';
const INV_COLUMNS_KEY = 'gorgon-inv-columns';
const INV_START_SLOT_KEY = 'gorgon-inv-start-slot';

interface SlotCal { x: number; y: number; w: number; h: number; }
type CalStep = 'click_top_left' | 'click_bottom_right' | 'calibrated';

const HANDLES: { dir: ResizeDirection; style: React.CSSProperties }[] = [
  { dir: 'NorthWest', style: { top: -4,    left: -4,    cursor: 'nw-resize' } },
  { dir: 'North',     style: { top: -4,    left: '50%', transform: 'translateX(-50%)', cursor: 'n-resize' } },
  { dir: 'NorthEast', style: { top: -4,    right: -4,   cursor: 'ne-resize' } },
  { dir: 'East',      style: { top: '50%', right: -4,   transform: 'translateY(-50%)', cursor: 'e-resize' } },
  { dir: 'SouthEast', style: { bottom: -4, right: -4,   cursor: 'se-resize' } },
  { dir: 'South',     style: { bottom: -4, left: '50%', transform: 'translateX(-50%)', cursor: 's-resize' } },
  { dir: 'SouthWest', style: { bottom: -4, left: -4,    cursor: 'sw-resize' } },
  { dir: 'West',      style: { top: '50%', left: -4,    transform: 'translateY(-50%)', cursor: 'w-resize' } },
];

function ResizeHandles() {
  const onMouseDown = (dir: ResizeDirection) => (e: React.MouseEvent) => {
    e.preventDefault();
    getCurrentWindow().startResizeDragging(dir).catch(console.error);
  };
  return (
    <>
      {HANDLES.map(({ dir, style }) => (
        <div
          key={dir}
          onMouseDown={onMouseDown(dir)}
          style={{
            position: 'absolute',
            width: 10, height: 10,
            background: 'rgba(255, 220, 0, 0.7)',
            border: '1px solid rgba(0,0,0,0.4)',
            borderRadius: 2,
            pointerEvents: 'auto',
            zIndex: 20,
            ...style,
          }}
        />
      ))}
    </>
  );
}

export default function InventoryOverlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [cal, setCal] = useState<SlotCal | null>(() => {
    const saved = localStorage.getItem(INV_CAL_KEY);
    return saved ? JSON.parse(saved) : null;
  });
  const [calStep, setCalStep] = useState<CalStep>(() => {
    return localStorage.getItem(INV_CAL_KEY) ? 'calibrated' : 'click_top_left';
  });
  const [topLeft, setTopLeft] = useState<{ x: number; y: number } | null>(null);
  const [columns, setColumns] = useState<number>(() => {
    const saved = localStorage.getItem(INV_COLUMNS_KEY);
    return saved ? parseInt(saved, 10) : 11;
  });
  const [startSlot, setStartSlot] = useState<number>(() => {
    const saved = localStorage.getItem(INV_START_SLOT_KEY);
    return saved ? parseInt(saved, 10) : 1;
  });
  const [size, setSize] = useState({ w: window.innerWidth, h: window.innerHeight });

  useEffect(() => {
    document.documentElement.style.background = 'transparent';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.background = 'transparent';
    document.body.style.overflow = 'hidden';
  }, []);

  useEffect(() => {
    const onResize = () => setSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  // Sync config from ControlPanel via localStorage
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === INV_CAL_KEY) {
        if (e.newValue) {
          setCal(JSON.parse(e.newValue));
          setCalStep('calibrated');
        } else {
          setCal(null);
          setCalStep('click_top_left');
        }
      }
      if (e.key === INV_COLUMNS_KEY && e.newValue) setColumns(parseInt(e.newValue, 10));
      if (e.key === INV_START_SLOT_KEY && e.newValue) setStartSlot(parseInt(e.newValue, 10));
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const handleCanvasClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
    const click = { x: e.clientX - rect.left, y: e.clientY - rect.top };

    if (calStep === 'click_top_left') {
      setTopLeft(click);
      setCalStep('click_bottom_right');
      return;
    }

    if (calStep === 'click_bottom_right' && topLeft) {
      const w = Math.abs(click.x - topLeft.x);
      const h = Math.abs(click.y - topLeft.y);
      if (w < 5 || h < 5) return; // too small, ignore
      const newCal: SlotCal = { x: topLeft.x, y: topLeft.y, w, h };
      setCal(newCal);
      setCalStep('calibrated');
      localStorage.setItem(INV_CAL_KEY, JSON.stringify(newCal));
      setTopLeft(null);
      return;
    }
  }, [calStep, topLeft]);

  // Canvas rendering
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    if (calStep !== 'calibrated' || !cal) {
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      ctx.font = 'bold 14px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      if (calStep === 'click_top_left') {
        ctx.fillText('Click TOP-LEFT corner of a slot', W / 2, H / 2);
      } else if (calStep === 'click_bottom_right') {
        ctx.fillText('Click BOTTOM-RIGHT corner of the same slot', W / 2, H / 2);
        if (topLeft) {
          ctx.beginPath();
          ctx.arc(topLeft.x, topLeft.y, 4, 0, Math.PI * 2);
          ctx.fillStyle = 'rgba(255,255,0,0.9)';
          ctx.fill();
        }
      }
      return;
    }

    const active = state.surveys
      .filter(s => !s.collected)
      .sort((a, b) => a.route_order! - b.route_order!);

    for (let i = 0; i < active.length; i++) {
      const slotIndex = (startSlot - 1) + i; // 0-based
      const col = slotIndex % columns;
      const row = Math.floor(slotIndex / columns);
      const cx = cal.x + col * cal.w + cal.w / 2;
      const cy = cal.y + row * cal.h + cal.h / 2;

      // Tag background
      ctx.beginPath();
      ctx.arc(cx, cy, 12, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255, 170, 0, 0.85)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();

      // Tag number
      ctx.fillStyle = '#000';
      ctx.font = 'bold 11px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(active[i].route_order), cx, cy);
    }
  }, [state, cal, calStep, columns, startSlot, topLeft, size]);

  return (
    <div style={{
      width: '100vw', height: '100vh',
      background: 'transparent',
      pointerEvents: 'none',
      boxSizing: 'border-box',
      border: '2px solid rgba(255, 220, 0, 0.6)',
    }}>
      <div
        style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: 22,
          background: 'rgba(255, 220, 0, 0.35)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'grab', pointerEvents: 'auto',
          fontSize: 11, fontFamily: 'sans-serif', userSelect: 'none', zIndex: 10,
          color: 'rgba(255,255,255,0.8)',
        }}
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        {...{ 'data-tauri-drag-region': true } as any}
      >
        INV
      </div>
      <canvas
        ref={canvasRef}
        width={size.w}
        height={size.h}
        style={{
          display: 'block',
          pointerEvents: 'auto',
          cursor: 'crosshair',
        }}
        onClick={handleCanvasClick}
      />
      <ResizeHandles />
    </div>
  );
}
```

**Step 2: Add the route in main.tsx**

Add import and route for InventoryOverlay:

```tsx
import InventoryOverlay from './pages/InventoryOverlay';
```

Add route inside `<Routes>`:

```tsx
<Route path="/inventory-overlay" element={<InventoryOverlay />} />
```

**Step 3: Verify frontend builds**

Run: `mise exec -- npx vite build`
Expected: builds with no errors

**Step 4: Commit**

```bash
git add src/pages/InventoryOverlay.tsx src/main.tsx
git commit -m "feat: add inventory overlay page with grid calibration and tag rendering"
```

---

### Task 4: Add inventory overlay controls to ControlPanel

**Files:**
- Modify: `src/pages/ControlPanel.tsx`

**Step 1: Add inventory overlay config UI**

In `ControlPanel.tsx`, add state variables after existing state declarations (around line 17):

```tsx
const [invOverlayVisible, setInvOverlayVisible] = useState(true);
const [invColumns, setInvColumns] = useState(() => localStorage.getItem('gorgon-inv-columns') ?? '11');
const [invStartSlot, setInvStartSlot] = useState(() => localStorage.getItem('gorgon-inv-start-slot') ?? '1');
```

Add handler functions after `onZoneChange` (around line 54):

```tsx
const toggleInvOverlay = async () => {
  try {
    const visible = await invoke<boolean>('toggle_inventory_overlay_visible');
    setInvOverlayVisible(visible);
  } catch (e) {
    console.error(e);
  }
};

const applyInvConfig = () => {
  const cols = parseInt(invColumns, 10);
  const slot = parseInt(invStartSlot, 10);
  if (!isNaN(cols) && cols > 0) localStorage.setItem('gorgon-inv-columns', String(cols));
  if (!isNaN(slot) && slot > 0) localStorage.setItem('gorgon-inv-start-slot', String(slot));
};

const recalibrateInv = () => {
  localStorage.removeItem('gorgon-inv-calibration');
};
```

Add UI section after the existing `<hr>` and before the settings button (before the closing `<hr>` around line 107):

```tsx
<hr style={{ margin: '12px 0 8px' }} />
<h4 style={{ margin: '0 0 8px', fontSize: 14 }}>Inventory Overlay</h4>
<div style={{ display: 'flex', gap: 4, alignItems: 'center', marginBottom: 6, fontSize: 12 }}>
  <span style={{ color: '#888' }}>Cols:</span>
  <input value={invColumns} onChange={e => setInvColumns(e.target.value)}
    style={{ width: 35, padding: '2px 4px', fontSize: 12 }} />
  <span style={{ color: '#888' }}>Start slot:</span>
  <input value={invStartSlot} onChange={e => setInvStartSlot(e.target.value)}
    style={{ width: 35, padding: '2px 4px', fontSize: 12 }} />
  <button onClick={applyInvConfig} style={{ fontSize: 12, padding: '2px 8px' }}>Set</button>
</div>
<div style={{ display: 'flex', gap: 4, fontSize: 12 }}>
  <button onClick={toggleInvOverlay}>{invOverlayVisible ? 'Hide' : 'Show'} Inv Overlay</button>
  <button onClick={recalibrateInv}>Recalibrate</button>
</div>
```

**Step 2: Verify frontend builds**

Run: `mise exec -- npx vite build`
Expected: builds with no errors

**Step 3: Commit**

```bash
git add src/pages/ControlPanel.tsx
git commit -m "feat: add inventory overlay config controls to control panel"
```

---

### Task 5: Integration test and final verification

**Step 1: Run all Rust tests**

Run: `cd src-tauri && mise exec -- cargo test`
Expected: all tests pass

**Step 2: Run frontend type check**

Run: `mise exec -- npx vite build`
Expected: builds with no errors

**Step 3: Manual smoke test**

Run: `WEBKIT_DISABLE_DMABUF_RENDERER=1 mise exec -- npm run tauri dev`

Verify:
- Three windows appear: control panel, map overlay, inventory overlay
- Inventory overlay has drag bar labeled "INV" and resize handles
- Two-click calibration works (click top-left then bottom-right of a slot)
- Tags appear at grid positions with survey route_order numbers
- Columns/start slot controls in control panel update the overlay
- Skip/clear in control panel updates inventory overlay tags
- Hide/Show and Recalibrate buttons work

**Step 4: Final commit if any fixups needed**
