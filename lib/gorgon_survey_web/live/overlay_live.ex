defmodule GorgonSurveyWeb.OverlayLive do
  @moduledoc """
  LiveView for the transparent overlay window at `/overlay`.

  Renders a transparent page that the Tauri desktop wrapper displays as an
  always-on-top, click-through window over the game. The overlay's JS hooks
  (`OverlayCanvas`) draw survey markers, route lines, and zone rectangles on
  a canvas that visually sits on top of the game minimap.

  ## Responsibilities

  - **State mirroring** — subscribes to `"game_state"` PubSub and pushes
    serialized state to the JS canvas hook via `push_event("state_updated", ...)`.
  - **Zone drawing** — receives zone setup/clear commands from `SurveyLive` via
    the `"overlay"` PubSub topic and forwards them to JS for rendering.
  - **User interaction** — when in interactive mode (toggled via F12 hotkey),
    handles click events for placing surveys, collecting surveys, and defining
    detection/inventory zones. These mutations are sent to `AppState.Server`.
  - **Zone broadcasting** — when the user defines a zone on the overlay, broadcasts
    it back to `SurveyLive` via `"overlay:zones"` so the sidebar UI reflects it.

  ## PubSub topics

  - Subscribes to `"game_state"` — state updates from `AppState.Server`.
  - Subscribes to `"overlay"` — commands from `SurveyLive` (start_set_zone, clear_zone).
  - Subscribes to `"overlay:zones"` — zone updates (bidirectional with `SurveyLive`).

  ## Layout

  Uses the `:overlay_root` layout which provides a minimal transparent HTML shell
  without the standard app chrome.
  """

  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.AppState
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay")
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "overlay:zones")
    end

    app_state = AppState.Server.get_state()

    {:ok,
     assign(socket,
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
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay:zones", {:zone_set, :detect, zone})

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_inv_zone", %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, socket) do
    zone = %{x1: x1, y1: y1, x2: x2, y2: y2}

    socket =
      socket
      |> assign(inv_zone: zone)
      |> push_event("zones_updated", %{detect_zone: socket.assigns[:detect_zone], inv_zone: zone})

    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "overlay:zones", {:zone_set, :inv, zone})

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    AppState.Server.place_survey(id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("place_and_collect", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    id = parse_id(id)
    AppState.Server.place_survey(id, x, y)
    AppState.Server.toggle_collected(id)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    AppState.Server.toggle_collected(parse_id(id))
    {:noreply, socket}
  end

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id) when is_integer(id), do: id

  defp serialize_state(socket, app_state) do
    surveys = Enum.map(app_state.surveys, &serialize_survey/1)
    readings = Enum.map(app_state.motherlode.readings, &serialize_reading/1)
    estimated_location = serialize_location(app_state.motherlode.estimated_location)

    %{
      mode: :survey,
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
