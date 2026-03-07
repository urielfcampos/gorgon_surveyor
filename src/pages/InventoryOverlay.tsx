import { useCallback, useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
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

  // Disable click-through during calibration so canvas receives clicks
  useEffect(() => {
    invoke('set_inventory_overlay_passthrough', { enabled: calStep === 'calibrated' }).catch(console.error);
  }, [calStep]);

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

    if (calStep === 'click_bottom_right') {
      if (!topLeft) return;
      const w = Math.abs(click.x - topLeft.x);
      const h = Math.abs(click.y - topLeft.y);
      if (w < 5 || h < 5) return; // too small, ignore
      const newCal: SlotCal = { x: Math.min(topLeft.x, click.x), y: Math.min(topLeft.y, click.y), w, h };
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
    // On WebKitGTK with transparent windows, clearRect alone doesn't
    // properly erase previous frames. Force a full opaque-then-clear cycle.
    ctx.globalCompositeOperation = 'copy';
    ctx.fillStyle = 'rgba(0,0,0,0)';
    ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = 'source-over';

    if (calStep !== 'calibrated' || !cal) return;

    const active = state.surveys
      .filter(s => !s.collected)
      .sort((a, b) => a.route_order! - b.route_order!);

    // Draw calibration grid preview (faint lines showing slot boundaries)
    const maxCols = columns;
    const maxRows = Math.ceil(active.length / columns) + 1;
    ctx.strokeStyle = 'rgba(255, 255, 0, 0.15)';
    ctx.lineWidth = 1;
    for (let c = 0; c <= maxCols; c++) {
      const gx = cal.x + c * cal.w;
      ctx.beginPath();
      ctx.moveTo(gx, cal.y);
      ctx.lineTo(gx, cal.y + maxRows * cal.h);
      ctx.stroke();
    }
    for (let r = 0; r <= maxRows; r++) {
      const gy = cal.y + r * cal.h;
      ctx.beginPath();
      ctx.moveTo(cal.x, gy);
      ctx.lineTo(cal.x + maxCols * cal.w, gy);
      ctx.stroke();
    }

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
        onMouseDown={() => getCurrentWindow().startDragging().catch(console.error)}
        style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: 22,
          background: 'rgba(255, 220, 0, 0.35)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'grab', pointerEvents: 'auto',
          fontSize: 11, fontFamily: 'sans-serif', userSelect: 'none', zIndex: 10,
          color: 'rgba(255,255,255,0.8)',
        }}
      >
        INV
      </div>
      {calStep !== 'calibrated' ? (
        <>
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
            {calStep === 'click_top_left' && 'Click TOP-LEFT corner of a slot'}
            {calStep === 'click_bottom_right' && 'Click BOTTOM-RIGHT corner of the same slot'}
          </div>
          {topLeft && calStep === 'click_bottom_right' && (
            <div style={{
              position: 'absolute',
              left: topLeft.x - 4, top: topLeft.y - 4,
              width: 8, height: 8, borderRadius: '50%',
              background: 'rgba(255,255,0,0.9)',
              pointerEvents: 'none', zIndex: 5,
            }} />
          )}
          <div
            style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, pointerEvents: 'auto', cursor: 'crosshair' }}
            onClick={handleCanvasClick}
          />
        </>
      ) : (
        <canvas
          ref={canvasRef}
          width={size.w}
          height={size.h}
          style={{ display: 'block' }}
        />
      )}
      <ResizeHandles />
    </div>
  );
}
