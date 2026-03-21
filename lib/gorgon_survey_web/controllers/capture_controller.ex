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
      case GorgonSurvey.SurveyDetector.detect(png_binary) do
        {:ok, circles} ->
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
end
