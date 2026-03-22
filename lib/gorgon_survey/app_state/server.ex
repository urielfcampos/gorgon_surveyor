defmodule GorgonSurvey.AppState.Server do
  @moduledoc """
  GenServer that holds and mutates AppState, broadcasting changes via PubSub.

  This is the single stateful process for the application. It wraps the pure
  `AppState` struct, applying mutations through the struct's functions and
  broadcasting the updated state to all subscribers after every change.

  ## Named process

  Started in the supervision tree as a named process (`__MODULE__`). All client
  functions default to this name, so callers can simply write:

      AppState.Server.place_survey(id, x, y)

  An explicit server reference can be passed as the first argument for testing.

  ## Broadcasting

  Every mutation broadcasts `{:state_updated, %AppState{}}` on the `"game_state"`
  PubSub topic. Both `SurveyLive` and `OverlayLive` subscribe to this topic to
  keep their UI in sync.

  ## Producers

  - `LogWatcher` — forwards parsed log events (surveys, motherlode distances)
  - `SurveyLive` / `OverlayLive` — user-initiated mutations (place, collect, delete)
  - `CaptureController` — auto-detect places surveys from image processing results
  """

  use GenServer

  alias GorgonSurvey.AppState

  @pubsub_topic "game_state"

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  def add_survey(server \\ __MODULE__, data) do
    GenServer.cast(server, {:add_survey, data})
  end

  def place_survey(server \\ __MODULE__, id, x_pct, y_pct) do
    GenServer.cast(server, {:place_survey, id, x_pct, y_pct})
  end

  def toggle_collected(server \\ __MODULE__, id) do
    GenServer.cast(server, {:toggle_collected, id})
  end

  def delete_survey(server \\ __MODULE__, id) do
    GenServer.cast(server, {:delete_survey, id})
  end

  def clear_surveys(server \\ __MODULE__) do
    GenServer.cast(server, :clear_surveys)
  end

  def set_zone(server \\ __MODULE__, zone) do
    GenServer.cast(server, {:set_zone, zone})
  end

  def add_pending_motherlode(server \\ __MODULE__, meters) do
    GenServer.cast(server, {:add_pending_motherlode, meters})
  end

  def complete_motherlode_reading(server \\ __MODULE__, x_pct, y_pct) do
    GenServer.cast(server, {:complete_motherlode_reading, x_pct, y_pct})
  end

  def delete_motherlode_reading(server \\ __MODULE__, index) do
    GenServer.cast(server, {:delete_motherlode_reading, index})
  end

  def clear_motherlode(server \\ __MODULE__) do
    GenServer.cast(server, :clear_motherlode)
  end

  # Server callbacks

  @impl true
  def init(:ok) do
    {:ok, %{app_state: AppState.new()}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.app_state, state}
  end

  @impl true
  def handle_cast({:add_survey, data}, state) do
    {:noreply, update_and_broadcast(state, &AppState.add_survey(&1, data))}
  end

  @impl true
  def handle_cast({:place_survey, id, x_pct, y_pct}, state) do
    {:noreply, update_and_broadcast(state, &AppState.place_survey(&1, id, x_pct, y_pct))}
  end

  @impl true
  def handle_cast({:toggle_collected, id}, state) do
    {:noreply, update_and_broadcast(state, &AppState.toggle_collected(&1, id))}
  end

  @impl true
  def handle_cast({:delete_survey, id}, state) do
    {:noreply, update_and_broadcast(state, &AppState.delete_survey(&1, id))}
  end

  @impl true
  def handle_cast(:clear_surveys, state) do
    {:noreply, update_and_broadcast(state, &AppState.clear_surveys/1)}
  end

  @impl true
  def handle_cast({:set_zone, zone}, state) do
    {:noreply, update_and_broadcast(state, fn app -> %{app | zone: zone} end)}
  end

  @impl true
  def handle_cast({:add_pending_motherlode, meters}, state) do
    {:noreply, update_and_broadcast(state, &AppState.add_pending_motherlode(&1, meters))}
  end

  @impl true
  def handle_cast({:complete_motherlode_reading, x_pct, y_pct}, state) do
    {:noreply,
     update_and_broadcast(state, &AppState.complete_motherlode_reading(&1, x_pct, y_pct))}
  end

  @impl true
  def handle_cast({:delete_motherlode_reading, index}, state) do
    {:noreply, update_and_broadcast(state, &AppState.delete_motherlode_reading(&1, index))}
  end

  @impl true
  def handle_cast(:clear_motherlode, state) do
    {:noreply, update_and_broadcast(state, &AppState.clear_motherlode/1)}
  end

  defp update_and_broadcast(state, fun) do
    app_state = fun.(state.app_state)

    Phoenix.PubSub.broadcast(
      GorgonSurvey.PubSub,
      @pubsub_topic,
      {:state_updated, app_state}
    )

    %{state | app_state: app_state}
  end
end
