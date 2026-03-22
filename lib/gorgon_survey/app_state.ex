defmodule GorgonSurvey.AppState do
  @moduledoc """
  Pure data structure and functions for application state.

  This module defines the `%AppState{}` struct and pure transformation functions
  that operate on it. It has no side effects — no GenServer, no PubSub, no I/O.
  The stateful wrapper is `AppState.Server`.

  ## State structure

  - `surveys` — ordered list of survey maps, each with an auto-incrementing `id`,
    a display `survey_number`, the parsed `name`, directional offsets (`dx`, `dy`),
    optional map coordinates (`x_pct`, `y_pct` as percentages), and a `collected` flag.
  - `motherlode` — map tracking motherlode triangulation: `readings` (list of
    `%{x_pct, y_pct, meters}`), `pending_meters` (distance from the latest log line
    awaiting a map click), and `estimated_location` (computed after 3+ readings via
    `Trilateration.estimate/1`).
  - `next_id` / `next_number` — auto-incrementing counters for survey identity.

  ## Survey lifecycle

  1. `add_survey/2` — a new survey is parsed from the chat log. Coordinates are nil
     until the user clicks the map or auto-detect places them.
  2. `place_survey/4` — sets `x_pct`/`y_pct` on a survey by id.
  3. `toggle_collected/2` — marks a survey as collected (or undoes it).
  4. `delete_survey/2` / `clear_surveys/1` — removal.

  ## Motherlode lifecycle

  1. `add_pending_motherlode/2` — stores a distance reading from the log.
  2. `complete_motherlode_reading/3` — user clicks the map to associate the pending
     distance with a position. After 3+ readings, triggers trilateration.
  3. `delete_motherlode_reading/2` / `clear_motherlode/1` — removal.
  """

  defstruct surveys: [],
            motherlode: %{readings: [], estimated_location: nil, pending_meters: nil},
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

    %{
      state
      | surveys: state.surveys ++ [survey],
        next_id: state.next_id + 1,
        next_number: state.next_number + 1
    }
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

  def add_pending_motherlode(state, meters) do
    motherlode = %{state.motherlode | pending_meters: meters}
    %{state | motherlode: motherlode}
  end

  def complete_motherlode_reading(%{motherlode: %{pending_meters: nil}} = state, _x_pct, _y_pct) do
    state
  end

  def complete_motherlode_reading(state, x_pct, y_pct) do
    reading = %{x_pct: x_pct, y_pct: y_pct, meters: state.motherlode.pending_meters}
    readings = state.motherlode.readings ++ [reading]

    estimated_location =
      if length(readings) >= 3 do
        GorgonSurvey.Trilateration.estimate(readings)
      else
        nil
      end

    motherlode = %{
      readings: readings,
      pending_meters: nil,
      estimated_location: estimated_location
    }

    %{state | motherlode: motherlode}
  end

  def delete_motherlode_reading(state, index) do
    readings = List.delete_at(state.motherlode.readings, index)

    estimated_location =
      if length(readings) >= 3 do
        GorgonSurvey.Trilateration.estimate(readings)
      else
        nil
      end

    motherlode = %{state.motherlode | readings: readings, estimated_location: estimated_location}
    %{state | motherlode: motherlode}
  end

  def clear_motherlode(state) do
    %{state | motherlode: %{readings: [], estimated_location: nil, pending_meters: nil}}
  end
end
