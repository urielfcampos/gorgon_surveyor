const LogStreamer = {
  mounted() {
    this.fileHandle = null;
    this.fileOffset = 0;
    this.pollInterval = null;
    this.statusEl = this.el.querySelector("[data-status]");
    this.pickBtn = this.el.querySelector("[data-pick-file]");
    this.stopBtn = this.el.querySelector("[data-stop-stream]");

    // Hide entire section if browser doesn't support File System Access API
    if (!window.showOpenFilePicker) {
      this.el.style.display = "none";
      return;
    }

    if (this.pickBtn) {
      this.pickBtn.addEventListener("click", () => this.pickFile());
    }

    if (this.stopBtn) {
      this.stopBtn.addEventListener("click", () => this.stopStream());
    }

    this.handleEvent("stop_log_stream_client", () => this.stopStream());
  },

  async pickFile() {
    try {
      const [handle] = await window.showOpenFilePicker({
        types: [{ description: "Log files", accept: { "text/plain": [".log", ".txt"] } }],
        multiple: false
      });

      this.fileHandle = handle;

      // Get initial file size as offset (only send new lines)
      const file = await handle.getFile();
      this.fileOffset = file.size;

      // Tell server to start remote watcher
      this.pushEvent("start_log_stream", {});

      this.setStatus("streaming", `Watching: ${file.name}`);
      this.pickBtn.textContent = "Change File";
      this.pickBtn.classList.add("active");
      this.stopBtn.style.display = "";
      this.startPolling();
    } catch (err) {
      if (err.name !== "AbortError") {
        console.error("File picker error:", err);
        this.setStatus("error", "Failed to open file");
      }
    }
  },

  startPolling() {
    this.stopPolling();
    this.pollInterval = setInterval(() => this.pollFile(), 1000);
  },

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  },

  async pollFile() {
    if (!this.fileHandle) return;

    try {
      const file = await this.fileHandle.getFile();

      if (file.size <= this.fileOffset) return;

      const blob = file.slice(this.fileOffset);
      const text = await blob.text();
      this.fileOffset = file.size;

      if (text.length > 0) {
        this.pushEvent("log_lines", { lines: text });
      }
    } catch (err) {
      console.error("Log poll error:", err);
      if (err.name === "NotAllowedError") {
        this.setStatus("error", "File permission revoked — please re-select");
      } else {
        this.setStatus("error", "Lost access to file");
      }
      this.stopPolling();
    }
  },

  stopStream() {
    this.stopPolling();
    this.fileHandle = null;
    this.fileOffset = 0;
    this.setStatus("idle", "");
    this.pickBtn.textContent = "Select Log File";
    this.pickBtn.classList.remove("active");
    this.stopBtn.style.display = "none";
    this.pushEvent("stop_log_stream", {});
  },

  setStatus(state, message) {
    if (this.statusEl) {
      this.statusEl.textContent = message;
      this.statusEl.dataset.status = state;
    }
  },

  destroyed() {
    this.stopPolling();
  }
};

export default LogStreamer;
