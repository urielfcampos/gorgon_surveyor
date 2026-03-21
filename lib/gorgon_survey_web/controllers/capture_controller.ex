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
      zone = parse_zone(params)
      overlay = parse_overlay_geometry(params)

      # Crop the monitor screenshot to the detect zone's screen region
      png_binary = crop_to_zone(png_binary, zone, overlay)

      case GorgonSurvey.SurveyDetector.detect(png_binary) do
        {:ok, circles} ->
          # Detected coords are zone-relative percentages — map to overlay space
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

  defp parse_zone(%{"zone_x1" => x1, "zone_y1" => y1, "zone_x2" => x2, "zone_y2" => y2}) do
    %{x1: to_float(x1), y1: to_float(y1), x2: to_float(x2), y2: to_float(y2)}
  end

  defp parse_zone(_), do: nil

  defp parse_overlay_geometry(%{
         "overlay_x" => x, "overlay_y" => y,
         "overlay_w" => w, "overlay_h" => h
       }) do
    %{x: to_float(x), y: to_float(y), w: to_float(w), h: to_float(h)}
  end

  defp parse_overlay_geometry(_), do: nil

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> String.to_integer(v) * 1.0
    end
  end

  # Crop monitor screenshot to the detect zone's screen region.
  # Zone coords are percentages of the overlay window.
  # Overlay geometry is the overlay's position/size on screen in pixels.
  defp crop_to_zone(png_binary, nil, _overlay), do: png_binary
  defp crop_to_zone(png_binary, _zone, nil), do: png_binary

  defp crop_to_zone(png_binary, zone, overlay) do
    case Vix.Vips.Image.new_from_buffer(png_binary) do
      {:ok, image} ->
        img_w = Vix.Vips.Image.width(image)
        img_h = Vix.Vips.Image.height(image)

        # Convert overlay-relative zone percentages to screen pixel coordinates
        left = round(overlay.x + zone.x1 / 100 * overlay.w) |> max(0) |> min(img_w - 1)
        top = round(overlay.y + zone.y1 / 100 * overlay.h) |> max(0) |> min(img_h - 1)
        width = round((zone.x2 - zone.x1) / 100 * overlay.w) |> max(1) |> min(img_w - left)
        height = round((zone.y2 - zone.y1) / 100 * overlay.h) |> max(1) |> min(img_h - top)

        Logger.info(
          "crop: overlay=#{round(overlay.x)},#{round(overlay.y)} #{round(overlay.w)}x#{round(overlay.h)}, " <>
            "zone crop=#{left},#{top} #{width}x#{height} from #{img_w}x#{img_h}"
        )

        with {:ok, cropped} <- Vix.Vips.Operation.extract_area(image, left, top, width, height),
             {:ok, buffer} <- Vix.Vips.Image.write_to_buffer(cropped, ".png") do
          buffer
        else
          _ -> png_binary
        end

      _ ->
        png_binary
    end
  end

  # Map zone-relative percentages back to overlay percentages
  defp map_to_overlay({x_pct, y_pct}, nil), do: {x_pct, y_pct}

  defp map_to_overlay({x_pct, y_pct}, zone) do
    {
      zone.x1 + x_pct / 100 * (zone.x2 - zone.x1),
      zone.y1 + y_pct / 100 * (zone.y2 - zone.y1)
    }
  end
end
