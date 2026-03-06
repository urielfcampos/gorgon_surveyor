import { useCallback, useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';

import { useSurveyState } from '../hooks/useSurveyState';

type ResizeDirection = 'East' | 'North' | 'NorthEast' | 'NorthWest' | 'South' | 'SouthEast' | 'SouthWest' | 'West';

const ANCHOR_KEY = 'gorgon-overlay-anchor';
const SCALE_KEY = 'gorgon-overlay-scale';
const DEFAULT_SCALE = 0.3;

interface Config {
  current_zone: string;
  colors: { uncollected: string; collected: string; waypoint: string; motherlode: string };
}

interface Anchor { x: number; y: number; }

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

function surveyToCanvas(gx: number, gy: number, anchor: Anchor, scale: number): [number, number] {
  return [anchor.x + gx * scale, anchor.y - gy * scale];
}

export default function Overlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [config, setConfig] = useState<Config | null>(null);
  const [anchor, setAnchor] = useState<Anchor | null>(() => {
    const saved = localStorage.getItem(ANCHOR_KEY);
    return saved ? JSON.parse(saved) : null;
  });
  const [scale, setScale] = useState<number>(() => {
    const saved = localStorage.getItem(SCALE_KEY);
    return saved ? parseFloat(saved) : DEFAULT_SCALE;
  });
  const [size, setSize] = useState({ w: window.innerWidth, h: window.innerHeight });

  useEffect(() => {
    document.documentElement.style.background = 'transparent';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.background = 'transparent';
    document.body.style.overflow = 'hidden';
  }, []);

  // Track window resize so canvas stays the right size
  useEffect(() => {
    const onResize = () => setSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  useEffect(() => {
    invoke<Config>('get_config').then(setConfig).catch(console.error);
    const unlisten = listen<Config>('config-updated', e => setConfig(e.payload));
    return () => { unlisten.then(f => f()); };
  }, []);

  // Pick up scale/anchor changes made from the ControlPanel window
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === SCALE_KEY && e.newValue) setScale(parseFloat(e.newValue));
      if (e.key === ANCHOR_KEY) setAnchor(e.newValue ? JSON.parse(e.newValue) : null);
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const handleCanvasClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
    const newAnchor = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    setAnchor(newAnchor);
    localStorage.setItem(ANCHOR_KEY, JSON.stringify(newAnchor));
  }, []);

  const handleContextMenu = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    e.preventDefault();
    if (!anchor) return;
    const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const clickY = e.clientY - rect.top;
    const HIT_RADIUS = 15;
    let closest: { id: number; dist: number } | null = null;
    for (const survey of state.surveys) {
      if (survey.collected) continue;
      const [cx, cy] = surveyToCanvas(survey.x, survey.y, anchor, scale);
      const dist = Math.hypot(clickX - cx, clickY - cy);
      if (dist <= HIT_RADIUS && (!closest || dist < closest.dist)) {
        closest = { id: survey.id, dist };
      }
    }
    if (closest) {
      invoke('skip_survey', { id: closest.id }).catch(console.error);
    }
  }, [anchor, scale, state.surveys]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !config) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    if (!anchor) {
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      ctx.font = 'bold 14px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('Click to mark your position', W / 2, H / 2);
      return;
    }

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
  }, [state, config, anchor, scale, size]);

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
        ⠿
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
        onContextMenu={handleContextMenu}
      />
      <ResizeHandles />
    </div>
  );
}
