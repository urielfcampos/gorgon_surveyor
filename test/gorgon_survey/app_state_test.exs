defmodule GorgonSurvey.AppStateTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.AppState

  test "new/0 returns empty state" do
    state = AppState.new()
    assert state.surveys == []
    assert state.motherlode == %{readings: [], estimated_location: nil, pending_meters: nil}
    assert state.zone == nil
    assert state.route_order == []
  end

  test "add_survey/2 adds a survey with incrementing number" do
    state = AppState.new()
    state = AppState.add_survey(state, %{name: "Good Metal Slab", dx: -815, dy: 1441})
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.survey_number == 1
    assert s.name == "Good Metal Slab"
    assert s.x_pct == nil
  end

  test "place_survey/3 sets coordinates" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "Slab", dx: 0, dy: 0})

    [survey] = state.surveys
    state = AppState.place_survey(state, survey.id, 50.5, 30.2)
    [placed] = state.surveys
    assert placed.x_pct == 50.5
    assert placed.y_pct == 30.2
  end

  test "toggle_collected/2 flips collected flag" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "Slab", dx: 0, dy: 0})

    [survey] = state.surveys
    assert survey.collected == false
    state = AppState.toggle_collected(state, survey.id)
    [toggled] = state.surveys
    assert toggled.collected == true
  end

  test "clear_surveys/1 removes all surveys" do
    state =
      AppState.new()
      |> AppState.add_survey(%{name: "A", dx: 0, dy: 0})
      |> AppState.add_survey(%{name: "B", dx: 1, dy: 1})
      |> AppState.clear_surveys()

    assert state.surveys == []
  end

  test "new/0 motherlode has pending_meters field" do
    state = AppState.new()
    assert state.motherlode.pending_meters == nil
  end

  test "add_pending_motherlode/2 sets pending_meters" do
    state = AppState.new() |> AppState.add_pending_motherlode(500)
    assert state.motherlode.pending_meters == 500
  end

  test "add_pending_motherlode/2 overwrites existing pending" do
    state =
      AppState.new()
      |> AppState.add_pending_motherlode(500)
      |> AppState.add_pending_motherlode(300)

    assert state.motherlode.pending_meters == 300
  end

  test "complete_motherlode_reading/3 moves pending to readings" do
    state =
      AppState.new()
      |> AppState.add_pending_motherlode(500)
      |> AppState.complete_motherlode_reading(25.0, 75.0)

    assert state.motherlode.pending_meters == nil
    assert length(state.motherlode.readings) == 1
    [r] = state.motherlode.readings
    assert r.x_pct == 25.0
    assert r.y_pct == 75.0
    assert r.meters == 500
  end

  test "complete_motherlode_reading/3 with no pending is no-op" do
    state = AppState.new() |> AppState.complete_motherlode_reading(25.0, 75.0)
    assert state.motherlode.readings == []
  end

  test "delete_motherlode_reading/2 removes by index" do
    state =
      AppState.new()
      |> AppState.add_pending_motherlode(100)
      |> AppState.complete_motherlode_reading(10.0, 10.0)
      |> AppState.add_pending_motherlode(200)
      |> AppState.complete_motherlode_reading(20.0, 20.0)
      |> AppState.delete_motherlode_reading(0)

    assert length(state.motherlode.readings) == 1
    [r] = state.motherlode.readings
    assert r.meters == 200
  end

  test "clear_motherlode/1 resets all motherlode data" do
    state =
      AppState.new()
      |> AppState.add_pending_motherlode(500)
      |> AppState.complete_motherlode_reading(25.0, 75.0)
      |> AppState.clear_motherlode()

    assert state.motherlode.readings == []
    assert state.motherlode.pending_meters == nil
    assert state.motherlode.estimated_location == nil
  end
end
