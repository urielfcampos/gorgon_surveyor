defmodule GorgonSurvey.ConfigStoreTest do
  use ExUnit.Case, async: false

  alias GorgonSurvey.{ConfigStore, SessionManager}

  setup do
    session_id = "config-test-#{System.unique_integer([:positive])}"
    SessionManager.register(session_id)
    on_exit(fn -> SessionManager.force_cleanup(session_id) end)
    {:ok, session_id: session_id}
  end

  test "get_for_session returns session override when set", %{session_id: session_id} do
    SessionManager.put_config(session_id, "log_folder", "/tmp/session-folder")
    Process.sleep(10)
    assert "/tmp/session-folder" = ConfigStore.get_for_session(session_id, "log_folder")
  end

  test "get_for_session falls back to global config", %{session_id: session_id} do
    global_val = ConfigStore.get("log_folder", "")
    assert ConfigStore.get_for_session(session_id, "log_folder", "") == global_val
  end

  test "put_for_session stores in session, not global", %{session_id: session_id} do
    original_global = ConfigStore.get("test_key_xyz", nil)
    ConfigStore.put_for_session(session_id, "test_key_xyz", "session_value")
    Process.sleep(10)
    assert ConfigStore.get_for_session(session_id, "test_key_xyz") == "session_value"
    assert ConfigStore.get("test_key_xyz", nil) == original_global
  end
end
