# Phoenix LiveView Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild gorgon-survey as an Elixir/Phoenix LiveView app with browser screen capture and canvas overlay.

**Architecture:** GenServer tails game log and broadcasts parsed events via PubSub. Single LiveView page renders video mirror + canvas overlay via JS hooks. User clicks canvas to place survey markers.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.5, LiveView, file_system hex package, ExUnit. No database.

---

### Task 1: Scaffold Phoenix Project

**Files:**
- Create: entire Phoenix project at repo root

**Step 1: Generate Phoenix project without Ecto (no database)**

Run:
```bash
cd /home/urielfcampos/projects/gorgon-survey
mise exec -- mix phx.new . --app gorgon_survey --no-ecto --no-install
```

Accept overwrites if prompted (repo is empty except docs/).

**Step 2: Create .mise.toml for the project**

Create `.mise.toml`:
```toml
[tools]
elixir = "1.18.4-otp-28"
erlang = "28.0.2"
node = "24.6.0"
```

**Step 3: Install dependencies**

Run:
```bash
mise exec -- mix deps.get
mise exec -- mix deps.compile
```

**Step 4: Add file_system dependency**

In `mix.exs`, add to `deps`:
```elixir
{:file_system, "~> 1.0"}
```

Run:
```bash
mise exec -- mix deps.get
```

**Step 5: Verify it compiles and default tests pass**

Run:
```bash
mise exec -- mix compile
mise exec -- mix test
```

Expected: All default Phoenix tests pass.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold Phoenix LiveView project with file_system dep"
```

---

### Task 2: Log Parser Module

**Files:**
- Create: `lib/gorgon_survey/log_parser.ex`
- Test: `test/gorgon_survey/log_parser_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule GorgonSurvey.LogParserTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.LogParser

  describe "parse_line/1" do
    test "parses survey with west and north" do
      line = "The Good Metal Slab is 815m west and 1441m north."
      assert {:survey, %{name: "Good Metal Slab", dx: -815, dy: 1441}} = LogParser.parse_line(line)
    end

    test "parses survey with east and south" do
      line = "The Fine Gravel Patch is 200m east and 300m south."
      assert {:survey, %{name: "Fine Gravel Patch", dx: 200, dy: -300}} = LogParser.parse_line(line)
    end

    test "parses motherlode distance" do
      line = "The treasure is 1000 meters away"
      assert {:motherlode, %{meters: 1000}} = LogParser.parse_line(line)
    end

    test "parses survey collected" do
      line = "You collected the survey reward"
      assert :survey_collected = LogParser.parse_line(line)
    end

    test "returns nil for unrelated lines" do
      assert nil == LogParser.parse_line("Hello world")
      assert nil == LogParser.parse_line("")
    end

    test "motherlode checked before survey to avoid false match" do
      line = "The treasure is 500 meters away"
      assert {:motherlode, %{meters: 500}} = LogParser.parse_line(line)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey/log_parser_test.exs`
Expected: FAIL — module not found

**Step 3: Implement LogParser**

```elixir
defmodule GorgonSurvey.LogParser do
  @moduledoc "Parses Project Gorgon chat log lines into structured events."

  @survey_regex ~r/The (.+?) is (\d+)m (east|west) and (\d+)m (north|south)\./E
  @motherlode_regex ~r/The treasure is (\d+) meters away/E
  @collected_regex ~r/You collected the survey reward/E

  def parse_line(line) do
    cond do
      match = Regex.run(@motherlode_regex, line) ->
        [_, meters] = match
        {:motherlode, %{meters: String.to_integer(meters)}}

      match = Regex.run(@survey_regex, line) ->
        [_, name, dist1, dir1, dist2, dir2] = match
        dx = directional_value(String.to_integer(dist1), dir1)
        dy = directional_value(String.to_integer(dist2), dir2)
        {:survey, %{name: name, dx: dx, dy: dy}}

      Regex.match?(@collected_regex, line) ->
        :survey_collected

      true ->
        nil
    end
  end

  defp directional_value(val, "east"), do: val
  defp directional_value(val, "west"), do: -val
  defp directional_value(val, "north"), do: val
  defp directional_value(val, "south"), do: -val
end
```

**Step 4: Run tests to verify they pass**

Run: `mise exec -- mix test test/gorgon_survey/log_parser_test.exs`
Expected: 6 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/gorgon_survey/log_parser.ex test/gorgon_survey/log_parser_test.exs
git commit -m "feat: add log parser for survey, motherlode, and collected events"
```

---

### Task 3: AppState Module

**Files:**
- Create: `lib/gorgon_survey/app_state.ex`
- Test: `test/gorgon_survey/app_state_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule GorgonSurvey.AppStateTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.AppState

  test "new/0 returns empty state" do
    state = AppState.new()
    assert state.surveys == []
    assert state.motherlode == %{readings: [], estimated_location: nil}
    assert state.zone == nil
    assert state.route_order == []
  end

  test "add_survey/2 adds a survey with incrementing number" do
    state = AppState.new()
    state = AppState.add_survey(state, %{name: "Good Metal Slab", dx: -815, dy: 1441})
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.survey_number == 1
    assert s.name == "Good Metal Slab"
    assert s.x_pct == nil
  end

  test "place_survey/3 sets coordinates" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "Slab", dx: 0, dy: 0})

    [survey] = state.surveys
    state = AppState.place_survey(state, survey.id, 50.5, 30.2)
    [placed] = state.surveys
    assert placed.x_pct == 50.5
    assert placed.y_pct == 30.2
  end

  test "toggle_collected/2 flips collected flag" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "Slab", dx: 0, dy: 0})

    [survey] = state.surveys
    assert survey.collected == false
    state = AppState.toggle_collected(state, survey.id)
    [toggled] = state.surveys
    assert toggled.collected == true
  end

  test "clear_surveys/1 removes all surveys" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "A", dx: 0, dy: 0})
      |> AppState.add_survey(%{name: "B", dx: 1, dy: 1})
      |> AppState.clear_surveys()

    assert state.surveys == []
  end

  test "add_motherlode_reading/2 appends reading" do
    state =
      AppState.new()
      |> AppState.add_motherlode_reading(%{x_pct: 50.0, y_pct: 50.0, meters: 1000})

    assert length(state.motherlode.readings) == 1
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey/app_state_test.exs`
Expected: FAIL — module not found

**Step 3: Implement AppState**

```elixir
defmodule GorgonSurvey.AppState do
  @moduledoc "Pure data structure and functions for application state."

  defstruct surveys: [],
            motherlode: %{readings: [], estimated_location: nil},
            zone: nil,
            route_order: [],
            next_id: 1,
            next_number: 1

  def new, do: %__MODULE__{}

  def add_survey(state, %{name: name, dx: dx, dy: dy}) do
    survey = %{
      id: state.next_id,
      survey_number: state.next_number,
      name: name,
      dx: dx,
      dy: dy,
      x_pct: nil,
      y_pct: nil,
      collected: false
    }

    %{state | surveys: state.surveys ++ [survey], next_id: state.next_id + 1, next_number: state.next_number + 1}
  end

  def place_survey(state, id, x_pct, y_pct) do
    surveys =
      Enum.map(state.surveys, fn
        %{id: ^id} = s -> %{s | x_pct: x_pct, y_pct: y_pct}
        s -> s
      end)

    %{state | surveys: surveys}
  end

  def toggle_collected(state, id) do
    surveys =
      Enum.map(state.surveys, fn
        %{id: ^id} = s -> %{s | collected: !s.collected}
        s -> s
      end)

    %{state | surveys: surveys}
  end

  def clear_surveys(state) do
    %{state | surveys: [], next_number: 1}
  end

  def add_motherlode_reading(state, reading) do
    readings = state.motherlode.readings ++ [reading]
    motherlode = %{state.motherlode | readings: readings}
    %{state | motherlode: motherlode}
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mise exec -- mix test test/gorgon_survey/app_state_test.exs`
Expected: 6 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/gorgon_survey/app_state.ex test/gorgon_survey/app_state_test.exs
git commit -m "feat: add AppState data structure with survey and motherlode management"
```

---

### Task 4: LogWatcher GenServer

**Files:**
- Create: `lib/gorgon_survey/log_watcher.ex`
- Test: `test/gorgon_survey/log_watcher_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule GorgonSurvey.LogWatcherTest do
  use ExUnit.Case

  alias GorgonSurvey.LogWatcher

  setup do
    # Create a temp log file
    tmp_dir = System.tmp_dir!()
    log_path = Path.join(tmp_dir, "test_chat_#{:rand.uniform(100_000)}.log")
    File.write!(log_path, "")
    on_exit(fn -> File.rm(log_path) end)

    # Subscribe to PubSub for state updates
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")

    {:ok, log_path: log_path}
  end

  test "starts and returns initial state", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    state = LogWatcher.get_state(pid)
    assert state.surveys == []
    GenServer.stop(pid)
  end

  test "detects new survey line appended to log", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    File.write!(log_path, "The Good Metal Slab is 815m west and 1441m north.\n", [:append])
    # Give file watcher time to detect
    Process.sleep(500)
    state = LogWatcher.get_state(pid)
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.name == "Good Metal Slab"
    GenServer.stop(pid)
  end

  test "broadcasts state updates via PubSub", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    assert_receive {:state_updated, %GorgonSurvey.AppState{}}, 2000
    GenServer.stop(pid)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: FAIL — module not found

**Step 3: Implement LogWatcher**

```elixir
defmodule GorgonSurvey.LogWatcher do
  @moduledoc "GenServer that tails the game chat log and maintains app state."

  use GenServer

  alias GorgonSurvey.{AppState, LogParser}

  # Client API

  def start_link(opts) do
    log_path = Keyword.fetch!(opts, :log_path)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, log_path, name: name)
  end

  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  def place_survey(server \\ __MODULE__, id, x_pct, y_pct) do
    GenServer.cast(server, {:place_survey, id, x_pct, y_pct})
  end

  def toggle_collected(server \\ __MODULE__, id) do
    GenServer.cast(server, {:toggle_collected, id})
  end

  def clear_surveys(server \\ __MODULE__) do
    GenServer.cast(server, :clear_surveys)
  end

  def set_zone(server \\ __MODULE__, zone) do
    GenServer.cast(server, {:set_zone, zone})
  end

  def add_motherlode_reading(server \\ __MODULE__, reading) do
    GenServer.cast(server, {:add_motherlode_reading, reading})
  end

  # Server callbacks

  @impl true
  def init(log_path) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [Path.dirname(log_path)])
    FileSystem.subscribe(watcher_pid)

    # Seek to end — only process new lines
    file_size = case File.stat(log_path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end

    {:ok, %{
      app_state: AppState.new(),
      log_path: log_path,
      watcher_pid: watcher_pid,
      file_offset: file_size
    }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.app_state, state}
  end

  @impl true
  def handle_cast({:place_survey, id, x_pct, y_pct}, state) do
    app_state = AppState.place_survey(state.app_state, id, x_pct, y_pct)
    state = %{state | app_state: app_state}
    broadcast(app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:toggle_collected, id}, state) do
    app_state = AppState.toggle_collected(state.app_state, id)
    state = %{state | app_state: app_state}
    broadcast(app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear_surveys, state) do
    app_state = AppState.clear_surveys(state.app_state)
    state = %{state | app_state: app_state}
    broadcast(app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_zone, zone}, state) do
    app_state = %{state.app_state | zone: zone}
    state = %{state | app_state: app_state}
    broadcast(app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_motherlode_reading, reading}, state) do
    app_state = AppState.add_motherlode_reading(state.app_state, reading)
    state = %{state | app_state: app_state}
    broadcast(app_state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
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

  defp read_new_lines(state) do
    case File.open(state.log_path, [:read]) do
      {:ok, file} ->
        :file.position(file, state.file_offset)
        new_content = IO.read(file, :eof)
        File.close(file)

        case new_content do
          :eof ->
            state

          content when is_binary(content) and byte_size(content) > 0 ->
            new_offset = state.file_offset + byte_size(content)
            app_state = process_lines(content, state.app_state)
            broadcast(app_state)
            %{state | file_offset: new_offset, app_state: app_state}

          _ ->
            state
        end

      _ ->
        state
    end
  end

  defp process_lines(content, app_state) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(app_state, fn line, acc ->
      case LogParser.parse_line(line) do
        {:survey, data} -> AppState.add_survey(acc, data)
        {:motherlode, _data} -> acc
        :survey_collected -> acc
        nil -> acc
      end
    end)
  end

  defp broadcast(app_state) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "game_state", {:state_updated, app_state})
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: 3 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/gorgon_survey/log_watcher.ex test/gorgon_survey/log_watcher_test.exs
git commit -m "feat: add LogWatcher GenServer with file tailing and PubSub broadcast"
```

---

### Task 5: LiveView Page with Sidebar

**Files:**
- Modify: `lib/gorgon_survey_web/router.ex`
- Create: `lib/gorgon_survey_web/live/survey_live.ex`
- Create: `lib/gorgon_survey_web/live/survey_live.html.heex`
- Test: `test/gorgon_survey_web/live/survey_live_test.exs`

**Step 1: Write failing test**

```elixir
defmodule GorgonSurveyWeb.SurveyLiveTest do
  use GorgonSurveyWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    # Start a LogWatcher with empty temp log
    tmp = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.log")
    File.write!(tmp, "")
    {:ok, pid} = GorgonSurvey.LogWatcher.start_link(log_path: tmp, name: GorgonSurvey.LogWatcher)
    on_exit(fn ->
      GenServer.stop(pid)
      File.rm(tmp)
    end)
    :ok
  end

  test "renders page with share screen button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
    assert html =~ "Surveys"
  end

  test "displays survey when state updates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Simulate a survey arriving
    new_state = GorgonSurvey.AppState.new()
      |> GorgonSurvey.AppState.add_survey(%{name: "Good Metal Slab", dx: -815, dy: 1441})
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "game_state", {:state_updated, new_state})

    # LiveView should re-render with the survey
    html = render(view)
    assert html =~ "Good Metal Slab"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey_web/live/survey_live_test.exs`
Expected: FAIL

**Step 3: Update router**

In `lib/gorgon_survey_web/router.ex`, replace the default `"/"` route in the browser scope:

```elixir
live "/", SurveyLive
```

Remove the default `PageController` route if present.

**Step 4: Create LiveView module**

```elixir
defmodule GorgonSurveyWeb.SurveyLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
    end

    state = LogWatcher.get_state()

    {:ok, assign(socket,
      app_state: state,
      sharing: false,
      placing_survey: nil
    )}
  end

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    socket = assign(socket, app_state: app_state)
    socket = push_event(socket, "state_updated", serialize_state(app_state))

    # If a new unplaced survey arrived, prompt placement
    unplaced = Enum.find(app_state.surveys, &is_nil(&1.x_pct))
    socket = if unplaced && socket.assigns.placing_survey == nil do
      assign(socket, placing_survey: unplaced.id)
    else
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    LogWatcher.place_survey(id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    LogWatcher.toggle_collected(id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    LogWatcher.clear_surveys()
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_sharing", _params, socket) do
    {:noreply, assign(socket, sharing: true)}
  end

  defp serialize_state(app_state) do
    %{
      surveys: Enum.map(app_state.surveys, fn s ->
        %{id: s.id, survey_number: s.survey_number, name: s.name,
          dx: s.dx, dy: s.dy, x_pct: s.x_pct, y_pct: s.y_pct,
          collected: s.collected}
      end),
      placing_survey: nil
    }
  end
end
```

**Step 5: Create template**

Create `lib/gorgon_survey_web/live/survey_live.html.heex`:

```heex
<div class="app-layout">
  <main class="main-area">
    <div id="screen-capture" phx-hook="ScreenCapture" data-sharing={to_string(@sharing)}>
      <%= unless @sharing do %>
        <button phx-click="start_sharing" class="share-btn">Share Screen</button>
      <% end %>
    </div>

    <%= if @placing_survey do %>
      <div class="placement-prompt">
        Click on the map to place survey
      </div>
    <% end %>
  </main>

  <aside class="sidebar">
    <h2>Surveys</h2>

    <div class="survey-list">
      <%= for survey <- @app_state.surveys do %>
        <div class={"survey-item #{if survey.collected, do: "collected"}"}>
          <span class="survey-num"><%= survey.survey_number %></span>
          <span class="survey-name"><%= survey.name %></span>
          <span class="survey-offset"><%= survey.dx %>, <%= survey.dy %></span>
          <button phx-click="toggle_collected" phx-value-id={survey.id}>
            <%= if survey.collected, do: "Undo", else: "Done" %>
          </button>
        </div>
      <% end %>
    </div>

    <button phx-click="clear_surveys" class="clear-btn">Clear All</button>
  </aside>
</div>
```

**Step 6: Run tests to verify they pass**

Run: `mise exec -- mix test test/gorgon_survey_web/live/survey_live_test.exs`
Expected: 2 tests, 0 failures

**Step 7: Commit**

```bash
git add lib/gorgon_survey_web/live/ lib/gorgon_survey_web/router.ex test/gorgon_survey_web/live/
git commit -m "feat: add SurveyLive page with sidebar and PubSub integration"
```

---

### Task 6: Screen Capture JS Hook

**Files:**
- Create: `assets/js/hooks/screen_capture.js`
- Modify: `assets/js/app.js` (register hook)

**Step 1: Create the ScreenCapture hook**

```javascript
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
```

**Step 2: Register hook in app.js**

In `assets/js/app.js`, add:

```javascript
import ScreenCapture from "./hooks/screen_capture";

let Hooks = { ScreenCapture };
// Pass Hooks to LiveSocket constructor
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
});
```

**Step 3: Verify manually**

Run: `mise exec -- mix phx.server`
Open `http://localhost:4000` — should see Share Screen button. Click it, select game window, see mirrored video.

**Step 4: Commit**

```bash
git add assets/js/hooks/screen_capture.js assets/js/app.js
git commit -m "feat: add ScreenCapture JS hook with canvas overlay and click-to-place"
```

---

### Task 7: CSS Layout

**Files:**
- Modify: `assets/css/app.css`

**Step 1: Add layout styles**

Append to `assets/css/app.css`:

```css
.app-layout {
  display: flex;
  height: 100vh;
  overflow: hidden;
  background: #1a1a2e;
  color: #eee;
}

.main-area {
  flex: 1;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #000;
}

#screen-capture {
  width: 100%;
  height: 100%;
  position: relative;
}

.share-btn {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  padding: 16px 32px;
  font-size: 18px;
  background: #3a86ff;
  color: #fff;
  border: none;
  border-radius: 8px;
  cursor: pointer;
}

.share-btn:hover {
  background: #2a76ef;
}

.placement-prompt {
  position: absolute;
  top: 16px;
  left: 50%;
  transform: translateX(-50%);
  background: rgba(0, 100, 200, 0.85);
  color: #fff;
  padding: 8px 16px;
  border-radius: 6px;
  font-weight: bold;
  z-index: 10;
  pointer-events: none;
}

.sidebar {
  width: 280px;
  padding: 16px;
  background: #16213e;
  overflow-y: auto;
  border-left: 1px solid #333;
}

.sidebar h2 {
  margin: 0 0 12px;
  font-size: 16px;
}

.survey-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 12px;
}

.survey-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 8px;
  background: #1a1a3e;
  border-radius: 4px;
  font-size: 13px;
}

.survey-item.collected {
  opacity: 0.5;
}

.survey-num {
  background: #3a86ff;
  color: #fff;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: bold;
  flex-shrink: 0;
}

.survey-name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.survey-offset {
  color: #888;
  font-size: 11px;
}

.clear-btn {
  width: 100%;
  padding: 6px;
  background: #a22;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

.clear-btn:hover {
  background: #c33;
}
```

**Step 2: Verify visually**

Run: `mise exec -- mix phx.server`
Check layout at `http://localhost:4000`.

**Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "feat: add app layout CSS for sidebar and screen capture area"
```

---

### Task 8: Wire LogWatcher into Application Supervision Tree

**Files:**
- Modify: `lib/gorgon_survey/application.ex`
- Create: `config/runtime.exs` (or modify existing)

**Step 1: Add LogWatcher to supervision tree**

In `lib/gorgon_survey/application.ex`, add LogWatcher as a child. It should only start if a log folder is configured.

```elixir
# In children list, after PubSub:
children = [
  GorgonSurveyWeb.Telemetry,
  {Phoenix.PubSub, name: GorgonSurvey.PubSub},
  # Only start LogWatcher if log_folder is configured
  log_watcher_child_spec(),
  GorgonSurveyWeb.Endpoint
] |> Enum.reject(&is_nil/1)
```

Add helper function:

```elixir
defp log_watcher_child_spec do
  log_folder = Application.get_env(:gorgon_survey, :log_folder)
  if log_folder && log_folder != "" do
    log_path = find_latest_log(log_folder)
    if log_path do
      {GorgonSurvey.LogWatcher, log_path: log_path}
    end
  end
end

defp find_latest_log(folder) do
  folder
  |> Path.join("*.log")
  |> Path.wildcard()
  |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
  |> List.first()
end
```

**Step 2: Add config**

In `config/config.exs`, add:

```elixir
config :gorgon_survey, :log_folder, ""
```

Users will set this via the UI (Task 9) or edit config directly.

**Step 3: Run tests**

Run: `mise exec -- mix test`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add lib/gorgon_survey/application.ex config/config.exs
git commit -m "feat: add LogWatcher to supervision tree with configurable log folder"
```

---

### Task 9: Settings — Log Folder Configuration via LiveView

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.ex`
- Modify: `lib/gorgon_survey_web/live/survey_live.html.heex`
- Create: `lib/gorgon_survey/config_store.ex`

**Step 1: Create a simple config persistence module**

```elixir
defmodule GorgonSurvey.ConfigStore do
  @moduledoc "Persists settings to a JSON file."

  @config_dir Path.join(System.user_home!(), ".config/gorgon-survey")
  @config_path Path.join(@config_dir, "settings.json")

  def load do
    case File.read(@config_path) do
      {:ok, content} -> Jason.decode!(content)
      _ -> %{}
    end
  end

  def save(config) when is_map(config) do
    File.mkdir_p!(@config_dir)
    File.write!(@config_path, Jason.encode!(config, pretty: true))
  end

  def get(key, default \\ nil) do
    load() |> Map.get(key, default)
  end

  def put(key, value) do
    config = load() |> Map.put(key, value)
    save(config)
    config
  end
end
```

**Step 2: Add settings panel to template**

Add to the sidebar in `survey_live.html.heex`:

```heex
<div class="settings-section">
  <h3>Settings</h3>
  <form phx-submit="set_log_folder">
    <label>Log Folder</label>
    <input type="text" name="folder" value={@log_folder} placeholder="/path/to/game/logs" />
    <button type="submit">Save & Watch</button>
  </form>
</div>
```

**Step 3: Handle the event in LiveView**

Add to `survey_live.ex`:

```elixir
def handle_event("set_log_folder", %{"folder" => folder}, socket) do
  GorgonSurvey.ConfigStore.put("log_folder", folder)
  # Restart LogWatcher with new path (Task 10 will handle dynamic restart)
  {:noreply, assign(socket, log_folder: folder)}
end
```

Update `mount` to load saved config:

```elixir
log_folder = GorgonSurvey.ConfigStore.get("log_folder", "")
```

**Step 4: Run tests**

Run: `mise exec -- mix test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/gorgon_survey/config_store.ex lib/gorgon_survey_web/live/
git commit -m "feat: add settings panel with log folder configuration"
```

---

### Task 10: CLAUDE.md and Final Wiring

**Files:**
- Create: `CLAUDE.md`

**Step 1: Write CLAUDE.md**

```markdown
# CLAUDE.md

## Tool Management

All commands must be prefixed with `mise exec --`. Tools (Elixir, Erlang, Node) are managed via `.mise.toml`.

## Commands

```bash
# Install dependencies
mise exec -- mix deps.get

# Dev server (hot-reload)
mise exec -- mix phx.server

# Interactive console
mise exec -- iex -S mix phx.server

# Run all tests
mise exec -- mix test

# Run specific test file
mise exec -- mix test test/gorgon_survey/log_parser_test.exs

# Compile check
mise exec -- mix compile --warnings-as-errors
```

## Architecture

Phoenix LiveView app running locally as a game companion. Single page at `/`.

### Data Flow

```
chat.log → LogWatcher GenServer → PubSub → LiveView → JS Hook → canvas
```

### Key Modules

| Module | Responsibility |
|---|---|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into events |
| `GorgonSurvey.AppState` | Pure state struct with survey/motherlode management |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file, maintains state, broadcasts via PubSub |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json` |
| `GorgonSurveyWeb.SurveyLive` | LiveView page — sidebar + screen capture area |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place |

### Frontend

- Screen capture via `getDisplayMedia` API
- Canvas overlay for survey markers drawn over mirrored video
- Click to place surveys, right-click to toggle collected
- State pushed from server via LiveView `push_event`
```

**Step 2: Run full test suite**

Run: `mise exec -- mix test`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with project conventions and architecture"
```

---

Plan complete and saved to `docs/plans/2026-03-09-phoenix-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?
