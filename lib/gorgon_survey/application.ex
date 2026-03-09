defmodule GorgonSurvey.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        GorgonSurveyWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:gorgon_survey, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: GorgonSurvey.PubSub},
        log_watcher_child_spec(),
        GorgonSurveyWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GorgonSurvey.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GorgonSurveyWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp log_watcher_child_spec do
    log_folder = Application.get_env(:gorgon_survey, :log_folder)

    if log_folder && log_folder != "" do
      log_path = find_latest_log(log_folder)

      if log_path do
        {GorgonSurvey.LogWatcher, log_path: log_path}
      end
    end
  end

  defp find_latest_log(folder) do
    folder
    |> Path.join("*.log")
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
    |> List.first()
  end
end
