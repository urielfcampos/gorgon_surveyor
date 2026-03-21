import {
  optimizeRoute,
  drawCollectedSurveys,
  drawUncollectedSurveys,
  drawRoute,
  drawDetectZone,
  drawInventoryZone,
  drawInventoryMarkers,
  drawMotherlode
} from "./canvas_drawing.js";

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
    this.invMarkers = []; // [{x_pct, y_pct, number}]
    this.routeOrder = []; // cached route as array of survey IDs

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

      // Click inside inventory zone = mark inventory item
      if (this.invZone &&
          x_pct >= this.invZone.x1 && x_pct <= this.invZone.x2 &&
          y_pct >= this.invZone.y1 && y_pct <= this.invZone.y2) {
        this.pushEvent("mark_inv_item", { x_pct, y_pct });
        return;
      }

      // Motherlode mode: click places player position for pending reading
      if (this.state.mode === "motherlode" && this.state.motherlode?.pending_meters) {
        this.pushEvent("place_motherlode_reading", { x_pct, y_pct });
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

      if (this.state.mode === "motherlode") return;

      // Find closest inventory marker by distance (tight radius)
      const invThreshold = 1.5; // percent — must be very close
      let closestInv = null;
      let closestInvDist = Infinity;
      for (const m of this.invMarkers) {
        const d = Math.hypot(m.x_pct - x_pct, m.y_pct - y_pct);
        if (d < invThreshold && d < closestInvDist) {
          closestInv = m;
          closestInvDist = d;
        }
      }
      if (closestInv) {
        this.pushEvent("remove_inv_mark", { number: closestInv.number });
        return;
      }

      // Find closest survey marker (toggle collected)
      const surveyThreshold = 3; // percent
      let closestSurvey = null;
      let closestSurveyDist = Infinity;
      for (const s of this.state.surveys.filter(s => s.x_pct != null)) {
        const d = Math.hypot(s.x_pct - x_pct, s.y_pct - y_pct);
        if (d < surveyThreshold && d < closestSurveyDist) {
          closestSurvey = s;
          closestSurveyDist = d;
        }
      }
      if (closestSurvey) {
        this.pushEvent("toggle_collected", { id: closestSurvey.id });
      }
    });

    // Listen for state updates from server
    this.handleEvent("state_updated", (data) => {
      this.state = data;
      this.updateRouteOrder();
      this.draw();
    });

    // Listen for start_capture event from server
    this.handleEvent("start_capture", () => this.startCapture());

    this.handleEvent("stop_capture", () => this.stopCapture());

    this.scanCanvas = document.createElement("canvas");

    this.handleEvent("scan_once", () => {
      console.log("[auto-detect] scan_once triggered (500ms delay)");
      setTimeout(() => this.captureFrame(), 500);
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

  },

  async startCapture() {
    if (this.stream) return;
    try {
      this.stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
      this.stream.addEventListener("inactive", () => {
        this.stopCapture();
        this.pushEvent("stopped_sharing", {});
      });
      this.video.srcObject = this.stream;
      this.video.onloadedmetadata = () => this.resizeCanvas();
      window.addEventListener("resize", () => this.resizeCanvas());
    } catch (err) {
      console.error("Screen capture failed:", err);
    }
  },

  stopCapture() {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop());
      this.stream = null;
    }
    this.video.srcObject = null;
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
  },

  resizeCanvas() {
    this.canvas.width = this.canvas.clientWidth;
    this.canvas.height = this.canvas.clientHeight;
    this.draw();
  },

  updateRouteOrder() {
    const surveys = this.state.surveys || [];

    // Reset if surveys cleared or all IDs changed
    if (surveys.length === 0) {
      this.routeOrder = [];
      return;
    }

    const currentIds = new Set(surveys.map(s => s.id));
    const routeHasValidId = this.routeOrder.some(id => currentIds.has(id));
    if (this.routeOrder.length > 0 && !routeHasValidId) {
      // All IDs changed — new batch
      this.routeOrder = [];
    }

    // Check for newly positioned uncollected surveys not in routeOrder
    const positioned = surveys.filter(s => s.x_pct != null && !s.collected);
    const routeSet = new Set(this.routeOrder);
    const hasNew = positioned.some(s => !routeSet.has(s.id));

    if (hasNew && positioned.length > 0) {
      const route = optimizeRoute(positioned);
      this.routeOrder = route.map(s => s.id);
    }
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

  },

  draw() {
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;
    ctx.clearRect(0, 0, W, H);

    if (this.state.mode === "motherlode") {
      drawMotherlode(ctx, this.state.motherlode, W, H);
      // Still draw zone corner if setting
      if (this.settingZone && this.zoneCorner1) {
        const cx = (this.zoneCorner1.x / 100) * W;
        const cy = (this.zoneCorner1.y / 100) * H;
        ctx.beginPath();
        ctx.arc(cx, cy, 6, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(255,255,0,0.9)";
        ctx.fill();
      }
      // Cursor
      if (this.state.motherlode?.pending_meters) {
        this.canvas.style.cursor = "crosshair";
      } else {
        this.canvas.style.cursor = "default";
      }
      return;
    }

    const allPlaced = this.state.surveys
      .filter(s => s.x_pct != null && s.y_pct != null);
    const collected = allPlaced.filter(s => s.collected);
    const uncollected = allPlaced.filter(s => !s.collected);

    // Pass 1: Draw collected markers (background layer, lower opacity)
    drawCollectedSurveys(ctx, collected, W, H);

    // Draw route path using cached order, filtering out collected surveys
    drawRoute(ctx, this.routeOrder, allPlaced, W, H);

    // Pass 2: Draw uncollected markers (foreground layer, full visibility)
    drawUncollectedSurveys(ctx, uncollected, W, H);

    // Draw detect zone rectangle
    if (this.detectZone) {
      drawDetectZone(ctx, this.detectZone, W, H);
    }

    // Draw inventory zone rectangle
    if (this.invZone) {
      drawInventoryZone(ctx, this.invZone, W, H);
    }

    // Draw inventory survey number tags
    drawInventoryMarkers(ctx, this.invMarkers, W, H);

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
    this.stopCapture();
  }
};

export default ScreenCapture;
