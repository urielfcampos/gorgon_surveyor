import {
  optimizeRoute,
  drawCollectedSurveys,
  drawUncollectedSurveys,
  drawRoute,
  drawDetectZone,
  drawInventoryZone,
  drawInventoryMarkers,
  drawMotherlode
} from "./canvas_drawing";

const OverlayCanvas = {
  mounted() {
    this.state = null;
    this.detectZone = null;
    this.invZone = null;
    this.invMarkers = [];
    this.routeOrder = [];
    this.settingZone = false; // "map" or "inv" or false
    this.zoneCorner1 = null;

    // Create fullscreen canvas
    this.canvas = document.createElement("canvas");
    this.canvas.style.cssText =
      "position:fixed;top:0;left:0;width:100vw;height:100vh;cursor:crosshair;";
    this.el.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d");

    this._resize();
    this._resizeHandler = () => this._resize();
    window.addEventListener("resize", this._resizeHandler);

    // LiveView event listeners
    this.handleEvent("state_updated", (state) => {
      console.log("[overlay] state_updated:", state.surveys?.length, "surveys");
      this.state = state;
      this._updateRoute();
      this._draw();
    });

    this.handleEvent("zones_updated", (data) => {
      console.log("[overlay] zones_updated:", JSON.stringify(data));
      this.detectZone = data.detect_zone;
      this.invZone = data.inv_zone;
      // Call _doDraw directly — rAF may not fire on click-through windows
      this._doDraw();
    });

    this.handleEvent("inv_markers", (data) => {
      this.invMarkers = data.markers || [];
      this._draw();
    });

    this.handleEvent("set_interactive", (data) => {
      this.canvas.style.pointerEvents = data.interactive ? "auto" : "none";
    });

    this.handleEvent("start_set_zone", (data) => {
      // Auto-enable interaction when zone setting starts
      this.canvas.style.pointerEvents = "auto";
      this.settingZone = data.zone_type; // "map" or "inv"
      this.zoneCorner1 = null;
      this.canvas.style.cursor = "crosshair";
    });

    // Click handler: zone setting > survey placement > inventory marking
    this.canvas.addEventListener("click", (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;

      // Zone setting mode
      if (this.settingZone) {
        if (!this.zoneCorner1) {
          this.zoneCorner1 = { x: x_pct, y: y_pct };
          return;
        }
        const zone = {
          x1: Math.min(this.zoneCorner1.x, x_pct),
          y1: Math.min(this.zoneCorner1.y, y_pct),
          x2: Math.max(this.zoneCorner1.x, x_pct),
          y2: Math.max(this.zoneCorner1.y, y_pct)
        };
        const eventName = this.settingZone === "map" ? "set_detect_zone" : "set_inv_zone";
        this.pushEvent(eventName, zone);
        this.settingZone = false;
        this.zoneCorner1 = null;
        this.canvas.style.cursor = "default";
        return;
      }

      // Survey placement
      if (this.state && this.state.placing_survey) {
        this.pushEvent("place_survey", {
          id: this.state.placing_survey,
          x_pct: x_pct,
          y_pct: y_pct
        });
        return;
      }
    });

    // Right-click to toggle collected
    this.canvas.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      if (!this.state) return;
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;

      const placed = this.state.surveys.filter((s) => s.x_pct != null);
      let closest = null;
      let closestDist = Infinity;
      for (const s of placed) {
        const d = Math.hypot(s.x_pct - x_pct, s.y_pct - y_pct);
        if (d < closestDist) {
          closestDist = d;
          closest = s;
        }
      }
      // Only toggle if within reasonable distance (3% of canvas)
      if (closest && closestDist < 3) {
        this.pushEvent("toggle_collected", { id: closest.id });
      }
    });
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
  },

  _resize() {
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
    this._draw();
  },

  _updateRoute() {
    if (!this.state) return;
    const placed = this.state.surveys.filter(
      (s) => s.x_pct != null && !s.collected
    );
    const optimized = optimizeRoute(placed);
    this.routeOrder = optimized.map((s) => s.id);
  },

  _draw() {
    this._doDraw();
  },

  _doDraw() {
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;

    ctx.clearRect(0, 0, W, H);

    // Draw zones even if state hasn't arrived yet
    if (this.detectZone) {
      drawDetectZone(ctx, this.detectZone, W, H);
    }
    if (this.invZone) {
      drawInventoryZone(ctx, this.invZone, W, H);
    }

    if (!this.state) return;

    const placed = this.state.surveys.filter((s) => s.x_pct != null);
    const collected = placed.filter((s) => s.collected);
    const uncollected = placed.filter((s) => !s.collected);

    drawCollectedSurveys(ctx, collected, W, H);
    drawRoute(ctx, this.routeOrder, placed, W, H);
    drawUncollectedSurveys(ctx, uncollected, W, H);

    if (this.invMarkers.length > 0) {
      drawInventoryMarkers(ctx, this.invMarkers, W, H);
    }

    if (this.state.mode === "motherlode") {
      drawMotherlode(ctx, this.state.motherlode, W, H);
    }
  }
};

export default OverlayCanvas;
