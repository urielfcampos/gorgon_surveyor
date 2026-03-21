defmodule GorgonSurveyWeb.SurveyLiveTest do
  use GorgonSurveyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders page with select game window button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Select Game Window"
    assert html =~ "Surveys"
  end

  test "renders without a running LogWatcher", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Select Game Window"
  end
end
