defmodule GorgonSurveyWeb.OverlayLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher
  require Logger

  @impl true
  def mount(params, _session, socket) do
    session_id = params["session_id"] || "default"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay:#{session_id}")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay:#{session_id}:zones")
    end

    app_state =
      case GorgonSurvey.SessionManager.get_watcher(session_id) do
        {:ok, pid} -> LogWatcher.get_state(pid)
        _ -> GorgonSurvey.AppState.new()
      end

    {:ok,
     assign(socket,
       session_id: session_id,
       app_state: app_state,
       placing_survey: nil,
       detect_zone: nil,
       inv_zone: nil,
       interactive: false
     ), layout: {GorgonSurveyWeb.Layouts, :overlay_root}}
  end

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    Logger.info("overlay received state_updated: #{length(app_state.surveys)} surveys")

    socket =
      socket
      |> assign(app_state: app_state)
      |> push_event("state_updated", serialize_state(socket, app_state))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:start_set_zone, zone_type}, socket) do
    {:noreply, push_event(socket, "start_set_zone", %{zone_type: zone_type})}
  end

  @impl true
  def handle_info({:clear_zone, :detect}, socket) do
    socket =
      socket
      |> assign(detect_zone: nil)
      |> push_event("zones_updated", %{detect_zone: nil, inv_zone: socket.assigns.inv_zone})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:clear_zone, :inv}, socket) do
    socket =
      socket
      |> assign(inv_zone: nil)
      |> push_event("zones_updated", %{detect_zone: socket.assigns.detect_zone, inv_zone: nil})

    {:noreply, socket}
  end

  # Handle zone_set from PubSub (includes nil for clearing)
  @impl true
  def handle_info({:zone_set, :detect, zone}, socket) do
    socket =
      socket
      |> assign(detect_zone: zone)
      |> push_event("zones_updated", %{detect_zone: zone, inv_zone: socket.assigns.inv_zone})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:zone_set, :inv, zone}, socket) do
    socket =
      socket
      |> assign(inv_zone: zone)
      |> push_event("zones_updated", %{detect_zone: socket.assigns.detect_zone, inv_zone: zone})

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_interact", _params, socket) do
    interactive = !socket.assigns.interactive

    socket =
      socket
      |> assign(interactive: interactive)
      |> push_event("set_interactive", %{interactive: interactive})

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_detect_zone", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}

    socket =
      socket
      |> assign(detect_zone: zone)
      |> push_event("zones_updated", %{detect_zone: zone, inv_zone: socket.assigns[:inv_zone]})

    # Broadcast zone to SurveyLive so sidebar reflects it
    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}:zones",
      {:zone_set, :detect, zone}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_inv_zone", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}

    socket =
      socket
      |> assign(inv_zone: zone)
      |> push_event("zones_updated", %{detect_zone: socket.assigns[:detect_zone], inv_zone: zone})

    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      "overlay:#{socket.assigns.session_id}:zones",
      {:zone_set, :inv, zone}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    case GorgonSurvey.SessionManager.get_watcher(socket.assigns.session_id) do
      {:ok, pid} -> LogWatcher.place_survey(pid, id, x, y)
      _ -> :ok
    end

    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("place_and_collect", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    case GorgonSurvey.SessionManager.get_watcher(socket.assigns.session_id) do
      {:ok, pid} ->
        LogWatcher.place_survey(pid, id, x, y)
        LogWatcher.toggle_collected(pid, id)

      _ ->
        :ok
    end

    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    case GorgonSurvey.SessionManager.get_watcher(socket.assigns.session_id) do
      {:ok, pid} -> LogWatcher.toggle_collected(pid, id)
      _ -> :ok
    end

    {:noreply, socket}
  end

  defp serialize_state(socket, app_state) do
    %{
      mode: :survey,
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
