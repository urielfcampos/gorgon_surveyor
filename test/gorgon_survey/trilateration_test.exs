defmodule GorgonSurvey.TrilaterationTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.Trilateration

  test "returns nil for fewer than 3 readings" do
    assert Trilateration.estimate([]) == nil

    assert Trilateration.estimate([
             %{x_pct: 10.0, y_pct: 10.0, meters: 100},
             %{x_pct: 20.0, y_pct: 20.0, meters: 50}
           ]) == nil
  end

  test "estimates location from 3 equidistant readings" do
    # Target is at (50, 50). Three readings at known distances.
    # All at distance 30 "meters" from center.
    readings = [
      %{x_pct: 50.0, y_pct: 20.0, meters: 30},
      %{x_pct: 24.02, y_pct: 65.0, meters: 30},
      %{x_pct: 75.98, y_pct: 65.0, meters: 30}
    ]

    {x, y} = Trilateration.estimate(readings)
    assert_in_delta x, 50.0, 2.0
    assert_in_delta y, 50.0, 2.0
  end

  test "estimates location from 4 readings with varying distances" do
    # Target at (70, 30)
    target = {70.0, 30.0}

    readings =
      for {px, py} <- [{20.0, 20.0}, {80.0, 80.0}, {10.0, 60.0}, {90.0, 10.0}] do
        meters =
          :math.sqrt(:math.pow(px - elem(target, 0), 2) + :math.pow(py - elem(target, 1), 2))

        %{x_pct: px, y_pct: py, meters: meters}
      end

    {x, y} = Trilateration.estimate(readings)
    assert_in_delta x, 70.0, 2.0
    assert_in_delta y, 30.0, 2.0
  end
end
