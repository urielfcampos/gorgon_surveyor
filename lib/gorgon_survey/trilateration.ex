defmodule GorgonSurvey.Trilateration do
  @moduledoc """
  Least-squares trilateration from distance readings.

  Estimates the location of a motherlode on the game map given 3 or more
  distance readings. Each reading is a point on the map (in screen percentage
  coordinates) paired with a distance in meters reported by the game.

  ## Algorithm

  1. **Initial guess** — the centroid of all reading positions.
  2. **Scale estimation** — infers a conversion factor between screen-percentage
     units and game meters by averaging the ratio of reported meters to screen
     distance from the centroid across all readings.
  3. **Gradient descent** — iteratively minimizes the sum of squared errors
     between predicted distances (screen distance * scale) and reported meters.
     Updates the estimated position (x, y) and the scale factor simultaneously.
  4. **Convergence** — stops when position changes fall below a threshold
     (`1.0e-8`) or after 1000 iterations.

  ## Assumptions

  The game map is a fixed overhead view where screen percentages have a roughly
  linear relationship to game-world distances. This holds well for the minimap
  but may degrade at extreme zoom levels or near map edges.
  """

  @max_iterations 1000
  @learning_rate 0.01
  @convergence_threshold 1.0e-8

  @doc """
  Given 3+ readings of %{x_pct, y_pct, meters}, estimate the target location.
  Returns {x_pct, y_pct} or nil if fewer than 3 readings.

  The algorithm infers a scale factor (screen-units-to-meters) from the data
  and uses gradient descent to minimize the sum of squared distance errors.
  """
  def estimate(readings) when length(readings) < 3, do: nil

  def estimate(readings) do
    # Initial guess: centroid of reading positions
    n = length(readings)
    cx = Enum.sum(Enum.map(readings, & &1.x_pct)) / n
    cy = Enum.sum(Enum.map(readings, & &1.y_pct)) / n

    # Initial scale: average ratio of meters to screen distance from centroid
    scale = estimate_scale(readings, cx, cy)

    iterate(readings, cx, cy, scale, 0)
  end

  defp estimate_scale(readings, cx, cy) do
    pairs =
      readings
      |> Enum.map(fn r ->
        screen_dist = :math.sqrt(:math.pow(r.x_pct - cx, 2) + :math.pow(r.y_pct - cy, 2))
        {r.meters, screen_dist}
      end)
      |> Enum.reject(fn {_m, sd} -> sd < 0.001 end)

    case pairs do
      [] ->
        1.0

      pairs ->
        Enum.sum(Enum.map(pairs, fn {m, sd} -> m / sd end)) / length(pairs)
    end
  end

  defp iterate(_readings, x, y, _scale, @max_iterations), do: {x, y}

  defp iterate(readings, x, y, scale, iter) do
    # Compute gradients for x, y, and scale
    {grad_x, grad_y, grad_s} =
      Enum.reduce(readings, {0.0, 0.0, 0.0}, fn r, {gx, gy, gs} ->
        dx = x - r.x_pct
        dy = y - r.y_pct
        screen_dist = :math.sqrt(dx * dx + dy * dy)
        predicted_meters = screen_dist * scale
        error = predicted_meters - r.meters

        if screen_dist < 0.001 do
          {gx, gy, gs}
        else
          # Partial derivatives
          d_x = error * scale * dx / screen_dist
          d_y = error * scale * dy / screen_dist
          d_s = error * screen_dist
          {gx + d_x, gy + d_y, gs + d_s}
        end
      end)

    new_x = x - @learning_rate * grad_x
    new_y = y - @learning_rate * grad_y
    new_scale = scale - @learning_rate * 0.001 * grad_s

    # Convergence check
    if abs(new_x - x) < @convergence_threshold and abs(new_y - y) < @convergence_threshold do
      {new_x, new_y}
    else
      iterate(readings, new_x, new_y, new_scale, iter + 1)
    end
  end
end
