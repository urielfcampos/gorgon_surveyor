defmodule GorgonSurvey.LogWatcher do
  @moduledoc """
  GenServer that tails the game chat log and forwards parsed events to AppState.Server.

  Uses the `file_system` library (inotify on Linux) to watch the directory containing
  the log file. When the file changes, reads only the new bytes appended since the last
  read (tracked via `file_offset`), splits them into lines, parses each line with
  `LogParser`, and forwards recognized events to `AppState.Server`.

  ## Lifecycle

  Started dynamically via `WatcherSupervisor` (a `DynamicSupervisor`) when the user
  sets a log folder in the settings UI. Stopped when the user clears the folder or
  the LiveView terminates.

  ## Initialization

  On startup, records the current file size as the initial offset so that only new
  lines appended after the watcher starts are processed — existing log history is
  ignored.

  ## Recognized events

  - `{:survey, %{name, dx, dy}}` — forwarded as `AppState.Server.add_survey/1`
  - `{:motherlode, %{meters}}` — forwarded as `AppState.Server.add_pending_motherlode/1`
  - All other lines (chat, system messages, etc.) are ignored.
  """

  use GenServer

  alias GorgonSurvey.{AppState, LogParser}

  # Client API

  def start_link(opts) do
    log_path = Keyword.fetch!(opts, :log_path)
    GenServer.start_link(__MODULE__, log_path)
  end

  # Server callbacks

  @impl true
  def init(log_path) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [Path.dirname(log_path)])
    FileSystem.subscribe(watcher_pid)

    file_size =
      case File.stat(log_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    {:ok,
     %{
       log_path: log_path,
       watcher_pid: watcher_pid,
       file_offset: file_size
     }}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if Path.basename(path) == Path.basename(state.log_path) do
      {:noreply, read_new_lines(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  defp read_new_lines(state) do
    with {:ok, content} <- read_from_offset(state.log_path, state.file_offset),
         true <- byte_size(content) > 0 do
      forward_events(content)
      %{state | file_offset: state.file_offset + byte_size(content)}
    else
      _ -> state
    end
  end

  defp read_from_offset(log_path, offset) do
    with {:ok, file} <- File.open(log_path, [:read]) do
      :file.position(file, offset)
      content = IO.read(file, :eof)
      File.close(file)

      case content do
        data when is_binary(data) -> {:ok, data}
        _ -> :error
      end
    end
  end

  defp forward_events(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case LogParser.parse_line(line) do
        {:survey, data} -> AppState.Server.add_survey(data)
        {:motherlode, data} -> AppState.Server.add_pending_motherlode(data.meters)
        _other -> :ok
      end
    end)
  end
end
