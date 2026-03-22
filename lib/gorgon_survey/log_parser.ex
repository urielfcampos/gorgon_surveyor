defmodule GorgonSurvey.LogParser do
  @moduledoc """
  Parses Project Gorgon chat log lines into structured events.

  The game writes survey and motherlode events to `chat.log` in plain text.
  This module uses regex patterns to recognize three kinds of lines:

  ## Recognized patterns

  - **Survey directions** — `"The Good Metal Slab is 815m west and 1441m north."`
    Parsed into `{:survey, %{name: "Good Metal Slab", dx: -815, dy: 1441}}`.
    Directions are converted to signed offsets: east/north are positive,
    west/south are negative.

  - **Motherlode distance** — `"The treasure is 500 meters away"`
    Parsed into `{:motherlode, %{meters: 500}}`.

  - **Survey collected** — `"You collected the survey reward"`
    Returns `:survey_collected` (currently unused but recognized).

  All other lines return `nil`.
  """

  @survey_regex ~r/The (.+?) is (\d+)m (east|west) and (\d+)m (north|south)\./
  @motherlode_regex ~r/The treasure is (\d+) meters away/
  @collected_regex ~r/You collected the survey reward/

  def parse_line(line) do
    cond do
      match = Regex.run(@motherlode_regex, line) ->
        [_, meters] = match
        {:motherlode, %{meters: String.to_integer(meters)}}

      match = Regex.run(@survey_regex, line) ->
        [_, name, dist1, dir1, dist2, dir2] = match
        dx = directional_value(String.to_integer(dist1), dir1)
        dy = directional_value(String.to_integer(dist2), dir2)
        {:survey, %{name: name, dx: dx, dy: dy}}

      Regex.match?(@collected_regex, line) ->
        :survey_collected

      true ->
        nil
    end
  end

  defp directional_value(val, "east"), do: val
  defp directional_value(val, "west"), do: -val
  defp directional_value(val, "north"), do: val
  defp directional_value(val, "south"), do: -val
end
