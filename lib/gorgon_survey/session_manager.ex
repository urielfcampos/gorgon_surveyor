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

  def start_remote_watcher(session_id) do
    GenServer.call(__MODULE__, {:start_remote_watcher, session_id})
  end

  def stop_watcher(session_id) do
    GenServer.call(__MODULE__, {:stop_watcher, session_id})
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
        if session.watcher_pid && Process.alive?(session.watcher_pid) do
          DynamicSupervisor.terminate_child(GorgonSurvey.SessionSupervisor, session.watcher_pid)
        end

        log_path = find_latest_log(log_folder)

        if log_path do
          case DynamicSupervisor.start_child(
                 GorgonSurvey.SessionSupervisor,
                 {GorgonSurvey.LogWatcher,
                  log_path: log_path,
                  session_id: session_id,
                  name: {:via, Registry, {GorgonSurvey.SessionRegistry, {:session, session_id}}}}
               ) do
            {:ok, pid} ->
              session = %{session | watcher_pid: pid}

              {:reply, {:ok, pid},
               %{state | sessions: Map.put(state.sessions, session_id, session)}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, "No log files found in #{log_folder}"}, state}
        end
    end
  end

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
                name:
                  {:via, Registry, {GorgonSurvey.SessionRegistry, {:session, session_id}}}}
             ) do
          {:ok, pid} ->
            session = %{session | watcher_pid: pid}

            {:reply, {:ok, pid},
             %{state | sessions: Map.put(state.sessions, session_id, session)}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
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
          DynamicSupervisor.terminate_child(
            GorgonSurvey.SessionSupervisor,
            session.watcher_pid
          )
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
