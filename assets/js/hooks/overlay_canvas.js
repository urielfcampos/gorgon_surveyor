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
      const prevDetect = this.detectZone;
      const prevInv = this.invZone;
      this.detectZone = data.detect_zone;
      this.invZone = data.inv_zone;
      this._doDraw();

      // WebKitGTK transparent windows don't
      // repaint after content is removed (upstream bug).
      // Force compositor invalidation by briefly hiding the canvas.
      const zoneCleared = (prevDetect && !this.detectZone) || (prevInv && !this.invZone);
      if (zoneCleared) {
        this.canvas.style.display = "none";
        void this.canvas.offsetHeight;
        requestAnimationFrame(() => {
          this.canvas.style.display = "block";
          this._doDraw();
        });
      }
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

    // Listen for collect hotkey from Tauri
    if (window.__TAURI__) {
      this._collectUnlisten = window.__TAURI__.event.listen("collect_at_cursor", (e) => {
        if (!this.state) return;
        const { x_pct, y_pct } = e.payload;

        const placed = this.state.surveys.filter((s) => s.x_pct != null && !s.collected);
        let closest = null;
        let closestDist = Infinity;
        for (const s of placed) {
          const d = Math.hypot(s.x_pct - x_pct, s.y_pct - y_pct);
          if (d < closestDist) {
            closestDist = d;
            closest = s;
          }
        }
        if (closest && closestDist < 3) {
          this.pushEvent("toggle_collected", { id: closest.id });
        }
      });
    }

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

    // Track cursor position for global hotkey collection
    this._cursorPct = { x: 0, y: 0 };
    window.addEventListener("mousemove", (e) => {
      this._cursorPct = {
        x: (e.clientX / window.innerWidth) * 100,
        y: (e.clientY / window.innerHeight) * 100
      };
    });

    // Right-click to toggle collected
    this.canvas.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;
      this._toggleClosestSurvey(x_pct, y_pct);
    });

    // Expose for Tauri hotkey via eval
    const hook = this;
    window._collectNearest = () => {
      hook._markInvAtCursor(hook._cursorPct.x, hook._cursorPct.y);
    };
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this._collectUnlisten) {
      this._collectUnlisten.then(fn => fn());
    }
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

  _markInvAtCursor(x_pct, y_pct) {
    this.pushEvent("mark_inv_item", { x_pct: x_pct, y_pct: y_pct });
  },

  _toggleClosestSurvey(x_pct, y_pct) {
    if (!this.state) return;
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
    if (closest && closestDist < 3) {
      this.pushEvent("toggle_collected", { id: closest.id });
    }
  },

  _draw() {
    this._doDraw();
  },

  _doDraw() {
    const W = this.canvas.width;
    const H = this.canvas.height;
    const ctx = this.ctx;

    // Clear to fully transparent using composite "copy" —
    // replaces all pixels including alpha, which triggers
    // WebKitGTK's damage tracking more reliably than buffer reset
    ctx.save();
    ctx.globalCompositeOperation = "copy";
    ctx.fillStyle = "rgba(0,0,0,0)";
    ctx.fillRect(0, 0, W, H);
    ctx.restore();

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
