defmodule GorgonSurvey.ConfigStore do
  @moduledoc "Persists settings to a JSON file."

  @config_dir Path.join(System.user_home!(), ".config/gorgon-survey")
  @config_path Path.join(@config_dir, "settings.json")

  def load do
    case File.read(@config_path) do
      {:ok, content} -> Jason.decode!(content)
      _ -> %{}
    end
  end

  def save(config) when is_map(config) do
    File.mkdir_p!(@config_dir)
    File.write!(@config_path, Jason.encode!(config, pretty: true))
  end

  def get(key, default \\ nil) do
    load() |> Map.get(key, default)
  end

  def put(key, value) do
    config = load() |> Map.put(key, value)
    save(config)
    config
  end

  def get_for_session(session_id, key, default \\ nil) do
    case GorgonSurvey.SessionManager.get_config(session_id, key) do
      nil -> get(key, default)
      value -> value
    end
  end

  def put_for_session(session_id, key, value) do
    GorgonSurvey.SessionManager.put_config(session_id, key, value)
  end
end
