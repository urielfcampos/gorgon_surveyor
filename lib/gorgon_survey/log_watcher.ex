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
    file_size =
      case File.stat(log_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    {:ok,
     %{
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
