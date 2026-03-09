defmodule GorgonSurvey.LogParser do
  @moduledoc "Parses Project Gorgon chat log lines into structured events."

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
