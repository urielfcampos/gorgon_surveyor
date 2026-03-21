defmodule GorgonSurveyWeb.SurveyLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher
  alias GorgonSurvey.ConfigStore

  @impl true
  def mount(_params, _session, socket) do
    session_id = generate_session_id()

    if connected?(socket) do
      GorgonSurvey.SessionManager.register(session_id)
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay:#{session_id}:zones")
      send(self(), :register_collect_hotkey)
    end

    log_folder = ConfigStore.get_for_session(session_id, "log_folder", "")

    {:ok,
     assign(socket,
       session_id: session_id,
       watcher: nil,
       app_state: GorgonSurvey.AppState.new(),
       overlay_active: false,
       placing_survey: nil,
       log_folder: log_folder,
       log_mode: :none,
       log_watcher_mode: Application.get_env(:gorgon_survey, :log_watcher_mode, :local),
       detect_zone: nil,
       inv_zone: nil,
       inv_markers: [],
       locked: false,
       auto_detect_on_survey:
         ConfigStore.get_for_session(session_id, "auto_detect_on_survey", "false") == "true",
       sidebar_tab: "surveys",
       mode: :survey,
       collect_hotkey: ConfigStore.get("collect_hotkey", "")
     )}
  end

  @impl true
  def terminate(_reason, socket) do
    if session_id = socket.assigns[:session_id] do
      GorgonSurvey.SessionManager.deregister(session_id)
    end

    :ok
  end

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
          session_id: socket.assigns.session_id,
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
    if w = watcher(socket), do: LogWatcher.place_survey(w, id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    if w = watcher(socket), do: LogWatcher.toggle_collected(w, id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_survey", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    if w = watcher(socket), do: LogWatcher.delete_survey(w, id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("replace_marker", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    if w = watcher(socket), do: LogWatcher.place_survey(w, id, nil, nil)
    {:noreply, assign(socket, placing_survey: id)}
  end

  @impl true
  def handle_event("toggle_lock", _params, socket) do
    {:noreply, assign(socket, locked: !socket.assigns.locked)}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    if w = watcher(socket), do: LogWatcher.clear_surveys(w)

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
    if w = watcher(socket), do: LogWatcher.complete_motherlode_reading(w, x, y)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_motherlode", _params, socket) do
    if w = watcher(socket), do: LogWatcher.clear_motherlode(w)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_motherlode_reading", %{"index" => index}, socket) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    if w = watcher(socket), do: LogWatcher.delete_motherlode_reading(w, index)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_game_window", _params, socket) do
    {:noreply, push_event(socket, "select_game_window", %{session_id: socket.assigns.session_id})}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, sidebar_tab: tab)}
  end

  @impl true
  def handle_event("toggle_auto_detect_on_survey", _params, socket) do
    enabled = !socket.assigns.auto_detect_on_survey

    ConfigStore.put_for_session(
      socket.assigns.session_id,
      "auto_detect_on_survey",
      if(enabled, do: "true", else: "false")
    )

    {:noreply, assign(socket, auto_detect_on_survey: enabled)}
  end

  @impl true
  def handle_event(
        "set_detect_zone",
        %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2},
        socket
      ) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}
    require Logger
    Logger.info("[detect zone] set to x1=#{x1} y1=#{y1} x2=#{x2} y2=#{y2}")
    {:noreply, assign(socket, detect_zone: zone)}
  end

  @impl true
  def handle_event("start_set_zone", _params, socket) do
    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}",
      {:start_set_zone, "map"}
    )
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_detect_zone", _params, socket) do
    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}",
      {:clear_zone, :detect}
    )

    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}:zones",
      {:zone_set, :detect, nil}
    )

    socket =
      socket
      |> assign(detect_zone: nil)
      |> push_event("refresh_overlay", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_set_inv_zone", _params, socket) do
    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}",
      {:start_set_zone, "inv"}
    )
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
    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}",
      {:clear_zone, :inv}
    )

    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}:zones",
      {:zone_set, :inv, nil}
    )

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
  def handle_event("start_log_stream", _params, socket) do
    session_id = socket.assigns.session_id

    case GorgonSurvey.SessionManager.start_remote_watcher(session_id) do
      {:ok, pid} ->
        {:noreply, assign(socket, watcher: pid, log_mode: :remote)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to start stream watcher: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("log_lines", %{"lines" => lines}, socket) do
    if w = watcher(socket) do
      LogWatcher.ingest_lines(w, lines)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_log_stream", _params, socket) do
    GorgonSurvey.SessionManager.stop_watcher(socket.assigns.session_id)
    {:noreply, assign(socket, watcher: nil, log_mode: :none)}
  end

  @impl true
  def handle_event("set_log_folder", %{"folder" => folder}, socket) do
    session_id = socket.assigns.session_id

    if socket.assigns.watcher do
      GorgonSurvey.SessionManager.stop_watcher(session_id)
      {:noreply, assign(socket, watcher: nil, log_mode: :none)}
    else
      ConfigStore.put_for_session(session_id, "log_folder", folder)
      # Also save globally as default for new sessions
      ConfigStore.put("log_folder", folder)
      socket = assign(socket, log_folder: folder)

      case GorgonSurvey.SessionManager.start_watcher(session_id, folder) do
        {:ok, pid} ->
          {:noreply, assign(socket, watcher: pid, log_mode: :local)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start watcher: #{inspect(reason)}")}
      end
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

  defp watcher(socket), do: socket.assigns[:watcher]

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp serialize_state(socket) do
    app_state = socket.assigns.app_state
    mode = socket.assigns[:mode] || :survey

    %{
      mode: mode,
      surveys:
        Enum.map(app_state.surveys, fn s ->
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
        end),
      placing_survey: socket.assigns.placing_survey,
      motherlode: %{
        readings:
          Enum.map(app_state.motherlode.readings, fn r ->
            %{x_pct: r.x_pct, y_pct: r.y_pct, meters: r.meters}
          end),
        pending_meters: app_state.motherlode.pending_meters,
        estimated_location:
          case app_state.motherlode.estimated_location do
            {x, y} -> %{x_pct: x, y_pct: y}
            nil -> nil
          end
      }
    }
  end
end
