import { useCallback, useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';

import { useSurveyState } from '../hooks/useSurveyState';
import { CALIBRATION_KEY } from '../constants';

type ResizeDirection = 'East' | 'North' | 'NorthEast' | 'NorthWest' | 'South' | 'SouthEast' | 'SouthWest' | 'West';

interface Config {
  current_zone: string;
  colors: { uncollected: string; collected: string; waypoint: string; motherlode: string };
}

interface Calibration { anchor: { x: number; y: number }; scaleX: number; scaleY: number; }
type CalibrationStep = 'waiting_for_survey' | 'click_player' | 'click_survey' | 'calibrated';

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

function surveyToCanvas(gx: number, gy: number, anchor: { x: number; y: number }, scaleX: number, scaleY: number): [number, number] {
  return [anchor.x + gx * scaleX, anchor.y - gy * scaleY];
}

export default function Overlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [config, setConfig] = useState<Config | null>(null);
  const [calibration, setCalibration] = useState<Calibration | null>(() => {
    const saved = localStorage.getItem(CALIBRATION_KEY);
    if (!saved) return null;
    const parsed = JSON.parse(saved);
    // Migrate old single-scale calibration
    if ('scale' in parsed && !('scaleX' in parsed)) {
      return { anchor: parsed.anchor, scaleX: parsed.scale, scaleY: parsed.scale };
    }
    return parsed;
  });
  const [calStep, setCalStep] = useState<CalibrationStep>(() => {
    const saved = localStorage.getItem(CALIBRATION_KEY);
    return saved ? 'calibrated' : 'waiting_for_survey';
  });
  const [playerClick, setPlayerClick] = useState<{ x: number; y: number } | null>(null);
  const [calibratingSurvey, setCalibratingSurvey] = useState<{ x: number; y: number } | null>(null);
  const [size, setSize] = useState({ w: window.innerWidth, h: window.innerHeight });

  useEffect(() => {
    document.documentElement.style.background = 'transparent';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.background = 'transparent';
    document.body.style.overflow = 'hidden';
    document.body.style.margin = '0';
    document.body.style.padding = '0';
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

  // Disable click-through during calibration so canvas receives clicks
  useEffect(() => {
    invoke('set_overlay_passthrough', { enabled: calStep === 'calibrated' }).catch(console.error);
  }, [calStep]);

  // Auto-transition from waiting_for_survey to click_player
  useEffect(() => {
    if (calStep !== 'waiting_for_survey') return;
    const uncollected = state.surveys.filter(s => !s.collected);
    if (uncollected.length > 0) {
      const latest = uncollected[uncollected.length - 1];
      setCalibratingSurvey({ x: latest.x, y: latest.y });
      setCalStep('click_player');
    }
  }, [calStep, state.surveys]);

  // Pick up calibration changes made from the ControlPanel window
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

  const handleCanvasClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
    const click = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    console.log('[CAL CLICK]', { calStep, clientX: e.clientX, clientY: e.clientY, rectLeft: rect.left, rectTop: rect.top, clickX: click.x, clickY: click.y, target: (e.target as HTMLElement).tagName });

    if (calStep === 'click_player') {
      setPlayerClick(click);
      setCalStep('click_survey');
      return;
    }

    if (calStep === 'click_survey' && playerClick && calibratingSurvey) {
      const dx = click.x - playerClick.x;
      const dy = playerClick.y - click.y; // flip: screen y is inverted vs game y
      if (Math.abs(calibratingSurvey.x) < 1 || Math.abs(calibratingSurvey.y) < 1) return;
      const scaleX = dx / calibratingSurvey.x;
      const scaleY = dy / calibratingSurvey.y;
      const newCal: Calibration = { anchor: playerClick, scaleX, scaleY };
      console.log('[CAL COMPLETE]', { anchor: playerClick, scaleX, scaleY, surveyGameCoords: calibratingSurvey });
      setCalibration(newCal);
      setCalStep('calibrated');
      localStorage.setItem(CALIBRATION_KEY, JSON.stringify(newCal));
      setPlayerClick(null);
      setCalibratingSurvey(null);
      return;
    }
  }, [calStep, playerClick, calibratingSurvey]);

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
      const [cx, cy] = surveyToCanvas(survey.x, survey.y, calibration.anchor, calibration.scaleX, calibration.scaleY);
      const dist = Math.hypot(clickX - cx, clickY - cy);
      if (dist <= HIT_RADIUS && (!closest || dist < closest.dist)) {
        closest = { id: survey.id, dist };
      }
    }
    if (closest) {
      invoke('skip_survey', { id: closest.id }).catch(console.error);
    }
  }, [calibration, state.surveys]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !config) return;
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

    if (calStep !== 'calibrated' || !calibration) return;

    const { anchor, scaleX, scaleY } = calibration;
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
      const [fx, fy] = surveyToCanvas(ordered[0].x, ordered[0].y, anchor, scaleX, scaleY);
      ctx.moveTo(fx, fy);
      for (let i = 1; i < ordered.length; i++) {
        const [nx, ny] = surveyToCanvas(ordered[i].x, ordered[i].y, anchor, scaleX, scaleY);
        ctx.lineTo(nx, ny);
      }
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Survey dots
    for (const survey of state.surveys) {
      if (survey.collected) continue;
      const [cx, cy] = surveyToCanvas(survey.x, survey.y, anchor, scaleX, scaleY);
      ctx.beginPath();
      ctx.arc(cx, cy, 9, 0, Math.PI * 2);
      ctx.fillStyle = uncollected;
      ctx.fill();
      ctx.fillStyle = '#000';
      ctx.font = 'bold 10px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(survey.survey_number), cx, cy);
    }

    // Motherlode distance circles
    for (const [[px, py], dist] of state.motherlode_readings) {
      const [cx, cy] = surveyToCanvas(px, py, anchor, scaleX, scaleY);
      const avgScale = (Math.abs(scaleX) + Math.abs(scaleY)) / 2;
      const scaledR = dist * avgScale;
      ctx.beginPath();
      ctx.arc(cx, cy, scaledR, 0, Math.PI * 2);
      ctx.strokeStyle = motherlode + '88';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    // Triangulated motherlode location
    if (state.motherlode_location) {
      const [mx, my] = state.motherlode_location;
      const [cx, cy] = surveyToCanvas(mx, my, anchor, scaleX, scaleY);
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

    // Anchor marker removed — it ghosts on WebKitGTK transparent windows
  }, [state, config, calibration, calStep, playerClick, size]);

  return (
    <div style={{
      position: 'relative',
      width: '100vw', height: '100vh',
      background: 'transparent',
      pointerEvents: 'none',
      outline: '2px solid rgba(255, 220, 0, 0.6)',
      outlineOffset: -2,
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
        onMouseDown={() => getCurrentWindow().startDragging().catch(console.error)}
      >
        ⠿
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
            {calStep === 'waiting_for_survey' && 'Waiting for survey data...'}
            {calStep === 'click_player' && 'Click YOUR position on the map'}
            {calStep === 'click_survey' && 'Now click the SURVEY location'}
          </div>
          {playerClick && calStep === 'click_survey' && (
            <div style={{
              position: 'absolute',
              left: playerClick.x - 5, top: playerClick.y - 5,
              width: 10, height: 10, borderRadius: '50%',
              background: 'rgba(255,0,0,0.9)',
              border: '2px solid #fff',
              pointerEvents: 'none', zIndex: 5,
            }} />
          )}
          <div
            style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, pointerEvents: 'auto', cursor: 'crosshair', background: 'rgba(0,0,0,0.01)' }}
            onClick={handleCanvasClick}
          />
        </>
      ) : (
        <canvas
          ref={canvasRef}
          width={size.w}
          height={size.h}
          style={{ position: 'absolute', top: 0, left: 0, display: 'block', pointerEvents: 'auto', cursor: 'default' }}
          onContextMenu={handleContextMenu}
        />
      )}
      <ResizeHandles />
    </div>
  );
}
