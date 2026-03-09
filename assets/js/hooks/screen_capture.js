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

    // Handle canvas clicks for survey placement
    this.canvas.addEventListener("click", (e) => {
      if (!this.state.placing_survey) return;
      const rect = this.canvas.getBoundingClientRect();
      const x_pct = ((e.clientX - rect.left) / rect.width) * 100;
      const y_pct = ((e.clientY - rect.top) / rect.height) * 100;
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
      ctx.arc(x, y, 12, 0, Math.PI * 2);
      ctx.fillStyle = s.collected ? "rgba(0,200,0,0.8)" : "rgba(0,150,255,0.8)";
      ctx.fill();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 2;
      ctx.stroke();

      ctx.fillStyle = "#fff";
      ctx.font = "bold 10px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(s.survey_number), x, y);
    }

    // Placement cursor hint
    if (this.state.placing_survey) {
      this.canvas.style.cursor = "crosshair";
    } else {
      this.canvas.style.cursor = "default";
    }
  },

  destroyed() {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop());
    }
  }
};

export default ScreenCapture;
