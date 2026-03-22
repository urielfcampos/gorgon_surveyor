defmodule GorgonSurvey.AppState.ServerTest do
  use ExUnit.Case

  alias GorgonSurvey.AppState

  setup do
    # Use a unique name so tests don't conflict with the application's server
    name = :"app_state_test_#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")
    {:ok, pid} = AppState.Server.start_link(name: name)
    {:ok, server: pid}
  end

  test "starts with empty state", %{server: server} do
    state = AppState.Server.get_state(server)
    assert state.surveys == []
  end

  test "add_survey broadcasts updated state", %{server: server} do
    AppState.Server.add_survey(server, %{name: "Good Metal Slab", dx: -815, dy: 1441})
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert length(state.surveys) == 1
    assert hd(state.surveys).name == "Good Metal Slab"
  end

  test "place_survey updates coordinates", %{server: server} do
    AppState.Server.add_survey(server, %{name: "Slab", dx: 0, dy: 0})
    assert_receive {:state_updated, %AppState{} = state}, 1000

    AppState.Server.place_survey(server, hd(state.surveys).id, 50.0, 30.0)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert hd(state.surveys).x_pct == 50.0
  end

  test "toggle_collected flips flag", %{server: server} do
    AppState.Server.add_survey(server, %{name: "Slab", dx: 0, dy: 0})
    assert_receive {:state_updated, %AppState{} = state}, 1000
    id = hd(state.surveys).id

    AppState.Server.toggle_collected(server, id)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert hd(state.surveys).collected == true
  end

  test "clear_surveys removes all", %{server: server} do
    AppState.Server.add_survey(server, %{name: "A", dx: 0, dy: 0})
    assert_receive {:state_updated, _}, 1000

    AppState.Server.clear_surveys(server)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert state.surveys == []
  end

  test "motherlode flow", %{server: server} do
    AppState.Server.add_pending_motherlode(server, 500)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert state.motherlode.pending_meters == 500

    AppState.Server.complete_motherlode_reading(server, 50.0, 50.0)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert state.motherlode.pending_meters == nil
    assert length(state.motherlode.readings) == 1

    AppState.Server.clear_motherlode(server)
    assert_receive {:state_updated, %AppState{} = state}, 1000
    assert state.motherlode.readings == []
  end
end
