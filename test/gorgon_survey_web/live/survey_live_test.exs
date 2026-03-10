defmodule GorgonSurveyWeb.SurveyLiveTest do
  use GorgonSurveyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders page with share screen button", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
    assert html =~ "Surveys"
  end

  test "renders without a running LogWatcher", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Share Screen"
  end
end
