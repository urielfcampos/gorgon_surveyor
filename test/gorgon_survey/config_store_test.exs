defmodule GorgonSurvey.ConfigStoreTest do
  use ExUnit.Case, async: false

  alias GorgonSurvey.ConfigStore

  test "get returns default when key is not set" do
    assert ConfigStore.get("nonexistent_key_#{System.unique_integer([:positive])}", "default") ==
             "default"
  end

  test "put persists and get retrieves value" do
    key = "test_key_#{System.unique_integer([:positive])}"
    ConfigStore.put(key, "test_value")
    assert ConfigStore.get(key) == "test_value"
  end
end
