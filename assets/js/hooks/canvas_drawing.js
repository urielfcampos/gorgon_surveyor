// Shared canvas drawing functions for survey overlay rendering.
// Coordinates are in percentage space (0-100), converted to canvas pixels
// using the provided canvasW/canvasH parameters.

/**
 * Nearest-neighbor TSP: returns surveys reordered by shortest path.
 */
export function optimizeRoute(surveys) {
  if (surveys.length <= 2) return surveys;
  const dist = (a, b) =>
    Math.hypot(a.x_pct - b.x_pct, a.y_pct - b.y_pct);

  const remaining = [...surveys];
  const route = [remaining.shift()];
  while (remaining.length > 0) {
    const last = route[route.length - 1];
    let bestIdx = 0;
    let bestDist = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const d = dist(last, remaining[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    route.push(remaining.splice(bestIdx, 1)[0]);
  }
  return route;
}

/**
 * Draw collected survey markers (background layer, reduced opacity).
 */
export function drawCollectedSurveys(ctx, surveys, W, H) {
  ctx.globalAlpha = 0.45;
  for (const s of surveys) {
    const x = (s.x_pct / 100) * W;
    const y = (s.y_pct / 100) * H;

    ctx.beginPath();
    ctx.arc(x, y, 10, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(0,200,0,0.55)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.7)";
    ctx.lineWidth = 1.5;
    ctx.stroke();

    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.font = "bold 9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(s.survey_number), x, y);
  }
  ctx.globalAlpha = 1.0;
}

/**
 * Draw uncollected survey markers (foreground layer, full visibility).
 */
export function drawUncollectedSurveys(ctx, surveys, W, H) {
  for (const s of surveys) {
    const x = (s.x_pct / 100) * W;
    const y = (s.y_pct / 100) * H;

    ctx.beginPath();
    ctx.arc(x, y, 10, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(0,150,255,0.55)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.7)";
    ctx.lineWidth = 1.5;
    ctx.stroke();

    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.font = "bold 9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(s.survey_number), x, y);
  }
}

/**
 * Draw route path connecting surveys in the given order.
 * routeOrder is an array of survey IDs; surveys is the full placed-surveys list.
 * Only uncollected surveys in the route are drawn.
 */
export function drawRoute(ctx, routeOrder, surveys, W, H) {
  const surveyById = Object.fromEntries(surveys.map(s => [s.id, s]));
  const routeSurveys = routeOrder
    .filter(id => surveyById[id] && !surveyById[id].collected)
    .map(id => surveyById[id]);

  if (routeSurveys.length > 1) {
    ctx.beginPath();
    ctx.moveTo((routeSurveys[0].x_pct / 100) * W, (routeSurveys[0].y_pct / 100) * H);
    for (let i = 1; i < routeSurveys.length; i++) {
      ctx.lineTo((routeSurveys[i].x_pct / 100) * W, (routeSurveys[i].y_pct / 100) * H);
    }
    ctx.strokeStyle = "rgba(255,255,255,0.5)";
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.stroke();
    ctx.setLineDash([]);
  }
}

/**
 * Draw the detection zone rectangle.
 */
export function drawDetectZone(ctx, zone, W, H) {
  const zx = (zone.x1 / 100) * W;
  const zy = (zone.y1 / 100) * H;
  const zw = ((zone.x2 - zone.x1) / 100) * W;
  const zh = ((zone.y2 - zone.y1) / 100) * H;
  ctx.strokeStyle = "rgba(255,255,0,0.7)";
  ctx.lineWidth = 2;
  ctx.setLineDash([8, 4]);
  ctx.strokeRect(zx, zy, zw, zh);
  ctx.setLineDash([]);
  ctx.fillStyle = "rgba(255,255,0,0.6)";
  ctx.font = "bold 12px sans-serif";
  ctx.textAlign = "left";
  ctx.textBaseline = "bottom";
  ctx.fillText("Detect Zone", zx + 4, zy - 4);
}

/**
 * Draw the inventory zone rectangle.
 */
export function drawInventoryZone(ctx, zone, W, H) {
  const zx = (zone.x1 / 100) * W;
  const zy = (zone.y1 / 100) * H;
  const zw = ((zone.x2 - zone.x1) / 100) * W;
  const zh = ((zone.y2 - zone.y1) / 100) * H;
  ctx.strokeStyle = "rgba(0,255,200,0.7)";
  ctx.lineWidth = 2;
  ctx.setLineDash([8, 4]);
  ctx.strokeRect(zx, zy, zw, zh);
  ctx.setLineDash([]);
  ctx.fillStyle = "rgba(0,255,200,0.6)";
  ctx.font = "bold 12px sans-serif";
  ctx.textAlign = "left";
  ctx.textBaseline = "bottom";
  ctx.fillText("Inventory Zone", zx + 4, zy - 4);
}

/**
 * Draw inventory survey number markers.
 */
export function drawInventoryMarkers(ctx, markers, W, H) {
  for (const m of markers) {
    const x = (m.x_pct / 100) * W;
    const y = (m.y_pct / 100) * H;
    ctx.beginPath();
    ctx.arc(x, y, 8, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(0,150,255,0.7)";
    ctx.fill();
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.fillStyle = "#fff";
    ctx.font = "bold 8px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(m.number), x, y);
  }
}

/**
 * Draw motherlode reading dots and estimated location marker.
 * motherlode is the state.motherlode object with readings[] and estimated_location.
 */
export function drawMotherlode(ctx, motherlode, W, H) {
  if (!motherlode) return;

  // Draw reading position dots
  for (let i = 0; i < motherlode.readings.length; i++) {
    const r = motherlode.readings[i];
    const x = (r.x_pct / 100) * W;
    const y = (r.y_pct / 100) * H;

    ctx.beginPath();
    ctx.arc(x, y, 6, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(200,200,200,0.6)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.8)";
    ctx.lineWidth = 1;
    ctx.stroke();

    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.font = "bold 8px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(i + 1), x, y);
  }

  // Draw estimated location marker (orange diamond)
  if (motherlode.estimated_location) {
    const ex = (motherlode.estimated_location.x_pct / 100) * W;
    const ey = (motherlode.estimated_location.y_pct / 100) * H;
    const size = 12;

    ctx.beginPath();
    ctx.moveTo(ex, ey - size);
    ctx.lineTo(ex + size, ey);
    ctx.lineTo(ex, ey + size);
    ctx.lineTo(ex - size, ey);
    ctx.closePath();
    ctx.fillStyle = "rgba(255,165,0,0.8)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.9)";
    ctx.lineWidth = 2;
    ctx.stroke();

    // "X" label
    ctx.fillStyle = "#fff";
    ctx.font = "bold 10px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("X", ex, ey);
  }
}
