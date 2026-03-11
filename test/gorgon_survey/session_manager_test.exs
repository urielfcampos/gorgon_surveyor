defmodule GorgonSurvey.SessionManagerTest do
  use ExUnit.Case, async: false

  alias GorgonSurvey.SessionManager

  setup do
    for session_id <- SessionManager.list_sessions() do
      SessionManager.force_cleanup(session_id)
    end

    :ok
  end

  describe "register/1" do
    test "registers a new session and returns :ok" do
      session_id = "test-#{System.unique_integer([:positive])}"
      assert :ok = SessionManager.register(session_id)
      assert session_id in SessionManager.list_sessions()
    end

    test "registering same session_id twice is idempotent" do
      session_id = "test-#{System.unique_integer([:positive])}"
      assert :ok = SessionManager.register(session_id)
      assert :ok = SessionManager.register(session_id)
    end
  end

  describe "deregister/1 and cleanup" do
    test "schedules cleanup timer on deregister" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert :ok = SessionManager.deregister(session_id)
      assert session_id in SessionManager.list_sessions()
    end

    test "force_cleanup removes session immediately" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.force_cleanup(session_id)
      refute session_id in SessionManager.list_sessions()
    end
  end

  describe "reconnect/1" do
    test "cancels cleanup timer and returns :ok" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.deregister(session_id)
      assert :ok = SessionManager.reconnect(session_id)
      assert session_id in SessionManager.list_sessions()
    end

    test "returns :error for unknown session" do
      assert :error = SessionManager.reconnect("nonexistent")
    end
  end

  describe "config overrides" do
    test "put_config/3 and get_config/2" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      SessionManager.put_config(session_id, "log_folder", "/tmp/test")
      # Small sleep to let cast complete
      Process.sleep(10)
      assert "/tmp/test" = SessionManager.get_config(session_id, "log_folder")
    end

    test "get_config returns nil for unset key" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert nil == SessionManager.get_config(session_id, "unset_key")
    end

    test "get_config returns nil for unknown session" do
      assert nil == SessionManager.get_config("nonexistent", "key")
    end
  end

  describe "watcher management" do
    test "start_watcher/2 stores watcher pid" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)

      tmp_dir = Path.join(System.tmp_dir!(), "sm_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      log_path = Path.join(tmp_dir, "chat.log")
      File.write!(log_path, "")
      on_exit(fn -> File.rm_rf(tmp_dir) end)

      assert {:ok, pid} = SessionManager.start_watcher(session_id, tmp_dir)
      assert is_pid(pid)
      assert Process.alive?(pid)

      SessionManager.force_cleanup(session_id)
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "get_watcher/1 returns nil when no watcher started" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)
      assert nil == SessionManager.get_watcher(session_id)
    end

    test "start_remote_watcher/1 starts a watcher in remote mode" do
      session_id = "test-#{System.unique_integer([:positive])}"
      SessionManager.register(session_id)

      assert {:ok, pid} = SessionManager.start_remote_watcher(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify it accepts ingest_lines (remote mode)
      GorgonSurvey.LogWatcher.ingest_lines(
        pid,
        "The Good Metal Slab is 100m east and 200m north.\n"
      )

      # No crash = success

      SessionManager.force_cleanup(session_id)
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "start_remote_watcher/1 returns error for unknown session" do
      assert {:error, :unknown_session} = SessionManager.start_remote_watcher("nonexistent")
    end
  end
end
