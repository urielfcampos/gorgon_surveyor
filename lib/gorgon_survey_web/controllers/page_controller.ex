defmodule GorgonSurveyWeb.PageController do
  use GorgonSurveyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
