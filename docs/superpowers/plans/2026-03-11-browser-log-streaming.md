# Browser Log Streaming Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add browser-based log file streaming as an alternative to local file tailing, using the File System Access API.

**Architecture:** Dual-mode LogWatcher (`:local` / `:remote`), new LogStreamer JS hook for browser file polling, UI toggle in settings tab.

**Tech Stack:** Elixir/Phoenix LiveView, File System Access API (JS), existing WebSocket transport.

---

## Chunk 1: Remote-Mode LogWatcher

### Task 1: Add `ingest_lines/2` to LogWatcher

**Files:**
- Modify: `lib/gorgon_survey/log_watcher.ex`
- Modify: `test/gorgon_survey/log_watcher_test.exs`

- [ ] **Step 1: Write failing test for remote-mode LogWatcher startup**

```elixir
# In test/gorgon_survey/log_watcher_test.exs, add:

describe "remote mode" do
  setup do
    session_id = "remote-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")
    {:ok, session_id: session_id}
  end

  test "starts in remote mode without log path", %{session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)
    state = LogWatcher.get_state(pid)
    assert state.surveys == []
    GenServer.stop(pid)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: FAIL — `start_link` requires `:log_path`

- [ ] **Step 3: Implement dual-mode init in LogWatcher**

In `lib/gorgon_survey/log_watcher.ex`, modify `start_link/1` and add a second `init/1` clause:

```elixir
def start_link(opts) do
  mode = Keyword.get(opts, :mode, :local)
  session_id = Keyword.get(opts, :session_id, "global")
  name = Keyword.get(opts, :name, nil)

  case mode do
    :local ->
      log_path = Keyword.fetch!(opts, :log_path)
      GenServer.start_link(__MODULE__, {:local, log_path, session_id}, name: name)

    :remote ->
      GenServer.start_link(__MODULE__, {:remote, session_id}, name: name)
  end
end
```

Rename existing `init/1` and add remote init. Also update `handle_info` for `:file_event` to guard on local mode (remote-mode state has no `log_path`):

```elixir
@impl true
def init({:local, log_path, session_id}) do
  {:ok, watcher_pid} = FileSystem.start_link(dirs: [Path.dirname(log_path)])
  FileSystem.subscribe(watcher_pid)

  file_size =
    case File.stat(log_path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end

  {:ok,
   %{
     mode: :local,
     app_state: AppState.new(),
     log_path: log_path,
     session_id: session_id,
     watcher_pid: watcher_pid,
     file_offset: file_size
   }}
end

@impl true
def init({:remote, session_id}) do
  {:ok,
   %{
     mode: :remote,
     app_state: AppState.new(),
     session_id: session_id
   }}
end
```

Update the existing `handle_info` for `:file_event` to pattern-match on local mode:

```elixir
@impl true
def handle_info({:file_event, _pid, {path, _events}}, %{mode: :local} = state) do
  if Path.basename(path) == Path.basename(state.log_path) do
    state = read_new_lines(state)
    {:noreply, state}
  else
    {:noreply, state}
  end
end

@impl true
def handle_info({:file_event, _pid, :stop}, state) do
  {:noreply, state}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: ALL PASS

- [ ] **Step 5: Write failing test for `ingest_lines/2`**

```elixir
# Add to the "remote mode" describe block:

test "ingest_lines parses and broadcasts survey lines", %{session_id: session_id} do
  {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)

  LogWatcher.ingest_lines(pid, "The Good Metal Slab is 815m west and 1441m north.\n")

  assert_receive {:state_updated, %GorgonSurvey.AppState{} = app_state}, 1000
  assert length(app_state.surveys) == 1
  [s] = app_state.surveys
  assert s.name == "Good Metal Slab"

  GenServer.stop(pid)
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: FAIL — `ingest_lines/2` undefined

- [ ] **Step 7: Implement `ingest_lines/2`**

Add to the client API section of `lib/gorgon_survey/log_watcher.ex`:

```elixir
def ingest_lines(server, content) do
  GenServer.cast(server, {:ingest_lines, content})
end
```

Add the `handle_cast` clause:

```elixir
@impl true
def handle_cast({:ingest_lines, content}, %{mode: :remote} = state) do
  app_state = process_lines(content, state.app_state)
  broadcast(state.session_id, app_state)
  {:noreply, %{state | app_state: app_state}}
end
```

- [ ] **Step 8: Run all tests to verify they pass**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: ALL PASS

- [ ] **Step 9: Write test for multiple ingestions accumulating state**

```elixir
test "multiple ingest_lines accumulate surveys", %{session_id: session_id} do
  {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)

  LogWatcher.ingest_lines(pid, "The Good Metal Slab is 815m west and 1441m north.\n")
  assert_receive {:state_updated, _}, 1000

  LogWatcher.ingest_lines(pid, "The Amazing Geode is 200m east and 300m south.\n")
  assert_receive {:state_updated, %GorgonSurvey.AppState{} = app_state}, 1000
  assert length(app_state.surveys) == 2

  GenServer.stop(pid)
end
```

- [ ] **Step 10: Run test — should pass with existing implementation**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: ALL PASS

- [ ] **Step 11: Commit**

```bash
git add lib/gorgon_survey/log_watcher.ex test/gorgon_survey/log_watcher_test.exs
git commit -m "feat: add remote mode to LogWatcher with ingest_lines/2"
```

### Task 2: Add `start_remote_watcher/1` to SessionManager

**Files:**
- Modify: `lib/gorgon_survey/session_manager.ex`
- Modify: `test/gorgon_survey/session_manager_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# Add to test/gorgon_survey/session_manager_test.exs, in the "watcher management" describe:

test "start_remote_watcher/1 starts a watcher in remote mode" do
  session_id = "test-#{System.unique_integer([:positive])}"
  SessionManager.register(session_id)

  assert {:ok, pid} = SessionManager.start_remote_watcher(session_id)
  assert is_pid(pid)
  assert Process.alive?(pid)

  # Verify it accepts ingest_lines (remote mode)
  GorgonSurvey.LogWatcher.ingest_lines(pid, "The Good Metal Slab is 100m east and 200m north.\n")
  # No crash = success

  SessionManager.force_cleanup(session_id)
  Process.sleep(100)
  refute Process.alive?(pid)
end

test "start_remote_watcher/1 returns error for unknown session" do
  assert {:error, :unknown_session} = SessionManager.start_remote_watcher("nonexistent")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- mix test test/gorgon_survey/session_manager_test.exs`
Expected: FAIL — `start_remote_watcher/1` undefined

- [ ] **Step 3: Implement `start_remote_watcher/1`**

Add to the client API section of `lib/gorgon_survey/session_manager.ex`:

```elixir
def start_remote_watcher(session_id) do
  GenServer.call(__MODULE__, {:start_remote_watcher, session_id})
end
```

Add the `handle_call` clause:

```elixir
@impl true
def handle_call({:start_remote_watcher, session_id}, _from, state) do
  case Map.get(state.sessions, session_id) do
    nil ->
      {:reply, {:error, :unknown_session}, state}

    session ->
      if session.watcher_pid && Process.alive?(session.watcher_pid) do
        DynamicSupervisor.terminate_child(GorgonSurvey.SessionSupervisor, session.watcher_pid)
      end

      case DynamicSupervisor.start_child(
             GorgonSurvey.SessionSupervisor,
             {GorgonSurvey.LogWatcher,
              mode: :remote,
              session_id: session_id,
              name: {:via, Registry, {GorgonSurvey.SessionRegistry, {:session, session_id}}}}
           ) do
        {:ok, pid} ->
          session = %{session | watcher_pid: pid}
          {:reply, {:ok, pid}, %{state | sessions: Map.put(state.sessions, session_id, session)}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
  end
end
```

- [ ] **Step 4: Run all tests**

Run: `mise exec -- mix test test/gorgon_survey/session_manager_test.exs`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/gorgon_survey/session_manager.ex test/gorgon_survey/session_manager_test.exs
git commit -m "feat: add start_remote_watcher/1 to SessionManager"
```

## Chunk 2: SurveyLive Event Handlers

### Task 3: Add log streaming events to SurveyLive

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.ex`

- [ ] **Step 1: Add `log_mode` assign to mount**

In `lib/gorgon_survey_web/live/survey_live.ex`, add `log_mode: :none` to the `assign` call in `mount/3` (line 18):

```elixir
# Add after the existing assigns:
log_mode: :none,
```

- [ ] **Step 2: Add `"start_log_stream"` event handler**

```elixir
@impl true
def handle_event("start_log_stream", _params, socket) do
  session_id = socket.assigns.session_id

  case GorgonSurvey.SessionManager.start_remote_watcher(session_id) do
    {:ok, pid} ->
      {:noreply, assign(socket, watcher: pid, log_mode: :remote)}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to start stream watcher: #{inspect(reason)}")}
  end
end
```

- [ ] **Step 3: Add `"log_lines"` event handler**

```elixir
@impl true
def handle_event("log_lines", %{"lines" => lines}, socket) do
  if w = watcher(socket) do
    LogWatcher.ingest_lines(w, lines)
  end

  {:noreply, socket}
end
```

- [ ] **Step 4: Add `stop_watcher/1` to SessionManager**

Add to client API in `lib/gorgon_survey/session_manager.ex`:

```elixir
def stop_watcher(session_id) do
  GenServer.call(__MODULE__, {:stop_watcher, session_id})
end
```

Add the `handle_call` clause:

```elixir
@impl true
def handle_call({:stop_watcher, session_id}, _from, state) do
  case Map.get(state.sessions, session_id) do
    nil ->
      {:reply, :ok, state}

    session ->
      if session.watcher_pid && Process.alive?(session.watcher_pid) do
        DynamicSupervisor.terminate_child(GorgonSurvey.SessionSupervisor, session.watcher_pid)
      end

      session = %{session | watcher_pid: nil}
      {:reply, :ok, %{state | sessions: Map.put(state.sessions, session_id, session)}}
  end
end
```

- [ ] **Step 5: Add `"stop_log_stream"` event handler**

```elixir
@impl true
def handle_event("stop_log_stream", _params, socket) do
  GorgonSurvey.SessionManager.stop_watcher(socket.assigns.session_id)
  {:noreply, assign(socket, watcher: nil, log_mode: :none)}
end
```

- [ ] **Step 6: Update `"set_log_folder"` handler to set `log_mode: :local`**

In the existing `handle_event("set_log_folder", ...)` at line 330, update the success branch:

```elixir
{:ok, pid} ->
  {:noreply, assign(socket, watcher: pid, log_mode: :local)}
```

- [ ] **Step 7: Run compile check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Compiles without warnings

- [ ] **Step 8: Commit**

```bash
git add lib/gorgon_survey_web/live/survey_live.ex lib/gorgon_survey/session_manager.ex
git commit -m "feat: add log streaming event handlers to SurveyLive"
```

## Chunk 3: LogStreamer JS Hook

### Task 4: Create LogStreamer JS hook

**Files:**
- Create: `assets/js/hooks/log_streamer.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the LogStreamer hook**

Create `assets/js/hooks/log_streamer.js`:

```javascript
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
```

- [ ] **Step 2: Register LogStreamer hook in app.js**

In `assets/js/app.js`, add after the ScreenCapture import (line 26):

```javascript
import LogStreamer from "./hooks/log_streamer"
```

Update the Hooks object (line 29):

```javascript
const Hooks = { ...colocatedHooks, ScreenCapture, LogStreamer }
```

- [ ] **Step 3: Run compile/build check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Compiles (JS is bundled at runtime by esbuild)

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/log_streamer.js assets/js/app.js
git commit -m "feat: add LogStreamer JS hook for browser file tailing"
```

## Chunk 4: UI Changes

### Task 5: Update settings tab template

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.html.heex`

- [ ] **Step 1: Replace the Log Watcher settings section**

Replace the settings section (lines 83-107) in `lib/gorgon_survey_web/live/survey_live.html.heex`:

Note: The LogStreamer hook div uses `phx-update="ignore"` so LiveView won't re-render it. All UI state (button text, stop button visibility, status) is managed by the JS hook itself. The initial HTML provides the static structure; the hook shows/hides elements dynamically.

```heex
<%= if @sidebar_tab == "settings" do %>
  <div class="settings-section">
    <h3>Log Watcher</h3>

    <div class="log-mode-toggle">
      <span class="log-mode-label">Local File</span>
      <form phx-submit="set_log_folder">
        <input type="text" name="folder" value={@log_folder} placeholder="/path/to/game/logs" />
        <button type="submit">Save & Watch</button>
      </form>
    </div>

    <div class="log-mode-divider">— or —</div>

    <div class="log-mode-toggle" id="log-streamer" phx-hook="LogStreamer" phx-update="ignore">
      <span class="log-mode-label">Stream from Browser</span>
      <p class="hint">
        Pick your chat.log file. New lines are streamed to the server automatically.
        <br /><small>Requires Chrome or Edge.</small>
      </p>
      <button data-pick-file class="detect-btn">Select Log File</button>
      <button data-stop-stream class="detect-btn" style="display:none">Stop Streaming</button>
      <span data-status class="log-stream-status"></span>
    </div>
  </div>

  <div class="settings-section">
    <h3>Auto-Detect</h3>
    <button
      phx-click="toggle_auto_detect_on_survey"
      class={"detect-btn #{if @auto_detect_on_survey, do: "active"}"}
    >
      {if @auto_detect_on_survey,
        do: "Auto-place on survey: ON",
        else: "Auto-place on survey: OFF"}
    </button>
    <p class="hint">
      Automatically scan and place marker when a new survey is detected in the log
    </p>
  </div>
<% end %>
```

- [ ] **Step 2: Run compile check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Compiles without warnings

- [ ] **Step 3: Run full test suite**

Run: `mise exec -- mix test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/gorgon_survey_web/live/survey_live.html.heex
git commit -m "feat: update settings UI with local/stream log watcher options"
```

### Task 6: Manual integration test

- [ ] **Step 1: Start dev server and verify both modes work**

Run: `mise exec -- mix phx.server`

1. Open browser, go to `/`
2. Go to Settings tab
3. Verify "Local File" section shows folder input (existing behavior)
4. Verify "Stream from Browser" section shows file picker button
5. Click "Select Log File", pick a test `.log` file
6. Verify status shows "Watching: filename.log"
7. Append a survey line to the file: `echo "The Good Metal Slab is 100m east and 200m north." >> /path/to/test.log`
8. Verify survey appears in the sidebar within ~1-2 seconds
9. Click "Stop Streaming", verify status resets

- [ ] **Step 2: Final commit with any fixes**

```bash
git add -A
git commit -m "fix: integration polish for browser log streaming"
```
