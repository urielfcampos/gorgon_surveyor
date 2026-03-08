import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";

import { useSurveyState } from "../hooks/useSurveyState";

type ResizeDirection =
  | "East"
  | "North"
  | "NorthEast"
  | "NorthWest"
  | "South"
  | "SouthEast"
  | "SouthWest"
  | "West";

interface Config {
  current_zone: string;
  colors: {
    uncollected: string;
    waypoint: string;
    motherlode: string;
  };
}

/** Survey ID → pixel position on the overlay */
type Placements = Record<number, { x: number; y: number }>;

const PLACEMENTS_KEY = "gorgon-survey-placements";

const HANDLES: { dir: ResizeDirection; style: React.CSSProperties }[] = [
  { dir: "NorthWest", style: { top: -4, left: -4, cursor: "nw-resize" } },
  {
    dir: "North",
    style: {
      top: -4,
      left: "50%",
      transform: "translateX(-50%)",
      cursor: "n-resize",
    },
  },
  { dir: "NorthEast", style: { top: -4, right: -4, cursor: "ne-resize" } },
  {
    dir: "East",
    style: {
      top: "50%",
      right: -4,
      transform: "translateY(-50%)",
      cursor: "e-resize",
    },
  },
  { dir: "SouthEast", style: { bottom: -4, right: -4, cursor: "se-resize" } },
  {
    dir: "South",
    style: {
      bottom: -4,
      left: "50%",
      transform: "translateX(-50%)",
      cursor: "s-resize",
    },
  },
  { dir: "SouthWest", style: { bottom: -4, left: -4, cursor: "sw-resize" } },
  {
    dir: "West",
    style: {
      top: "50%",
      left: -4,
      transform: "translateY(-50%)",
      cursor: "w-resize",
    },
  },
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
            position: "absolute",
            width: 10,
            height: 10,
            background: "rgba(255, 220, 0, 0.7)",
            border: "1px solid rgba(0,0,0,0.4)",
            borderRadius: 2,
            pointerEvents: "auto",
            zIndex: 20,
            ...style,
          }}
        />
      ))}
    </>
  );
}

export default function Overlay() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const state = useSurveyState();
  const [config, setConfig] = useState<Config | null>(null);
  const [placements, setPlacements] = useState<Placements>(() => {
    const saved = localStorage.getItem(PLACEMENTS_KEY);
    return saved ? JSON.parse(saved) : {};
  });
  // The survey currently being placed (null = not placing)
  const [placingSurvey, setPlacingSurvey] = useState<{
    id: number;
    num: number;
    x: number;
    y: number;
  } | null>(null);
  // Survey IDs that have been right-clicked (shown in green)
  const [collected, setCollected] = useState<Set<number>>(new Set());
  const [size, setSize] = useState({
    w: window.innerWidth,
    h: window.innerHeight,
  });

  useEffect(() => {
    document.documentElement.style.background = "transparent";
    document.documentElement.style.overflow = "hidden";
    document.body.style.background = "transparent";
    document.body.style.overflow = "hidden";
    document.body.style.margin = "0";
    document.body.style.padding = "0";
  }, []);

  useEffect(() => {
    const onResize = () =>
      setSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);

  useEffect(() => {
    invoke<Config>("get_config").then(setConfig).catch(console.error);
    const unlisten = listen<Config>("config-updated", (e) =>
      setConfig(e.payload),
    );
    return () => {
      unlisten.then((f) => f());
    };
  }, []);

  // Disable click-through when placing a survey so overlay receives clicks
  useEffect(() => {
    invoke("set_overlay_passthrough", {
      enabled: placingSurvey === null,
    }).catch(console.error);
  }, [placingSurvey]);

  // When a new unplaced survey arrives, prompt to place it.
  // When all surveys are cleared, clear placements too.
  useEffect(() => {
    const uncollected = state.surveys.filter((s) => !s.collected);
    if (uncollected.length === 0 && Object.keys(placements).length > 0) {
      setPlacements({});
      localStorage.setItem(PLACEMENTS_KEY, JSON.stringify({}));
      setPlacingSurvey(null);
      setCollected(new Set());
      return;
    }
    if (placingSurvey !== null) return;
    const unplaced = uncollected.filter((s) => !(s.id in placements));
    if (unplaced.length > 0) {
      const s = unplaced[0];
      setPlacingSurvey({ id: s.id, num: s.survey_number, x: s.x, y: s.y });
    }
  }, [placingSurvey, state.surveys, placements]);

  // Pick up placement changes from the ControlPanel window (clear)
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === PLACEMENTS_KEY) {
        if (e.newValue) {
          setPlacements(JSON.parse(e.newValue));
        } else {
          setPlacements({});
        }
        setPlacingSurvey(null);
      }
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      if (!placingSurvey) return;
      const rect = (e.target as HTMLElement).getBoundingClientRect();
      const click = { x: e.clientX - rect.left, y: e.clientY - rect.top };

      const newPlacements = {
        ...placements,
        [placingSurvey.id]: click,
      };
      setPlacements(newPlacements);
      localStorage.setItem(PLACEMENTS_KEY, JSON.stringify(newPlacements));
      setPlacingSurvey(null);
    },
    [placingSurvey, placements],
  );

  const handleContextMenu = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      e.preventDefault();
      const rect = (e.target as HTMLCanvasElement).getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const clickY = e.clientY - rect.top;
      const HIT_RADIUS = 15;
      let closest: { id: number; dist: number } | null = null;
      for (const survey of state.surveys) {
        if (survey.collected) continue;
        const pos = placements[survey.id];
        if (!pos) continue;
        const dist = Math.hypot(clickX - pos.x, clickY - pos.y);
        if (dist <= HIT_RADIUS && (!closest || dist < closest.dist)) {
          closest = { id: survey.id, dist };
        }
      }
      if (closest) {
        setCollected((prev) => {
          const next = new Set(prev);
          if (next.has(closest!.id)) {
            next.delete(closest!.id);
          } else {
            next.add(closest!.id);
          }
          return next;
        });
      }
    },
    [placements, state.surveys],
  );

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !config) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.globalCompositeOperation = "copy";
    ctx.fillStyle = "rgba(0,0,0,0)";
    ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = "source-over";

    if (placingSurvey !== null) return;

    const { uncollected, waypoint } = config.colors;

    // Route lines between placed surveys
    const ordered = state.surveys
      .filter(
        (s) => !s.collected && s.route_order !== null && s.id in placements,
      )
      .sort((a, b) => a.route_order! - b.route_order!);

    if (ordered.length > 1) {
      ctx.strokeStyle = waypoint;
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      const f = placements[ordered[0].id];
      ctx.moveTo(f.x, f.y);
      for (let i = 1; i < ordered.length; i++) {
        const p = placements[ordered[i].id];
        ctx.lineTo(p.x, p.y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Survey dots (only placed surveys)
    for (const survey of state.surveys) {
      if (survey.collected) continue;
      const pos = placements[survey.id];
      if (!pos) continue;
      const isCollected = collected.has(survey.id);
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, 9, 0, Math.PI * 2);
      ctx.fillStyle = isCollected ? "#44FF44" : uncollected;
      ctx.fill();
      ctx.fillStyle = "#000";
      ctx.font = "bold 10px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(survey.survey_number), pos.x, pos.y);
    }
  }, [state, config, placements, placingSurvey, collected, size]);

  return (
    <div
      style={{
        position: "relative",
        width: "100vw",
        height: "100vh",
        background: "transparent",
        pointerEvents: "none",
        outline: "2px solid rgba(255, 220, 0, 0.6)",
        outlineOffset: -2,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 22,
          background: "rgba(255, 220, 0, 0.35)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          cursor: "grab",
          pointerEvents: "auto",
          fontSize: 11,
          fontFamily: "sans-serif",
          userSelect: "none",
          zIndex: 10,
          color: "rgba(255,255,255,0.8)",
        }}
        onMouseDown={() =>
          getCurrentWindow().startDragging().catch(console.error)
        }
      >
        ⠿
      </div>
      {placingSurvey ? (
        <>
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: "translate(-50%, -50%)",
              color: "#fff",
              font: "bold 14px sans-serif",
              textAlign: "center",
              pointerEvents: "none",
              zIndex: 5,
              background: "rgba(0, 0, 0, 0.75)",
              padding: "8px 16px",
              borderRadius: 6,
            }}
          >
            {`Click Survey #${placingSurvey.num} (${Math.abs(Math.round(placingSurvey.x))}m ${placingSurvey.x >= 0 ? "E" : "W"}, ${Math.abs(Math.round(placingSurvey.y))}m ${placingSurvey.y >= 0 ? "N" : "S"})`}
          </div>
          {/* Show already-placed surveys as markers */}
          {Object.entries(placements).map(([id, pos]) => (
            <div
              key={id}
              style={{
                position: "absolute",
                left: pos.x - 5,
                top: pos.y - 5,
                width: 10,
                height: 10,
                borderRadius: "50%",
                background: "rgba(0,200,255,0.9)",
                border: "1px solid #000",
                pointerEvents: "none",
                zIndex: 5,
              }}
            />
          ))}
          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              pointerEvents: "auto",
              cursor: "crosshair",
              background: "rgba(0,0,0,0.01)",
            }}
            onClick={handleClick}
          />
        </>
      ) : (
        <canvas
          ref={canvasRef}
          width={size.w}
          height={size.h}
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            display: "block",
            pointerEvents: "auto",
            cursor: "default",
          }}
          onContextMenu={handleContextMenu}
        />
      )}
      <ResizeHandles />
    </div>
  );
}
