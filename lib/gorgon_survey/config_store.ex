defmodule GorgonSurvey.ConfigStore do
  @moduledoc """
  Persists user settings to a JSON file on disk.

  Settings are stored at `~/.config/gorgon-survey/settings.json` as a flat
  key-value JSON object. The file is read from disk on every `get/2` call and
  written on every `put/2` call — there is no in-memory cache.

  ## Stored settings

  - `"log_folder"` — path to the directory containing Project Gorgon's chat.log
  - `"auto_detect_on_survey"` — `"true"` or `"false"`, whether to auto-scan
    when a new survey appears in the log
  - `"collect_hotkey"` — global hotkey string (e.g. `"F11"`) for marking surveys
    as collected
  """

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

end
