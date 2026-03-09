defmodule GorgonSurveyWeb.SurveyLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher
  alias GorgonSurvey.ConfigStore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
    end

    state = try do
      LogWatcher.get_state()
    catch
      :exit, _ -> GorgonSurvey.AppState.new()
    end
    log_folder = ConfigStore.get("log_folder", "")

    {:ok, assign(socket,
      app_state: state,
      sharing: false,
      placing_survey: nil,
      log_folder: log_folder,
      auto_detect: false,
      detect_zone: nil,
      inv_zone: nil,
      locked: false
    )}
  end

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    app_state = if socket.assigns.locked do
      # When locked, only update existing surveys (positions, collected status)
      # but don't add new ones
      existing_ids = MapSet.new(socket.assigns.app_state.surveys, & &1.id)
      surveys = Enum.filter(app_state.surveys, &MapSet.member?(existing_ids, &1.id))
      %{app_state | surveys: surveys}
    else
      app_state
    end

    socket = assign(socket, app_state: app_state)

    # If a new unplaced survey arrived, prompt placement
    unplaced = Enum.find(app_state.surveys, &is_nil(&1.x_pct))
    socket = if unplaced && socket.assigns.placing_survey == nil do
      assign(socket, placing_survey: unplaced.id)
    else
      socket
    end

    socket = push_event(socket, "state_updated", serialize_state(socket))
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
  def handle_event("toggle_lock", _params, socket) do
    {:noreply, assign(socket, locked: !socket.assigns.locked)}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    LogWatcher.clear_surveys()
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_sharing", _params, socket) do
    socket = assign(socket, sharing: true)
    socket = push_event(socket, "start_capture", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auto_detect", _params, socket) do
    auto_detect = !socket.assigns.auto_detect
    socket = assign(socket, auto_detect: auto_detect)

    socket = if auto_detect do
      push_event(socket, "start_auto_detect", %{})
    else
      push_event(socket, "stop_auto_detect", %{})
    end

    {:noreply, socket}
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
    socket = assign(socket, inv_zone: nil)
    socket = push_event(socket, "clear_inv_zone", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_event("scan_frame", %{"data" => data_url}, socket) do
    require Logger
    Logger.info("scan_frame received, data_url size: #{byte_size(data_url)}")

    png_binary = data_url
      |> String.split(",", parts: 2)
      |> List.last()
      |> Base.decode64!()

    Logger.info("scan_frame decoded PNG: #{byte_size(png_binary)} bytes")

    zone = socket.assigns.detect_zone

    # Detect surveys and player in the cropped image
    survey_result = GorgonSurvey.SurveyDetector.detect(png_binary)
    player_result = GorgonSurvey.SurveyDetector.detect_player(png_binary)

    # Map coordinates from cropped image back to full screen
    map_to_screen = fn {x_pct, y_pct} ->
      if zone do
        {zone.x1 + (x_pct / 100) * (zone.x2 - zone.x1),
         zone.y1 + (y_pct / 100) * (zone.y2 - zone.y1)}
      else
        {x_pct, y_pct}
      end
    end

    # Place detected survey circles
    case survey_result do
      {:ok, circles} ->
        circles = Enum.map(circles, map_to_screen)
        unplaced = Enum.filter(socket.assigns.app_state.surveys, &is_nil(&1.x_pct))
        Logger.info("scan_frame: detected #{length(circles)} circles, #{length(unplaced)} unplaced surveys")

        Enum.zip(unplaced, circles)
        |> Enum.each(fn {survey, {x_pct, y_pct}} ->
          Logger.info("scan_frame: placing survey #{survey.id} at (#{x_pct}, #{y_pct})")
          LogWatcher.place_survey(survey.id, x_pct, y_pct)
        end)

      other ->
        Logger.warning("scan_frame: detect returned #{inspect(other)}")
    end

    # Send player position to JS overlay and auto-collect nearby surveys
    socket = case player_result do
      {:ok, {px, py}} ->
        {full_x, full_y} = map_to_screen.({px, py})

        # Auto-collect: if player is within 3% of a placed uncollected survey, mark collected
        socket.assigns.app_state.surveys
        |> Enum.filter(fn s -> s.x_pct != nil and not s.collected end)
        |> Enum.each(fn s ->
          dist = :math.sqrt(:math.pow(s.x_pct - full_x, 2) + :math.pow(s.y_pct - full_y, 2))
          if dist < 3.0 do
            Logger.info("auto-collect: survey #{s.id} (dist=#{Float.round(dist, 1)}%)")
            LogWatcher.toggle_collected(s.id)
          end
        end)

        push_event(socket, "player_position", %{x_pct: full_x, y_pct: full_y})
      _ ->
        socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("scan_inventory", %{"data" => data_url}, socket) do
    require Logger

    png_binary = data_url
      |> String.split(",", parts: 2)
      |> List.last()
      |> Base.decode64!()

    inv_zone = socket.assigns.inv_zone

    case GorgonSurvey.SurveyDetector.detect_inventory(png_binary) do
      {:ok, icons} ->
        # Map back to full screen coords and assign survey numbers
        surveys = socket.assigns.app_state.surveys
        markers = icons
          |> Enum.with_index(1)
          |> Enum.map(fn {{x_pct, y_pct}, idx} ->
            number = case Enum.at(surveys, idx - 1) do
              nil -> idx
              s -> s.survey_number
            end
            full_x = if inv_zone, do: inv_zone.x1 + (x_pct / 100) * (inv_zone.x2 - inv_zone.x1), else: x_pct
            full_y = if inv_zone, do: inv_zone.y1 + (y_pct / 100) * (inv_zone.y2 - inv_zone.y1), else: y_pct
            %{x_pct: full_x, y_pct: full_y, number: number}
          end)

        Logger.info("[scan_inventory] detected #{length(icons)} survey icons")
        socket = push_event(socket, "inv_markers", %{markers: markers})
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
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

  defp serialize_state(socket) do
    app_state = socket.assigns.app_state
    %{
      surveys: Enum.map(app_state.surveys, fn s ->
        %{id: s.id, survey_number: s.survey_number, name: s.name,
          dx: s.dx, dy: s.dy, x_pct: s.x_pct, y_pct: s.y_pct,
          collected: s.collected}
      end),
      placing_survey: socket.assigns.placing_survey
    }
  end
end
