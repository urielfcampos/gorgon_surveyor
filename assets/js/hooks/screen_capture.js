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

    // Observe data-sharing attribute changes
    this._observer = new MutationObserver(() => this.maybeStartCapture());
    this._observer.observe(this.el, { attributes: true });
    this.maybeStartCapture();
  },

  async maybeStartCapture() {
    if (this.el.dataset.sharing !== "true" || this.stream) return;
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

    for (const s of this.state.surveys) {
      if (s.x_pct == null || s.y_pct == null) continue;
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
    this._observer.disconnect();
  }
};

export default ScreenCapture;
