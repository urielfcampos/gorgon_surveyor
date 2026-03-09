defmodule GorgonSurvey.AppStateTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.AppState

  test "new/0 returns empty state" do
    state = AppState.new()
    assert state.surveys == []
    assert state.motherlode == %{readings: [], estimated_location: nil}
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

  test "add_motherlode_reading/2 appends reading" do
    state =
      AppState.new()
      |> AppState.add_motherlode_reading(%{x_pct: 50.0, y_pct: 50.0, meters: 1000})

    assert length(state.motherlode.readings) == 1
  end
end
