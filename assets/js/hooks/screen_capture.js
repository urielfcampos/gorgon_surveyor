// Nearest-neighbor TSP: returns surveys reordered by shortest path
function optimizeRoute(surveys) {
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

const ScreenCapture = {
  mounted() {
    this.video = document.createElement("video");
    this.video.autoplay = true;
    this.video.playsInline = true;
    this.video.style.width = "100%";
    this.video.style.height = "100%";
    this.video.style.objectFit = "contain";

    this.canvas = document.createElement("canvas");
    this.canvas.style.position = "absolute";
    this.canvas.style.top = "0";
    this.canvas.style.left = "0";
    this.canvas.style.width = "100%";
    this.canvas.style.height = "100%";
    this.canvas.style.pointerEvents = "auto";

    this.el.style.position = "relative";
    this.el.appendChild(this.video);
    this.el.appendChild(this.canvas);

    this.ctx = this.canvas.getContext("2d");
    this.state = { surveys: [], placing_survey: null };
    this.detectZone = null; // {x1, y1, x2, y2} as percentages
    this.invZone = null;   // inventory zone
    this.settingZone = false;  // "map" or "inv" or false
    this.zoneCorner1 = null;
    this.playerPos = null; // {x_pct, y_pct}
    this.invMarkers = []; // [{x_pct, y_pct, number}]

    // Handle canvas clicks for survey placement and zone setting
    this.canvas.addEventListener("click", (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;

      // Zone setting takes priority
      if (this.settingZone) {
        if (!this.zoneCorner1) {
          this.zoneCorner1 = { x: x_pct, y: y_pct };
          this.draw();
          return;
        }
        // Second click completes the zone
        const c1 = this.zoneCorner1;
        const zone = {
          x1: Math.min(c1.x, x_pct),
          y1: Math.min(c1.y, y_pct),
          x2: Math.max(c1.x, x_pct),
          y2: Math.max(c1.y, y_pct)
        };
        if (this.settingZone === "inv") {
          this.invZone = zone;
          this.pushEvent("set_inv_zone", zone);
        } else {
          this.detectZone = zone;
          this.pushEvent("set_detect_zone", zone);
        }
        this.settingZone = false;
        this.zoneCorner1 = null;
        this.draw();
        return;
      }

      if (!this.state.placing_survey) return;
      this.pushEvent("place_survey", {
        id: this.state.placing_survey,
        x_pct: x_pct,
        y_pct: y_pct
      });
    });

    // Handle canvas right-click for toggling collected
    this.canvas.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;
      // Find nearest survey within threshold
      const threshold = 3; // percent
      const nearest = this.state.surveys
        .filter(s => s.x_pct != null)
        .find(s => Math.abs(s.x_pct - x_pct) < threshold && Math.abs(s.y_pct - y_pct) < threshold);
      if (nearest) {
        this.pushEvent("toggle_collected", { id: nearest.id });
      }
    });

    // Listen for state updates from server
    this.handleEvent("state_updated", (data) => {
      this.state = data;
      this.draw();
    });

    // Listen for start_capture event from server
    this.handleEvent("start_capture", () => this.startCapture());

    this.scanInterval = null;
    this.scanCanvas = document.createElement("canvas");

    this.handleEvent("start_auto_detect", () => {
      console.log("[auto-detect] start_auto_detect received");
      if (this.scanInterval) return;
      this.scanInterval = setInterval(() => this.captureFrame(), 3000);
    });

    this.handleEvent("stop_auto_detect", () => {
      if (this.scanInterval) {
        clearInterval(this.scanInterval);
        this.scanInterval = null;
      }
    });

    this.handleEvent("start_set_zone", () => {
      this.settingZone = "map";
      this.zoneCorner1 = null;
      this.draw();
    });

    this.handleEvent("clear_detect_zone", () => {
      this.detectZone = null;
      this.settingZone = false;
      this.zoneCorner1 = null;
      this.draw();
    });

    this.handleEvent("start_set_inv_zone", () => {
      this.settingZone = "inv";
      this.zoneCorner1 = null;
      this.draw();
    });

    this.handleEvent("clear_inv_zone", () => {
      this.invZone = null;
      this.invMarkers = [];
      this.settingZone = false;
      this.zoneCorner1 = null;
      this.draw();
    });

    this.handleEvent("inv_markers", (data) => {
      this.invMarkers = data.markers;
      this.draw();
    });

    this.handleEvent("player_position", (pos) => {
      this.playerPos = pos;
      this.draw();
    });
  },

  async startCapture() {
    if (this.stream) return;
    try {
      this.stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
      this.video.srcObject = this.stream;
      this.video.onloadedmetadata = () => this.resizeCanvas();
      window.addEventListener("resize", () => this.resizeCanvas());
    } catch (err) {
      console.error("Screen capture failed:", err);
    }
  },

  resizeCanvas() {
    this.canvas.width = this.canvas.clientWidth;
    this.canvas.height = this.canvas.clientHeight;
    this.draw();
  },

  // Compute where the video renders inside its container (object-fit: contain)
  getVideoRect() {
    const cw = this.video.clientWidth;
    const ch = this.video.clientHeight;
    const vw = this.video.videoWidth;
    const vh = this.video.videoHeight;
    const videoAR = vw / vh;
    const containerAR = cw / ch;
    let renderW, renderH, offsetX, offsetY;
    if (videoAR > containerAR) {
      renderW = cw;
      renderH = cw / videoAR;
      offsetX = 0;
      offsetY = (ch - renderH) / 2;
    } else {
      renderH = ch;
      renderW = ch * videoAR;
      offsetX = (cw - renderW) / 2;
      offsetY = 0;
    }
    return { renderW, renderH, offsetX, offsetY, cw, ch };
  },

  // Convert canvas % to video pixel coordinates
  canvasToVideoPixel(canvasPctX, canvasPctY) {
    const r = this.getVideoRect();
    const vw = this.video.videoWidth;
    const vh = this.video.videoHeight;
    const cx = (canvasPctX / 100) * r.cw;
    const cy = (canvasPctY / 100) * r.ch;
    const vx = ((cx - r.offsetX) / r.renderW) * vw;
    const vy = ((cy - r.offsetY) / r.renderH) * vh;
    return { x: Math.round(Math.max(0, Math.min(vx, vw))),
             y: Math.round(Math.max(0, Math.min(vy, vh))) };
  },

  captureFrame() {
    if (!this.video || !this.video.videoWidth) return;
    const vw = this.video.videoWidth;
    const vh = this.video.videoHeight;

    let sx = 0, sy = 0, sw = vw, sh = vh;
    if (this.detectZone) {
      // Convert zone from canvas % to video pixels (accounting for letterboxing)
      const topLeft = this.canvasToVideoPixel(this.detectZone.x1, this.detectZone.y1);
      const botRight = this.canvasToVideoPixel(this.detectZone.x2, this.detectZone.y2);
      sx = topLeft.x;
      sy = topLeft.y;
      sw = botRight.x - topLeft.x;
      sh = botRight.y - topLeft.y;
    }

    // Downscale cropped region to max 800px wide
    const scale = Math.min(1, 800 / sw);
    this.scanCanvas.width = Math.round(sw * scale);
    this.scanCanvas.height = Math.round(sh * scale);
    const ctx = this.scanCanvas.getContext("2d");
    ctx.drawImage(this.video, sx, sy, sw, sh, 0, 0, this.scanCanvas.width, this.scanCanvas.height);
    // Use PNG — JPEG destroys thin red circle outlines
    const dataUrl = this.scanCanvas.toDataURL("image/png");
    this.pushEvent("scan_frame", { data: dataUrl });

    // Also capture inventory zone if set
    if (this.invZone) {
      const iTL = this.canvasToVideoPixel(this.invZone.x1, this.invZone.y1);
      const iBR = this.canvasToVideoPixel(this.invZone.x2, this.invZone.y2);
      const isx = iTL.x, isy = iTL.y;
      const isw = iBR.x - iTL.x, ish = iBR.y - iTL.y;
      const iScale = Math.min(1, 800 / isw);
      this.scanCanvas.width = Math.round(isw * iScale);
      this.scanCanvas.height = Math.round(ish * iScale);
      const ictx = this.scanCanvas.getContext("2d");
      ictx.drawImage(this.video, isx, isy, isw, ish, 0, 0, this.scanCanvas.width, this.scanCanvas.height);
      const invDataUrl = this.scanCanvas.toDataURL("image/png");
      this.pushEvent("scan_inventory", { data: invDataUrl });
    }
  },

  draw() {
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;
    ctx.clearRect(0, 0, W, H);

    const placed = this.state.surveys
      .filter(s => s.x_pct != null && s.y_pct != null && !s.collected);
    const route = optimizeRoute(placed);

    // Draw path connecting markers in optimized order
    if (route.length > 1) {
      ctx.beginPath();
      ctx.moveTo((route[0].x_pct / 100) * W, (route[0].y_pct / 100) * H);
      for (let i = 1; i < route.length; i++) {
        ctx.lineTo((route[i].x_pct / 100) * W, (route[i].y_pct / 100) * H);
      }
      ctx.strokeStyle = "rgba(255,255,255,0.5)";
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Draw markers (all placed, including collected)
    const allPlaced = this.state.surveys
      .filter(s => s.x_pct != null && s.y_pct != null);
    for (const s of allPlaced) {
      const x = (s.x_pct / 100) * W;
      const y = (s.y_pct / 100) * H;

      ctx.beginPath();
      ctx.arc(x, y, 10, 0, Math.PI * 2);
      ctx.fillStyle = s.collected ? "rgba(0,200,0,0.55)" : "rgba(0,150,255,0.55)";
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

    // Draw player position marker
    if (this.playerPos) {
      const px = (this.playerPos.x_pct / 100) * W;
      const py = (this.playerPos.y_pct / 100) * H;
      const size = 10;
      ctx.beginPath();
      ctx.moveTo(px, py - size);
      ctx.lineTo(px - size * 0.7, py + size * 0.6);
      ctx.lineTo(px + size * 0.7, py + size * 0.6);
      ctx.closePath();
      ctx.fillStyle = "rgba(255,200,50,0.9)";
      ctx.fill();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Draw detect zone rectangle
    if (this.detectZone) {
      const z = this.detectZone;
      const zx = (z.x1 / 100) * W;
      const zy = (z.y1 / 100) * H;
      const zw = ((z.x2 - z.x1) / 100) * W;
      const zh = ((z.y2 - z.y1) / 100) * H;
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

    // Draw inventory zone rectangle
    if (this.invZone) {
      const z = this.invZone;
      const zx = (z.x1 / 100) * W;
      const zy = (z.y1 / 100) * H;
      const zw = ((z.x2 - z.x1) / 100) * W;
      const zh = ((z.y2 - z.y1) / 100) * H;
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

    // Draw inventory survey number tags
    for (const m of this.invMarkers) {
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

    // Draw first corner marker when setting zone
    if (this.settingZone && this.zoneCorner1) {
      const cx = (this.zoneCorner1.x / 100) * W;
      const cy = (this.zoneCorner1.y / 100) * H;
      ctx.beginPath();
      ctx.arc(cx, cy, 6, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255,255,0,0.9)";
      ctx.fill();
    }

    // Cursor hint
    if (this.settingZone) {
      this.canvas.style.cursor = "crosshair";
    } else if (this.state.placing_survey) {
      this.canvas.style.cursor = "crosshair";
    } else {
      this.canvas.style.cursor = "default";
    }
  },

  destroyed() {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop());
    }
    if (this.scanInterval) {
      clearInterval(this.scanInterval);
    }
  }
};

export default ScreenCapture;
