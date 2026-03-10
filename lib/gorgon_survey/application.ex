defmodule GorgonSurvey.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GorgonSurveyWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:gorgon_survey, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GorgonSurvey.PubSub},
      {Registry, keys: :unique, name: GorgonSurvey.SessionRegistry},
      GorgonSurvey.SessionManager,
      {DynamicSupervisor, name: GorgonSurvey.SessionSupervisor, strategy: :one_for_one},
      GorgonSurveyWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: GorgonSurvey.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    GorgonSurveyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
