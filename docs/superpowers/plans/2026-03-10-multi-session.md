# Multi-Session Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate each browser tab into its own session with independent LogWatcher, survey state, and config overrides.

**Architecture:** A `SessionManager` GenServer tracks sessions by UUID. A `DynamicSupervisor` supervises per-session `LogWatcher` processes registered via `Registry`. On disconnect, a 30s cleanup timer fires; on reconnect the timer is cancelled. PubSub topics are scoped per session.

**Tech Stack:** Elixir/Phoenix LiveView, GenServer, DynamicSupervisor, Registry, PubSub. All commands prefixed with `mise exec --`.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/gorgon_survey/session_manager.ex` | Create | GenServer tracking sessions, cleanup timers, config overrides |
| `test/gorgon_survey/session_manager_test.exs` | Create | Tests for SessionManager |
| `lib/gorgon_survey/application.ex` | Modify | Add Registry, SessionManager, SessionSupervisor; remove global LogWatcher |
| `lib/gorgon_survey/log_watcher.ex` | Modify | Accept session_id, register via Registry, scope PubSub topic |
| `test/gorgon_survey/log_watcher_test.exs` | Modify | Update to pass session_id, subscribe to scoped topic |
| `lib/gorgon_survey/config_store.ex` | Modify | Add session-aware get/put that checks SessionManager first |
| `test/gorgon_survey/config_store_test.exs` | Create | Tests for session-aware config |
| `lib/gorgon_survey_web/live/survey_live.ex` | Modify | Generate session UUID, register/deregister, use scoped LogWatcher |
| `test/gorgon_survey_web/live/survey_live_test.exs` | Modify | Update setup to work with session-based architecture |

---

## Chunk 1: Infrastructure (Registry, SessionSupervisor, SessionManager)

### Task 1: Add Registry and DynamicSupervisor to Application

**Files:**
- Modify: `lib/gorgon_survey/application.ex`

- [ ] **Step 1: Update supervision tree**

Add Registry and DynamicSupervisor before the Endpoint. Remove the global `log_watcher_child_spec()` call. Keep `start_log_watcher/1` but mark it deprecated (it will be replaced in Task 5).

```elixir
# In start/2, replace children list:
children =
  [
    GorgonSurveyWeb.Telemetry,
    {DNSCluster, query: Application.get_env(:gorgon_survey, :dns_cluster_query) || :ignore},
    {Phoenix.PubSub, name: GorgonSurvey.PubSub},
    {Registry, keys: :unique, name: GorgonSurvey.SessionRegistry},
    GorgonSurvey.SessionManager,
    {DynamicSupervisor, name: GorgonSurvey.SessionSupervisor, strategy: :one_for_one},
    GorgonSurveyWeb.Endpoint
  ]
```

Remove the `|> Enum.reject(&is_nil/1)` pipe since we no longer have conditional children.

- [ ] **Step 2: Verify it compiles**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Compilation error (SessionManager module doesn't exist yet — that's fine, we'll create it next)

- [ ] **Step 3: Commit**

```bash
git add lib/gorgon_survey/application.ex
git commit -m "refactor: update supervision tree for multi-session support"
```

### Task 2: Create SessionManager

**Files:**
- Create: `lib/gorgon_survey/session_manager.ex`
- Create: `test/gorgon_survey/session_manager_test.exs`

- [ ] **Step 1: Write failing tests for SessionManager**

```elixir
# test/gorgon_survey/session_manager_test.exs
defmodule GorgonSurvey.SessionManagerTest do
  use ExUnit.Case, async: false

  alias GorgonSurvey.SessionManager

  setup do
    # Clear all sessions between tests
    for session_id <- SessionManager.list_sessions() do
      SessionManager.force_cleanup(session_id)
    end
    :ok
  end

  describe "register/1" do
    test "registers a new session and returns :ok" do
      session_id = "test-#{System.unique_integer([:positive])}"
      assert :ok = SessionManager.register(session_id)
      assert session_id in SessionManager.list_sessions()
    end

    test "registering same session_id twice is idempotent" do
      session_id = "test-#{System.unique_integer([:positive])}"
      assert :ok = SessionManager.register(session_id)
      assert :ok = SessionManager.register(session_id)
    end
  end

  describe "deregister/1 and cleanup" do
    test "schedules cleanup timer on deregister" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert :ok = SessionManager.deregister(session_id)
      # Session still exists during grace period
      assert session_id in SessionManager.list_sessions()
    end

    test "force_cleanup removes session immediately" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.force_cleanup(session_id)
      refute session_id in SessionManager.list_sessions()
    end
  end

  describe "reconnect/1" do
    test "cancels cleanup timer and returns :ok" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.deregister(session_id)
      assert :ok = SessionManager.reconnect(session_id)
      # Still alive after reconnect
      assert session_id in SessionManager.list_sessions()
    end

    test "returns :error for unknown session" do
      assert :error = SessionManager.reconnect("nonexistent")
    end
  end

  describe "config overrides" do
    test "put_config/3 and get_config/2" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.put_config(session_id, "log_folder", "/tmp/test")
      assert "/tmp/test" = SessionManager.get_config(session_id, "log_folder")
    end

    test "get_config returns nil for unset key" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert nil == SessionManager.get_config(session_id, "unset_key")
    end

    test "get_config returns nil for unknown session" do
      assert nil == SessionManager.get_config("nonexistent", "key")
    end
  end

  describe "watcher management" do
    test "start_watcher/2 stores watcher pid" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)

      tmp_dir = Path.join(System.tmp_dir!(), "sm_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      log_path = Path.join(tmp_dir, "chat.log")
      File.write!(log_path, "")
      on_exit(fn -> File.rm_rf(tmp_dir) end)

      assert {:ok, pid} = SessionManager.start_watcher(session_id, tmp_dir)
      assert is_pid(pid)
      assert Process.alive?(pid)

      SessionManager.force_cleanup(session_id)
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "get_watcher/1 returns pid or nil" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert nil == SessionManager.get_watcher(session_id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey/session_manager_test.exs`
Expected: Compilation error (SessionManager module doesn't exist)

- [ ] **Step 3: Implement SessionManager**

```elixir
# lib/gorgon_survey/session_manager.ex
defmodule GorgonSurvey.SessionManager do
  @moduledoc "Tracks active sessions, manages per-session LogWatcher lifecycle and config overrides."

  use GenServer

  @cleanup_timeout :timer.seconds(30)

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(session_id) do
    GenServer.call(__MODULE__, {:register, session_id})
  end

  def deregister(session_id) do
    GenServer.call(__MODULE__, {:deregister, session_id})
  end

  def reconnect(session_id) do
    GenServer.call(__MODULE__, {:reconnect, session_id})
  end

  def force_cleanup(session_id) do
    GenServer.call(__MODULE__, {:force_cleanup, session_id})
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  def start_watcher(session_id, log_folder) do
    GenServer.call(__MODULE__, {:start_watcher, session_id, log_folder})
  end

  def get_watcher(session_id) do
    GenServer.call(__MODULE__, {:get_watcher, session_id})
  end

  def put_config(session_id, key, value) do
    GenServer.cast(__MODULE__, {:put_config, session_id, key, value})
  end

  def get_config(session_id, key) do
    GenServer.call(__MODULE__, {:get_config, session_id, key})
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:register, session_id}, _from, state) do
    sessions =
      Map.put_new(state.sessions, session_id, %{
        watcher_pid: nil,
        config: %{},
        cleanup_timer: nil
      })

    {:reply, :ok, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:deregister, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :ok, state}

      session ->
        timer = Process.send_after(self(), {:cleanup, session_id}, @cleanup_timeout)
        session = %{session | cleanup_timer: timer}
        {:reply, :ok, %{state | sessions: Map.put(state.sessions, session_id, session)}}
    end
  end

  @impl true
  def handle_call({:reconnect, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :error, state}

      session ->
        if session.cleanup_timer, do: Process.cancel_timer(session.cleanup_timer)
        session = %{session | cleanup_timer: nil}
        {:reply, :ok, %{state | sessions: Map.put(state.sessions, session_id, session)}}
    end
  end

  @impl true
  def handle_call({:force_cleanup, session_id}, _from, state) do
    state = do_cleanup(state, session_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    {:reply, Map.keys(state.sessions), state}
  end

  @impl true
  def handle_call({:start_watcher, session_id, log_folder}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :unknown_session}, state}

      session ->
        # Stop existing watcher if any
        if session.watcher_pid && Process.alive?(session.watcher_pid) do
          DynamicSupervisor.terminate_child(GorgonSurvey.SessionSupervisor, session.watcher_pid)
        end

        log_path = find_latest_log(log_folder)

        if log_path do
          case DynamicSupervisor.start_child(
                 GorgonSurvey.SessionSupervisor,
                 {GorgonSurvey.LogWatcher, log_path: log_path, session_id: session_id, name: {:via, Registry, {GorgonSurvey.SessionRegistry, {:session, session_id}}}}
               ) do
            {:ok, pid} ->
              session = %{session | watcher_pid: pid}
              {:reply, {:ok, pid}, %{state | sessions: Map.put(state.sessions, session_id, session)}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, "No log files found in #{log_folder}"}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_watcher, session_id}, _from, state) do
    watcher_pid =
      case Map.get(state.sessions, session_id) do
        nil -> nil
        session -> session.watcher_pid
      end

    {:reply, watcher_pid, state}
  end

  @impl true
  def handle_call({:get_config, session_id, key}, _from, state) do
    value =
      case Map.get(state.sessions, session_id) do
        nil -> nil
        session -> Map.get(session.config, key)
      end

    {:reply, value, state}
  end

  @impl true
  def handle_cast({:put_config, session_id, key, value}, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:noreply, state}

      session ->
        session = %{session | config: Map.put(session.config, key, value)}
        {:noreply, %{state | sessions: Map.put(state.sessions, session_id, session)}}
    end
  end

  @impl true
  def handle_info({:cleanup, session_id}, state) do
    {:noreply, do_cleanup(state, session_id)}
  end

  defp do_cleanup(state, session_id) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session ->
        if session.watcher_pid && Process.alive?(session.watcher_pid) do
          DynamicSupervisor.terminate_child(GorgonSurvey.SessionSupervisor, session.watcher_pid)
        end

        %{state | sessions: Map.delete(state.sessions, session_id)}
    end
  end

  defp find_latest_log(folder) do
    folder
    |> Path.join("*.log")
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
    |> List.first()
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mise exec -- mix test test/gorgon_survey/session_manager_test.exs`
Expected: All pass

- [ ] **Step 5: Compile check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 6: Commit**

```bash
git add lib/gorgon_survey/session_manager.ex test/gorgon_survey/session_manager_test.exs lib/gorgon_survey/application.ex
git commit -m "feat: add SessionManager and session infrastructure"
```

---

## Chunk 2: Scope LogWatcher per session

### Task 3: Update LogWatcher for per-session operation

**Files:**
- Modify: `lib/gorgon_survey/log_watcher.ex`
- Modify: `test/gorgon_survey/log_watcher_test.exs`

- [ ] **Step 1: Update LogWatcher to accept session_id and scope PubSub**

The key changes:
- `init/1` receives a keyword list, extracts `log_path` and `session_id`
- `broadcast/2` sends to `"game_state:#{session_id}"` instead of `"game_state"`
- Client API functions accept a server ref (pid or via-tuple) as first argument (already supported via default `\\ __MODULE__` params — keep that pattern but the default will no longer work since there's no global registration)

```elixir
# lib/gorgon_survey/log_watcher.ex
defmodule GorgonSurvey.LogWatcher do
  @moduledoc "GenServer that tails the game chat log and maintains app state."

  use GenServer

  alias GorgonSurvey.{AppState, LogParser}

  # Client API

  def start_link(opts) do
    log_path = Keyword.fetch!(opts, :log_path)
    session_id = Keyword.get(opts, :session_id, "global")
    name = Keyword.get(opts, :name, nil)
    GenServer.start_link(__MODULE__, {log_path, session_id}, name: name)
  end

  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  def place_survey(server, id, x_pct, y_pct) do
    GenServer.cast(server, {:place_survey, id, x_pct, y_pct})
  end

  def toggle_collected(server, id) do
    GenServer.cast(server, {:toggle_collected, id})
  end

  def delete_survey(server, id) do
    GenServer.cast(server, {:delete_survey, id})
  end

  def clear_surveys(server) do
    GenServer.cast(server, :clear_surveys)
  end

  def set_zone(server, zone) do
    GenServer.cast(server, {:set_zone, zone})
  end

  def add_motherlode_reading(server, reading) do
    GenServer.cast(server, {:add_motherlode_reading, reading})
  end

  # Server callbacks

  @impl true
  def init({log_path, session_id}) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [Path.dirname(log_path)])
    FileSystem.subscribe(watcher_pid)

    file_size =
      case File.stat(log_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    {:ok,
     %{
       app_state: AppState.new(),
       log_path: log_path,
       session_id: session_id,
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
    broadcast(state.session_id, app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:toggle_collected, id}, state) do
    app_state = AppState.toggle_collected(state.app_state, id)
    state = %{state | app_state: app_state}
    broadcast(state.session_id, app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete_survey, id}, state) do
    app_state = AppState.delete_survey(state.app_state, id)
    state = %{state | app_state: app_state}
    broadcast(state.session_id, app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear_surveys, state) do
    app_state = AppState.clear_surveys(state.app_state)
    state = %{state | app_state: app_state}
    broadcast(state.session_id, app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_zone, zone}, state) do
    app_state = %{state.app_state | zone: zone}
    state = %{state | app_state: app_state}
    broadcast(state.session_id, app_state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_motherlode_reading, reading}, state) do
    app_state = AppState.add_motherlode_reading(state.app_state, reading)
    state = %{state | app_state: app_state}
    broadcast(state.session_id, app_state)
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
            broadcast(state.session_id, app_state)
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

  defp broadcast(session_id, app_state) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "game_state:#{session_id}", {:state_updated, app_state})
  end
end
```

- [ ] **Step 2: Update LogWatcher tests**

```elixir
# test/gorgon_survey/log_watcher_test.exs
defmodule GorgonSurvey.LogWatcherTest do
  use ExUnit.Case

  alias GorgonSurvey.LogWatcher

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "logwatch_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    log_path = Path.join(tmp_dir, "chat.log")
    File.write!(log_path, "")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    session_id = "test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")

    {:ok, log_path: log_path, session_id: session_id}
  end

  test "starts and returns initial state", %{log_path: log_path, session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    state = LogWatcher.get_state(pid)
    assert state.surveys == []
    GenServer.stop(pid)
  end

  test "detects new survey line appended to log", %{log_path: log_path, session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 815m west and 1441m north.\n", [:append])
    Process.sleep(500)
    state = LogWatcher.get_state(pid)
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.name == "Good Metal Slab"
    GenServer.stop(pid)
  end

  test "broadcasts state updates via scoped PubSub", %{log_path: log_path, session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    assert_receive {:state_updated, %GorgonSurvey.AppState{}}, 2000
    GenServer.stop(pid)
  end

  test "different sessions do not receive each other's broadcasts", %{log_path: log_path} do
    other_session = "other-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{other_session}")

    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: "isolated-session")
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    # Should NOT receive on the other_session topic
    refute_receive {:state_updated, _}, 1000
    GenServer.stop(pid)
  end
end
```

- [ ] **Step 3: Run tests**

Run: `mise exec -- mix test test/gorgon_survey/log_watcher_test.exs`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/gorgon_survey/log_watcher.ex test/gorgon_survey/log_watcher_test.exs
git commit -m "refactor: scope LogWatcher PubSub broadcasts per session"
```

---

## Chunk 3: Update ConfigStore and SurveyLive

### Task 4: Update ConfigStore with session-aware accessors

**Files:**
- Modify: `lib/gorgon_survey/config_store.ex`
- Create: `test/gorgon_survey/config_store_test.exs`

- [ ] **Step 1: Write tests for session-aware config**

```elixir
# test/gorgon_survey/config_store_test.exs
defmodule GorgonSurvey.ConfigStoreTest do
  use ExUnit.Case, async: false

  alias GorgonSurvey.{ConfigStore, SessionManager}

  setup do
    session_id = "config-test-#{System.unique_integer([:positive])}"
    SessionManager.register(session_id)
    on_exit(fn -> SessionManager.force_cleanup(session_id) end)
    {:ok, session_id: session_id}
  end

  test "get_for_session returns session override when set", %{session_id: session_id} do
    SessionManager.put_config(session_id, "log_folder", "/tmp/session-folder")
    assert "/tmp/session-folder" = ConfigStore.get_for_session(session_id, "log_folder")
  end

  test "get_for_session falls back to global config", %{session_id: session_id} do
    # Global config has some value; session does not override it
    global_val = ConfigStore.get("log_folder", "")
    assert ConfigStore.get_for_session(session_id, "log_folder", "") == global_val
  end

  test "put_for_session stores in session, not global", %{session_id: session_id} do
    original_global = ConfigStore.get("test_key_xyz", nil)
    ConfigStore.put_for_session(session_id, "test_key_xyz", "session_value")
    assert ConfigStore.get_for_session(session_id, "test_key_xyz") == "session_value"
    # Global unchanged
    assert ConfigStore.get("test_key_xyz", nil) == original_global
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise exec -- mix test test/gorgon_survey/config_store_test.exs`
Expected: FAIL (functions don't exist)

- [ ] **Step 3: Add session-aware functions to ConfigStore**

```elixir
# Add to lib/gorgon_survey/config_store.ex, after existing functions:

def get_for_session(session_id, key, default \\ nil) do
  case GorgonSurvey.SessionManager.get_config(session_id, key) do
    nil -> get(key, default)
    value -> value
  end
end

def put_for_session(session_id, key, value) do
  GorgonSurvey.SessionManager.put_config(session_id, key, value)
end
```

- [ ] **Step 4: Run tests**

Run: `mise exec -- mix test test/gorgon_survey/config_store_test.exs`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/gorgon_survey/config_store.ex test/gorgon_survey/config_store_test.exs
git commit -m "feat: add session-aware config accessors to ConfigStore"
```

### Task 5: Update SurveyLive for per-session operation

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.ex`
- Modify: `test/gorgon_survey_web/live/survey_live_test.exs`

- [ ] **Step 1: Update SurveyLive mount, terminate, and all LogWatcher calls**

Key changes to `lib/gorgon_survey_web/live/survey_live.ex`:

1. `mount/3`: Generate session UUID, register with SessionManager, subscribe to scoped PubSub topic, load config via `ConfigStore.get_for_session/3`.
2. Add `terminate/2` callback to deregister session.
3. Replace all `LogWatcher.function(args)` calls with `LogWatcher.function(watcher, args)` where `watcher` comes from `socket.assigns.watcher`.
4. `set_log_folder` handler: use `SessionManager.start_watcher/2` instead of `Application.start_log_watcher/1`, store config via `ConfigStore.put_for_session/3`.
5. `handle_info({:state_updated, ...})`: no change needed (PubSub topic already scoped).

Replace `mount/3`:

```elixir
@impl true
def mount(_params, _session, socket) do
  session_id = Ecto.UUID.generate()

  if connected?(socket) do
    GorgonSurvey.SessionManager.register(session_id)
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")
  end

  log_folder = ConfigStore.get_for_session(session_id, "log_folder", "")

  {:ok,
   assign(socket,
     session_id: session_id,
     watcher: nil,
     app_state: GorgonSurvey.AppState.new(),
     sharing: false,
     placing_survey: nil,
     log_folder: log_folder,
     detect_zone: nil,
     inv_zone: nil,
     inv_markers: [],
     locked: false,
     auto_detect_on_survey: ConfigStore.get_for_session(session_id, "auto_detect_on_survey", "false") == "true",
     sidebar_tab: "surveys"
   )}
end
```

Add `terminate/2`:

```elixir
@impl true
def terminate(_reason, socket) do
  if session_id = socket.assigns[:session_id] do
    GorgonSurvey.SessionManager.deregister(session_id)
  end
  :ok
end
```

Replace `set_log_folder` handler:

```elixir
@impl true
def handle_event("set_log_folder", %{"folder" => folder}, socket) do
  session_id = socket.assigns.session_id
  ConfigStore.put_for_session(session_id, "log_folder", folder)
  # Also save globally as default for new sessions
  ConfigStore.put("log_folder", folder)
  socket = assign(socket, log_folder: folder)

  case GorgonSurvey.SessionManager.start_watcher(session_id, folder) do
    {:ok, pid} ->
      {:noreply, assign(socket, watcher: pid)}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to start watcher: #{inspect(reason)}")}
  end
end
```

Replace `toggle_auto_detect_on_survey` to use session config:

```elixir
@impl true
def handle_event("toggle_auto_detect_on_survey", _params, socket) do
  enabled = !socket.assigns.auto_detect_on_survey
  ConfigStore.put_for_session(socket.assigns.session_id, "auto_detect_on_survey", if(enabled, do: "true", else: "false"))
  {:noreply, assign(socket, auto_detect_on_survey: enabled)}
end
```

For ALL event handlers that call LogWatcher, add a guard and use `socket.assigns.watcher`:

```elixir
# Helper to get watcher ref, returns nil if not started
defp watcher(socket), do: socket.assigns[:watcher]
```

Update each handler. Example for `place_survey`:

```elixir
@impl true
def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
  if w = watcher(socket), do: LogWatcher.place_survey(w, id, x, y)
  {:noreply, assign(socket, placing_survey: nil)}
end
```

Apply the same pattern to: `toggle_collected`, `delete_survey`, `replace_marker`, `clear_surveys`. Each one should guard with `if w = watcher(socket)`.

Note: `Ecto.UUID.generate()` is not available since there's no Ecto. Use `:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)` instead.

- [ ] **Step 2: Update SurveyLive tests**

```elixir
# test/gorgon_survey_web/live/survey_live_test.exs
defmodule GorgonSurveyWeb.SurveyLiveTest do
  use GorgonSurveyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders page with share screen button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
    assert html =~ "Surveys"
  end

  test "renders without a running LogWatcher", %{conn: conn} do
    # No LogWatcher started — should still render cleanly
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
  end
end
```

The old test that broadcasts to `"game_state"` is removed because the topic is now session-scoped and the session ID is generated internally by mount. Testing PubSub integration would require extracting the session ID from the LiveView, which is better tested at the SessionManager/LogWatcher level.

- [ ] **Step 3: Run all tests**

Run: `mise exec -- mix test`
Expected: All pass

- [ ] **Step 4: Compile check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 5: Commit**

```bash
git add lib/gorgon_survey_web/live/survey_live.ex test/gorgon_survey_web/live/survey_live_test.exs
git commit -m "feat: isolate SurveyLive sessions with per-session LogWatcher and config"
```

---

## Chunk 4: Cleanup and final verification

### Task 6: Remove deprecated global LogWatcher startup

**Files:**
- Modify: `lib/gorgon_survey/application.ex`

- [ ] **Step 1: Remove `start_log_watcher/1`, `log_watcher_child_spec/0`, and `find_latest_log/1` from Application**

These are now handled by SessionManager. The `find_latest_log/1` function has been duplicated into SessionManager already.

```elixir
# lib/gorgon_survey/application.ex — final version
defmodule GorgonSurvey.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GorgonSurveyWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:gorgon_survey, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GorgonSurvey.PubSub},
      {Registry, keys: :unique, name: GorgonSurvey.SessionRegistry},
      GorgonSurvey.SessionManager,
      {DynamicSupervisor, name: GorgonSurvey.SessionSupervisor, strategy: :one_for_one},
      GorgonSurveyWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: GorgonSurvey.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    GorgonSurveyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

- [ ] **Step 2: Run full test suite**

Run: `mise exec -- mix test`
Expected: All pass

- [ ] **Step 3: Compile check**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 4: Commit**

```bash
git add lib/gorgon_survey/application.ex
git commit -m "refactor: remove global LogWatcher startup from Application"
```

### Task 7: Update CLAUDE.md and README

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update supervision tree docs in CLAUDE.md and README.md**

Update the supervision tree section in both files to reflect the new architecture:

```
Application Supervisor (one_for_one)
+-- Telemetry
+-- DNSCluster (conditional)
+-- Phoenix.PubSub
+-- Registry (SessionRegistry)
+-- SessionManager
+-- SessionSupervisor (DynamicSupervisor)
|   +-- LogWatcher (per session)
+-- Endpoint
```

Add `SessionManager` to the key modules table:

| `GorgonSurvey.SessionManager` | Tracks active sessions, manages per-session LogWatcher lifecycle, config overrides, cleanup timers |

Update the data flow to mention session scoping.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: update architecture docs for multi-session support"
```

### Task 8: Final integration verification

- [ ] **Step 1: Run full test suite**

Run: `mise exec -- mix test`
Expected: All 24+ tests pass, 0 failures

- [ ] **Step 2: Run precommit**

Run: `mise exec -- mix precommit`
Expected: Clean (compile + format + test)

- [ ] **Step 3: Manual smoke test (optional)**

Run: `mise exec -- mix phx.server`
Open two browser tabs to `http://localhost:4000`. Verify each tab operates independently.
