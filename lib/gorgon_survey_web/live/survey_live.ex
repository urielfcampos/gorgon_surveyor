defmodule GorgonSurveyWeb.SurveyLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher
  alias GorgonSurvey.ConfigStore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
    end

    state =
      try do
        LogWatcher.get_state()
      catch
        :exit, _ -> GorgonSurvey.AppState.new()
      end

    log_folder = ConfigStore.get("log_folder", "")

    {:ok,
     assign(socket,
       app_state: state,
       sharing: false,
       placing_survey: nil,
       log_folder: log_folder,
       detect_zone: nil,
       inv_zone: nil,
       inv_markers: [],
       locked: false,
       auto_detect_on_survey: ConfigStore.get("auto_detect_on_survey", "false") == "true",
       sidebar_tab: "surveys"
     )}
  end

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    app_state =
      if socket.assigns.locked do
        # When locked, only update existing surveys (positions, collected status)
        # but don't add new ones
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

    dbg(newly_collected)

    inv_markers =
      if MapSet.size(newly_collected) > 0 do
        [collected] = newly_collected |> MapSet.to_list()

        remove_and_shift_inv_markers(inv_markers, collected)
        |> dbg()
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
        push_event(socket, "scan_once", %{})
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

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    LogWatcher.place_survey(id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    LogWatcher.toggle_collected(id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_survey", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    LogWatcher.delete_survey(id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("replace_marker", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    # Clear the survey's position so it becomes unplaced, then prompt placement
    LogWatcher.place_survey(id, nil, nil)
    {:noreply, assign(socket, placing_survey: id)}
  end

  @impl true
  def handle_event("toggle_lock", _params, socket) do
    {:noreply, assign(socket, locked: !socket.assigns.locked)}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    LogWatcher.clear_surveys()

    socket =
      socket
      |> assign(inv_markers: [])
      |> push_event("inv_markers", %{markers: []})

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_sharing", _params, socket) do
    socket = assign(socket, sharing: true)
    socket = push_event(socket, "start_capture", %{})
    {:noreply, socket}
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
  def handle_event("set_detect_zone", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}
    require Logger
    Logger.info("[detect zone] set to x1=#{x1} y1=#{y1} x2=#{x2} y2=#{y2}")
    {:noreply, assign(socket, detect_zone: zone)}
  end

  @impl true
  def handle_event("start_set_zone", _params, socket) do
    socket = push_event(socket, "start_set_zone", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_detect_zone", _params, socket) do
    socket = assign(socket, detect_zone: nil)
    socket = push_event(socket, "clear_detect_zone", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_set_inv_zone", _params, socket) do
    socket = push_event(socket, "start_set_inv_zone", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_inv_zone", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    {:noreply, assign(socket, inv_zone: %{x1: x1, y1: y1, x2: x2, y2: y2})}
  end

  @impl true
  def handle_event("clear_inv_zone", _params, socket) do
    socket =
      socket
      |> assign(inv_zone: nil, inv_markers: [])
      |> push_event("clear_inv_zone", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("scan_frame", %{"data" => data_url}, socket) do
    require Logger
    Logger.info("scan_frame received, data_url size: #{byte_size(data_url)}")

    png_binary =
      data_url
      |> String.split(",", parts: 2)
      |> List.last()
      |> Base.decode64!()

    Logger.info("scan_frame decoded PNG: #{byte_size(png_binary)} bytes")

    zone = socket.assigns.detect_zone

    survey_result = GorgonSurvey.SurveyDetector.detect(png_binary)

    # Map coordinates from cropped image back to full screen
    map_to_screen = fn {x_pct, y_pct} ->
      if zone do
        {zone.x1 + x_pct / 100 * (zone.x2 - zone.x1), zone.y1 + y_pct / 100 * (zone.y2 - zone.y1)}
      else
        {x_pct, y_pct}
      end
    end

    # Place detected survey circles
    case survey_result do
      {:ok, circles} ->
        circles = Enum.map(circles, map_to_screen)
        unplaced = Enum.filter(socket.assigns.app_state.surveys, &is_nil(&1.x_pct))

        Logger.info(
          "scan_frame: detected #{length(circles)} circles, #{length(unplaced)} unplaced surveys"
        )

        Enum.zip(unplaced, circles)
        |> Enum.each(fn {survey, {x_pct, y_pct}} ->
          Logger.info("scan_frame: placing survey #{survey.id} at (#{x_pct}, #{y_pct})")
          LogWatcher.place_survey(survey.id, x_pct, y_pct)
        end)

      other ->
        Logger.warning("scan_frame: detect returned #{inspect(other)}")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_inv_item", %{"x_pct" => x_pct, "y_pct" => y_pct}, socket) do
    surveys = socket.assigns.app_state.surveys
    inv_markers = socket.assigns[:inv_markers] || []

    # Assign the next survey number based on how many markers are already placed
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
    inv_markers =
      (socket.assigns[:inv_markers] || [])
      |> remove_and_shift_inv_markers(number)

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
  def handle_event("set_log_folder", %{"folder" => folder}, socket) do
    ConfigStore.put("log_folder", folder)
    socket = assign(socket, log_folder: folder)

    case GorgonSurvey.Application.start_log_watcher(folder) do
      {:ok, _pid} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start watcher: #{reason}")}
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

  defp serialize_state(socket) do
    app_state = socket.assigns.app_state

    %{
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
      placing_survey: socket.assigns.placing_survey
    }
  end
end
