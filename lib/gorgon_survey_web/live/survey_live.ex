defmodule GorgonSurveyWeb.SurveyLive do
  use GorgonSurveyWeb, :live_view

  alias GorgonSurvey.LogWatcher
  alias GorgonSurvey.ConfigStore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
    end

    state = LogWatcher.get_state()
    log_folder = ConfigStore.get("log_folder", "")

    {:ok, assign(socket,
      app_state: state,
      sharing: false,
      placing_survey: nil,
      log_folder: log_folder
    )}
  end

  @impl true
  def handle_info({:state_updated, app_state}, socket) do
    socket = assign(socket, app_state: app_state)
    socket = push_event(socket, "state_updated", serialize_state(app_state))

    # If a new unplaced survey arrived, prompt placement
    unplaced = Enum.find(app_state.surveys, &is_nil(&1.x_pct))
    socket = if unplaced && socket.assigns.placing_survey == nil do
      assign(socket, placing_survey: unplaced.id)
    else
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_survey", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    LogWatcher.place_survey(id, x, y)
    {:noreply, assign(socket, placing_survey: nil)}
  end

  @impl true
  def handle_event("toggle_collected", %{"id" => id}, socket) do
    LogWatcher.toggle_collected(id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_surveys", _params, socket) do
    LogWatcher.clear_surveys()
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_sharing", _params, socket) do
    {:noreply, assign(socket, sharing: true)}
  end

  @impl true
  def handle_event("set_log_folder", %{"folder" => folder}, socket) do
    ConfigStore.put("log_folder", folder)
    {:noreply, assign(socket, log_folder: folder)}
  end

  defp serialize_state(app_state) do
    %{
      surveys: Enum.map(app_state.surveys, fn s ->
        %{id: s.id, survey_number: s.survey_number, name: s.name,
          dx: s.dx, dy: s.dy, x_pct: s.x_pct, y_pct: s.y_pct,
          collected: s.collected}
      end),
      placing_survey: nil
    }
  end
end
