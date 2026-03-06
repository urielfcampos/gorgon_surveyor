import { useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useSurveyState } from '../hooks/useSurveyState';

// Zone bounding boxes — kept in sync with src-tauri/src/zones.rs
const ZONE_BOUNDS: Record<string, [number, number, number, number]> = {
  'Serbule':       [-2048, -2048, 2048, 2048],
  'Eltibule':      [-2048, -2048, 2048, 2048],
  'Kur Mountains': [-2048, -2048, 2048, 2048],
  'Povus':         [-2048, -2048, 2048, 2048],
  'Ilmari':        [-2048, -2048, 2048, 2048],
  'Gazluk':        [-2048, -2048, 2048, 2048],
};

interface Config {
  current_zone: string;
  colors: { uncollected: string; collected: string; waypoint: string; motherlode: string };
}

function gameToCanvas(
  gx: number, gy: number,
  bounds: [number, number, number, number],
  W: number, H: number
): [number, number] {
  const [minX, minY, maxX, maxY] = bounds;
  return [
    ((gx - minX) / (maxX - minX)) * W,
    ((gy - minY) / (maxY - minY)) * H,
  ];
}

export default function Overlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [config, setConfig] = useState<Config | null>(null);

  useEffect(() => {
    invoke<Config>('get_config').then(setConfig).catch(console.error);
    const unlisten = listen<Config>('config-updated', e => setConfig(e.payload));
    return () => { unlisten.then(f => f()); };
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !config) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    const bounds = ZONE_BOUNDS[config.current_zone] ?? [-2048, -2048, 2048, 2048];
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
      const [fx, fy] = gameToCanvas(ordered[0].x, ordered[0].y, bounds, W, H);
      ctx.moveTo(fx, fy);
      for (let i = 1; i < ordered.length; i++) {
        const [nx, ny] = gameToCanvas(ordered[i].x, ordered[i].y, bounds, W, H);
        ctx.lineTo(nx, ny);
      }
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Survey dots
    for (const survey of state.surveys) {
      if (survey.collected) continue;
      const [cx, cy] = gameToCanvas(survey.x, survey.y, bounds, W, H);
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
    const span = bounds[2] - bounds[0];
    for (const [[px, py], dist] of state.motherlode_readings) {
      const [cx, cy] = gameToCanvas(px, py, bounds, W, H);
      const scaledR = (dist / span) * W;
      ctx.beginPath();
      ctx.arc(cx, cy, scaledR, 0, Math.PI * 2);
      ctx.strokeStyle = motherlode + '88';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    // Triangulated motherlode location
    if (state.motherlode_location) {
      const [mx, my] = state.motherlode_location;
      const [cx, cy] = gameToCanvas(mx, my, bounds, W, H);
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
  }, [state, config]);

  return (
    <div style={{ width: '100vw', height: '100vh', background: 'transparent', pointerEvents: 'none' }}>
      <canvas
        ref={canvasRef}
        width={window.innerWidth}
        height={window.innerHeight}
        style={{ display: 'block' }}
      />
    </div>
  );
}
