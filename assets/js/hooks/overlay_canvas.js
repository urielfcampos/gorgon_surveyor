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
      this.state = state;
      this._updateRoute();
      this._draw();
    });

    this.handleEvent("zones_updated", (data) => {
      this.detectZone = data.detect_zone;
      this.invZone = data.inv_zone;
      this._draw();
    });

    this.handleEvent("inv_markers", (data) => {
      this.invMarkers = data.markers || [];
      this._draw();
    });

    // Click to place survey
    this.canvas.addEventListener("click", (e) => {
      if (!this.state || !this.state.placing_survey) return;
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;
      this.pushEvent("place_survey", {
        id: this.state.placing_survey,
        x_pct: x_pct,
        y_pct: y_pct
      });
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
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;

    ctx.clearRect(0, 0, W, H);

    if (!this.state) return;

    const placed = this.state.surveys.filter((s) => s.x_pct != null);
    const collected = placed.filter((s) => s.collected);
    const uncollected = placed.filter((s) => !s.collected);

    // Draw layers in order: zones, collected (background), route, uncollected (foreground)
    if (this.detectZone) {
      drawDetectZone(ctx, this.detectZone, W, H);
    }
    if (this.invZone) {
      drawInventoryZone(ctx, this.invZone, W, H);
    }

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
