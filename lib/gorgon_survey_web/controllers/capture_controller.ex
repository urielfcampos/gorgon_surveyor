defmodule GorgonSurveyWeb.CaptureController do
  use GorgonSurveyWeb, :controller

  alias GorgonSurvey.LogWatcher

  require Logger

  def create(conn, %{"session_id" => session_id} = params) do
    watcher = {:via, Registry, {GorgonSurvey.SessionRegistry, {:session, session_id}}}

    png_binary =
      cond do
        upload = params["file"] ->
          File.read!(upload.path)

        path = params["path"] ->
          File.read!(path)

        true ->
          nil
      end

    if is_nil(png_binary) do
      conn
      |> put_status(400)
      |> json(%{error: "No file or path provided"})
    else
      # Parse detect zone from params (percentages of overlay window)
      zone = parse_zone(params)

      case GorgonSurvey.SurveyDetector.detect(png_binary) do
        {:ok, circles} ->
          # Map detected coordinates from zone-relative to overlay-relative
          circles = Enum.map(circles, &map_to_overlay(&1, zone))

          app_state = LogWatcher.get_state(watcher)
          unplaced = Enum.filter(app_state.surveys, &is_nil(&1.x_pct))

          Logger.info(
            "capture: detected #{length(circles)} circles, #{length(unplaced)} unplaced surveys"
          )

          Enum.zip(unplaced, circles)
          |> Enum.each(fn {survey, {x_pct, y_pct}} ->
            Logger.info("capture: placing survey #{survey.id} at (#{x_pct}, #{y_pct})")
            LogWatcher.place_survey(watcher, survey.id, x_pct, y_pct)
          end)

          json(conn, %{ok: true, detected: length(circles)})

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{ok: false, error: inspect(reason)})
      end
    end
  end

  # Parse zone from request params. Zone coords are percentages of the overlay.
  defp parse_zone(%{"zone_x1" => x1, "zone_y1" => y1, "zone_x2" => x2, "zone_y2" => y2}) do
    %{
      x1: to_float(x1),
      y1: to_float(y1),
      x2: to_float(x2),
      y2: to_float(y2)
    }
  end

  defp parse_zone(_), do: nil

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(v) when is_binary(v), do: String.to_float(v)

  # Map coordinates from zone-relative percentages to overlay-relative percentages
  defp map_to_overlay({x_pct, y_pct}, nil), do: {x_pct, y_pct}

  defp map_to_overlay({x_pct, y_pct}, zone) do
    {
      zone.x1 + x_pct / 100 * (zone.x2 - zone.x1),
      zone.y1 + y_pct / 100 * (zone.y2 - zone.y1)
    }
  end
end
