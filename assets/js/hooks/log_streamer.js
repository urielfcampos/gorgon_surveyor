const LogStreamer = {
  mounted() {
    this.fileHandle = null;
    this.file = null;
    this.fileOffset = 0;
    this.pollInterval = null;
    this.useNativeAPI = !!window.showOpenFilePicker;
    this.statusEl = this.el.querySelector("[data-status]");
    this.pickBtn = this.el.querySelector("[data-pick-file]");
    this.stopBtn = this.el.querySelector("[data-stop-stream]");

    if (!this.useNativeAPI) {
      // Create a hidden file input as fallback
      this.fileInput = document.createElement("input");
      this.fileInput.type = "file";
      this.fileInput.accept = ".log,.txt,text/plain";
      this.fileInput.style.display = "none";
      this.el.appendChild(this.fileInput);
      this.fileInput.addEventListener("change", (e) => this.onFallbackFileSelected(e));
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
    if (this.useNativeAPI) {
      await this.pickFileNative();
    } else {
      this.fileInput.click();
    }
  },

  async pickFileNative() {
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

  onFallbackFileSelected(e) {
    const file = e.target.files[0];
    if (!file) return;

    this.file = file;
    this.fileOffset = file.size;

    this.pushEvent("start_log_stream", {});

    this.setStatus("streaming", `Watching: ${file.name} (re-select to refresh)`);
    this.pickBtn.textContent = "Re-select to Refresh";
    this.pickBtn.classList.add("active");
    this.stopBtn.style.display = "";
    this.startPolling();
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
    if (this.useNativeAPI) {
      await this.pollFileNative();
    } else {
      await this.pollFileFallback();
    }
  },

  async pollFileNative() {
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

  async pollFileFallback() {
    // With <input type="file">, the File object is a snapshot from selection time.
    // We can't detect new content by polling. The user must re-select the file
    // to pick up new lines. Polling is a no-op here but kept running so that
    // re-selection (which updates this.file and this.fileOffset) works seamlessly.
    if (!this.file) return;

    try {
      // Attempt to read from offset — in some browsers this may pick up changes
      const blob = this.file.slice(this.fileOffset);
      const text = await blob.text();

      if (text.length > 0) {
        this.fileOffset += text.length;
        this.pushEvent("log_lines", { lines: text });
      }
    } catch (_err) {
      // Silently ignore — user will re-select to refresh
    }
  },

  stopStream() {
    this.stopPolling();
    this.fileHandle = null;
    this.file = null;
    this.fileOffset = 0;
    this.setStatus("idle", "");
    this.pickBtn.textContent = "Select Log File";
    this.pickBtn.classList.remove("active");
    this.stopBtn.style.display = "none";
    if (this.fileInput) this.fileInput.value = "";
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
