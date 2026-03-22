defmodule GorgonSurveyWeb.SurveyLive do
  @moduledoc """
  Main LiveView serving the sidebar control panel at `/`.

  This is the primary UI the user interacts with. It renders a tabbed sidebar
  with three sections: Surveys, Settings, and Help.

  ## Responsibilities

  - **Survey management** — displays the list of detected surveys, allows toggling
    collected status, deleting, replacing markers, locking the list, and clearing.
  - **Motherlode mode** — switches between survey and motherlode triangulation modes.
  - **Log watcher control** — starts/stops the `LogWatcher` when the user sets a
    log folder path in settings.
  - **Zone management** — sends PubSub messages to `OverlayLive` to set/clear
    detection and inventory zones.
  - **Auto-detect** — when enabled, triggers a screenshot capture via the Tauri
    sidecar whenever a new survey appears in the log.
  - **Inventory markers** — tracks click-to-mark inventory items and shifts marker
    positions when surveys are collected.

  ## PubSub topics

  - Subscribes to `"game_state"` — receives `{:state_updated, %AppState{}}` from
    `AppState.Server` whenever state changes.
  - Subscribes to `"overlay:zones"` — receives zone updates from `OverlayLive`.
  - Broadcasts to `"overlay"` — sends zone setup/clear commands to `OverlayLive`.
  - Broadcasts to `"overlay:zones"` — sends zone clear events.

  ## State mutations

  All state mutations (place, collect, delete, clear, motherlode operations) are
  sent to `AppState.Server` which broadcasts the updated state back via PubSub.
  The LiveView never mutates app state directly — it only updates local UI state
  (placing_survey, locked, mode, inv_markers, etc.) in its own assigns.
  """

  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.AppState
  alias GorgonSurvey.ConfigStore

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay:zones")
      send(self(), :register_collect_hotkey)
    end

    log_folder = ConfigStore.get("log_folder", "")

    {:ok,
     assign(socket,
       watcher: nil,
       app_state: AppState.new(),
       overlay_active: false,
       placing_survey: nil,
       log_folder: log_folder,
       log_mode: :none,
       detect_zone: nil,
       inv_zone: nil,
       inv_markers: [],
       locked: false,
       auto_detect_on_survey:
         ConfigStore.get("auto_detect_on_survey", "false") == "true",
       sidebar_tab: "surveys",
       mode: :survey,
       collect_hotkey: ConfigStore.get("collect_hotkey", "")
     )}
  end

  @impl true
  def terminate(_reason, socket) do
    maybe_terminate_child(socket.assigns[:watcher])
    :ok
  end

  defp maybe_terminate_child(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      DynamicSupervisor.terminate_child(GorgonSurvey.WatcherSupervisor, pid)
    end
  end

  defp maybe_terminate_child(_), do: :ok

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    app_state =
      if socket.assigns.locked do
        existing_ids = MapSet.new(socket.assigns.app_state.surveys, & &1.id)
        surveys = Enum.filter(app_state.surveys, &MapSet.member?(existing_ids, &1.id))
        %{app_state | surveys: surveys}
      else
        app_state
      end

    # Remove inventory markers for newly collected surveys
    old_surveys = socket.assigns.app_state.surveys
    inv_markers = socket.assigns[:inv_markers] || []

    newly_collected =
      app_state.surveys
      |> Enum.filter(fn s ->
        s.collected &&
          Enum.find(old_surveys, fn o -> o.id == s.id && !o.collected end)
      end)
      |> MapSet.new(& &1.survey_number)

    inv_markers =
      if MapSet.size(newly_collected) > 0 do
        [collected] = newly_collected |> MapSet.to_list()

        remove_and_shift_inv_markers(inv_markers, collected)
      else
        inv_markers
      end

    socket = assign(socket, app_state: app_state, inv_markers: inv_markers)

    # Check if a new survey arrived (not present in old state)
    old_ids = MapSet.new(old_surveys, & &1.id)
    has_new_survey = Enum.any?(app_state.surveys, fn s -> !MapSet.member?(old_ids, s.id) end)

    # Trigger a single scan to place the new survey's marker
    socket =
      if has_new_survey && socket.assigns.auto_detect_on_survey do
        push_event(socket, "trigger_capture", %{
          detect_zone: socket.assigns.detect_zone
        })
      else
        socket
      end

    # If a new unplaced survey arrived, prompt manual placement (skip when auto-place handles it)
    unplaced = Enum.find(app_state.surveys, &is_nil(&1.x_pct))

    socket =
      if unplaced && socket.assigns.placing_survey == nil && !socket.assigns.auto_detect_on_survey do
        assign(socket, placing_survey: unplaced.id)
      else
        socket
      end

    socket =
      socket
      |> push_event("state_updated", serialize_state(socket))
      |> push_event("inv_markers", %{markers: inv_markers})

    {:noreply, socket}
  end

  # Receive zone updates from OverlayLive
  @impl true
  def handle_info({:zone_set, :detect, zone}, socket) do
    {:noreply, assign(socket, detect_zone: zone)}
  end

  @impl true
  def handle_info({:zone_set, :inv, zone}, socket) do
    {:noreply, assign(socket, inv_zone: zone)}
  end

  @impl true
  def handle_info(:register_collect_hotkey, socket) do
    key = socket.assigns.collect_hotkey

    if key != "" do
      {:noreply, push_event(socket, "set_collect_hotkey", %{key: key})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_collect_hotkey", %{"key" => key}, socket) do
    ConfigStore.put("collect_hotkey", key)

    socket =
      socket
      |> assign(collect_hotkey: key)
      |> push_event("set_collect_hotkey", %{key: key})

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    AppState.Server.place_survey(id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    AppState.Server.toggle_collected(parse_id(id))
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_survey", %{"id" => id}, socket) do
    AppState.Server.delete_survey(parse_id(id))
    {:noreply, socket}
  end

  @impl true
  def handle_event("replace_marker", %{"id" => id}, socket) do
    id = parse_id(id)
    AppState.Server.place_survey(id, nil, nil)
    {:noreply, assign(socket, placing_survey: id)}
  end

  @impl true
  def handle_event("toggle_lock", _params, socket) do
    {:noreply, assign(socket, locked: !socket.assigns.locked)}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    AppState.Server.clear_surveys()

    socket =
      socket
      |> assign(inv_markers: [])
      |> push_event("inv_markers", %{markers: []})

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_mode", _params, socket) do
    new_mode = if socket.assigns.mode == :survey, do: :motherlode, else: :survey
    socket = assign(socket, mode: new_mode)
    socket = push_event(socket, "state_updated", serialize_state(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_event("place_motherlode_reading", %{"x_pct" => x, "y_pct" => y}, socket) do
    AppState.Server.complete_motherlode_reading(x, y)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_motherlode", _params, socket) do
    AppState.Server.clear_motherlode()
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_motherlode_reading", %{"index" => index}, socket) do
    AppState.Server.delete_motherlode_reading(parse_id(index))
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_game_window", _params, socket) do
    {:noreply, push_event(socket, "select_game_window", %{})}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, sidebar_tab: tab)}
  end

  @impl true
  def handle_event("toggle_auto_detect_on_survey", _params, socket) do
    enabled = !socket.assigns.auto_detect_on_survey

    ConfigStore.put("auto_detect_on_survey", if(enabled, do: "true", else: "false"))

    {:noreply, assign(socket, auto_detect_on_survey: enabled)}
  end

  @impl true
  def handle_event(
        "set_detect_zone",
        %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2},
        socket
      ) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}
    Logger.info("[detect zone] set to x1=#{x1} y1=#{y1} x2=#{x2} y2=#{y2}")
    {:noreply, assign(socket, detect_zone: zone)}
  end

  @impl true
  def handle_event("start_set_zone", _params, socket) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay", {:start_set_zone, "map"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_detect_zone", _params, socket) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay", {:clear_zone, :detect})
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay:zones", {:zone_set, :detect, nil})

    socket =
      socket
      |> assign(detect_zone: nil)
      |> push_event("refresh_overlay", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_set_inv_zone", _params, socket) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay", {:start_set_zone, "inv"})
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "set_inv_zone",
        %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2},
        socket
      ) do
    {:noreply, assign(socket, inv_zone: %{x1: x1, y1: y1, x2: x2, y2: y2})}
  end

  @impl true
  def handle_event("clear_inv_zone", _params, socket) do
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay", {:clear_zone, :inv})
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay:zones", {:zone_set, :inv, nil})

    socket =
      socket
      |> assign(inv_zone: nil, inv_markers: [])
      |> push_event("refresh_overlay", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_inv_item", %{"x_pct" => x_pct, "y_pct" => y_pct}, socket) do
    surveys = socket.assigns.app_state.surveys
    inv_markers = socket.assigns[:inv_markers] || []

    next_idx = length(inv_markers)

    number =
      case Enum.at(surveys, next_idx) do
        nil -> next_idx + 1
        s -> s.survey_number
      end

    marker = %{x_pct: x_pct, y_pct: y_pct, number: number}
    inv_markers = inv_markers ++ [marker]

    socket =
      socket
      |> assign(inv_markers: inv_markers)
      |> push_event("inv_markers", %{markers: inv_markers})

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_inv_mark", %{"number" => number}, socket) do
    # Right-click removal: just delete the marker, no shifting
    inv_markers =
      (socket.assigns[:inv_markers] || [])
      |> Enum.reject(fn m -> m.number == number end)

    socket =
      socket
      |> assign(inv_markers: inv_markers)
      |> push_event("inv_markers", %{markers: inv_markers})

    {:noreply, socket}
  end

  @impl true
  def handle_event("undo_inv_mark", _params, socket) do
    inv_markers = socket.assigns[:inv_markers] || []

    inv_markers = if inv_markers != [], do: Enum.drop(inv_markers, -1), else: []

    socket =
      socket
      |> assign(inv_markers: inv_markers)
      |> push_event("inv_markers", %{markers: inv_markers})

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_log_folder", %{"folder" => _folder}, socket)
      when socket.assigns.watcher != nil do
    stop_current_watcher(socket)
    {:noreply, assign(socket, watcher: nil, log_mode: :none)}
  end

  def handle_event("set_log_folder", %{"folder" => folder}, socket) do
    ConfigStore.put("log_folder", folder)
    socket = assign(socket, log_folder: folder)

    case start_log_watcher(folder) do
      {:ok, pid} ->
        {:noreply, assign(socket, watcher: pid, log_mode: :local)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start watcher: #{inspect(reason)}")}
    end
  end

  # Remove a marker by number, shift later markers into earlier positions.
  # Numbers stay the same, positions shift left to fill the gap.
  # e.g. [(p1,6), (p2,7), (p3,8), (p4,9)] remove 7 → [(p1,6), (p2,8), (p3,9)]
  def remove_and_shift_inv_markers(markers, number) do
    idx = Enum.find_index(markers, fn m -> m.number == number end)

    if idx == nil do
      markers
    else
      marker_to_be_deleted = Enum.at(markers, idx)

      markers
      |> List.delete_at(idx)
      |> shift_inv_markers(marker_to_be_deleted)
    end
  end

  # After removing markers (e.g. from collection), shift positions left.
  # Keep original numbers, just collapse positions.
  defp shift_inv_markers(markers, deleted_marker) do
    result =
      Enum.reduce(
        markers,
        %{markers: [], previous_position: %{x: deleted_marker.x_pct, y: deleted_marker.y_pct}},
        fn marker, acc ->
          cond do
            marker.number > deleted_marker.number ->
              updated_marker = %{
                marker
                | x_pct: acc.previous_position.x,
                  y_pct: acc.previous_position.y
              }

              acc = put_in(acc, [:previous_position, :x], marker.x_pct)
              acc = put_in(acc, [:previous_position, :y], marker.y_pct)

              markers = [updated_marker | acc.markers]
              Map.put(acc, :markers, markers)

            marker.number < deleted_marker.number ->
              markers = [marker | acc.markers]
              Map.put(acc, :markers, markers)

            true ->
              acc
          end
        end
      )

    Enum.reverse(result.markers)
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id) when is_integer(id), do: id

  defp stop_current_watcher(socket) do
    maybe_terminate_child(socket.assigns[:watcher])
  end

  defp start_log_watcher(folder) do
    log_path = find_latest_log(folder)

    if log_path do
      DynamicSupervisor.start_child(
        GorgonSurvey.WatcherSupervisor,
        {GorgonSurvey.LogWatcher, log_path: log_path}
      )
    else
      {:error, "No log files found in #{folder}"}
    end
  end

  defp find_latest_log(folder) do
    folder
    |> Path.join("*.log")
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
    |> List.first()
  end

  defp serialize_state(socket) do
    app_state = socket.assigns.app_state
    mode = socket.assigns[:mode] || :survey

    surveys = Enum.map(app_state.surveys, &serialize_survey/1)
    readings = Enum.map(app_state.motherlode.readings, &serialize_reading/1)
    estimated_location = serialize_location(app_state.motherlode.estimated_location)

    %{
      mode: mode,
      surveys: surveys,
      placing_survey: socket.assigns.placing_survey,
      motherlode: %{
        readings: readings,
        pending_meters: app_state.motherlode.pending_meters,
        estimated_location: estimated_location
      }
    }
  end

  defp serialize_survey(s) do
    %{
      id: s.id,
      survey_number: s.survey_number,
      name: s.name,
      dx: s.dx,
      dy: s.dy,
      x_pct: s.x_pct,
      y_pct: s.y_pct,
      collected: s.collected
    }
  end

  defp serialize_reading(r), do: %{x_pct: r.x_pct, y_pct: r.y_pct, meters: r.meters}

  defp serialize_location({x, y}), do: %{x_pct: x, y_pct: y}
  defp serialize_location(nil), do: nil
end
