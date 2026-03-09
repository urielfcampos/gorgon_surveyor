defmodule GorgonSurveyWeb.SurveyLiveTest do
  use GorgonSurveyWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    # Start a LogWatcher with empty temp log
    tmp_dir = Path.join(System.tmp_dir!(), "liveview_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    tmp = Path.join(tmp_dir, "chat.log")
    File.write!(tmp, "")
    {:ok, pid} = GorgonSurvey.LogWatcher.start_link(log_path: tmp, name: GorgonSurvey.LogWatcher)
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm_rf!(tmp_dir)
    end)
    :ok
  end

  test "renders page with share screen button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
    assert html =~ "Surveys"
  end

  test "displays survey when state updates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Simulate a survey arriving
    new_state = GorgonSurvey.AppState.new()
      |> GorgonSurvey.AppState.add_survey(%{name: "Good Metal Slab", dx: -815, dy: 1441})
    Phoenix.PubSub.broadcast(GorgonSurvey.PubSub, "game_state", {:state_updated, new_state})

    # LiveView should re-render with the survey
    html = render(view)
    assert html =~ "Good Metal Slab"
  end
end
