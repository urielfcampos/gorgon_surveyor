defmodule GorgonSurveyWeb.CaptureController do
  @moduledoc """
  API endpoint for screenshot-based survey auto-detection.

  Called by the Tauri sidecar at `POST /api/capture` with either a file upload
  or a filesystem path to a screenshot. The pipeline:

  1. **Extract image** — reads the PNG from the uploaded file or path.
  2. **Crop to zone** — if detection zone and overlay geometry are provided,
     crops the full-monitor screenshot down to just the minimap region. Zone
     coordinates are percentages of the overlay window; overlay geometry gives
     the overlay's position and size on screen in pixels.
  3. **Detect circles** — passes the (possibly cropped) image to `SurveyDetector`
     which returns percentage coordinates of detected red circles.
  4. **Map to overlay space** — converts zone-relative detection coordinates back
     to overlay-relative percentages.
  5. **Place surveys** — pairs detected circles with unplaced surveys (those
     without coordinates) in order, and calls `AppState.Server.place_survey/3`
     for each match.

  ## Parameters

  - `file` — multipart file upload (PNG screenshot)
  - `path` — alternative: filesystem path to a screenshot (used by Tauri sidecar)
  - `zone_x1`, `zone_y1`, `zone_x2`, `zone_y2` — detection zone as overlay percentages
  - `overlay_x`, `overlay_y`, `overlay_w`, `overlay_h` — overlay window geometry in pixels
  """

  use GorgonSurveyWeb, :controller

  alias GorgonSurvey.AppState

  require Logger

  def create(conn, params) do
    Logger.info("capture params: #{inspect(Map.keys(params))}")

    with {:ok, png_binary} <- extract_image(params),
         zone = parse_zone(params),
         overlay = parse_overlay_geometry(params),
         cropped = crop_to_zone(png_binary, zone, overlay),
         {:ok, circles} <- GorgonSurvey.SurveyDetector.detect(cropped) do
      circles = Enum.map(circles, &map_to_overlay(&1, zone))
      place_detected_surveys(circles)
      json(conn, %{ok: true, detected: length(circles)})
    else
      :no_image ->
        conn |> put_status(400) |> json(%{error: "No file or path provided"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{ok: false, error: inspect(reason)})
    end
  end

  defp extract_image(%{"file" => upload}), do: {:ok, File.read!(upload.path)}
  defp extract_image(%{"path" => path}), do: {:ok, File.read!(path)}
  defp extract_image(_), do: :no_image

  defp place_detected_surveys(circles) do
    app_state = AppState.Server.get_state()
    unplaced = Enum.filter(app_state.surveys, &is_nil(&1.x_pct))

    Logger.info(
      "capture: detected #{length(circles)} circles, #{length(unplaced)} unplaced surveys"
    )

    Enum.zip(unplaced, circles)
    |> Enum.each(fn {survey, {x_pct, y_pct}} ->
      Logger.info("capture: placing survey #{survey.id} at (#{x_pct}, #{y_pct})")
      AppState.Server.place_survey(survey.id, x_pct, y_pct)
    end)
  end

  defp parse_zone(%{"zone_x1" => x1, "zone_y1" => y1, "zone_x2" => x2, "zone_y2" => y2}) do
    %{x1: to_float(x1), y1: to_float(y1), x2: to_float(x2), y2: to_float(y2)}
  end

  defp parse_zone(_), do: nil

  defp parse_overlay_geometry(%{
         "overlay_x" => x,
         "overlay_y" => y,
         "overlay_w" => w,
         "overlay_h" => h
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
