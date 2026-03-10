defmodule GorgonSurvey.AppState do
  @moduledoc "Pure data structure and functions for application state."

  defstruct surveys: [],
            motherlode: %{readings: [], estimated_location: nil},
            zone: nil,
            route_order: [],
            next_id: 1,
            next_number: 1

  def new, do: %__MODULE__{}

  def add_survey(state, %{name: name, dx: dx, dy: dy}) do
    survey = %{
      id: state.next_id,
      survey_number: state.next_number,
      name: name,
      dx: dx,
      dy: dy,
      x_pct: nil,
      y_pct: nil,
      collected: false
    }

    %{state | surveys: state.surveys ++ [survey], next_id: state.next_id + 1, next_number: state.next_number + 1}
  end

  def place_survey(state, id, x_pct, y_pct) do
    surveys =
      Enum.map(state.surveys, fn
        %{id: ^id} = s -> %{s | x_pct: x_pct, y_pct: y_pct}
        s -> s
      end)

    %{state | surveys: surveys}
  end

  def toggle_collected(state, id) do
    surveys =
      Enum.map(state.surveys, fn
        %{id: ^id} = s -> %{s | collected: !s.collected}
        s -> s
      end)

    %{state | surveys: surveys}
  end

  def delete_survey(state, id) do
    %{state | surveys: Enum.reject(state.surveys, &(&1.id == id))}
  end

  def clear_surveys(state) do
    %{state | surveys: [], next_number: 1}
  end

  def add_motherlode_reading(state, reading) do
    readings = state.motherlode.readings ++ [reading]
    motherlode = %{state.motherlode | readings: readings}
    %{state | motherlode: motherlode}
  end
end
