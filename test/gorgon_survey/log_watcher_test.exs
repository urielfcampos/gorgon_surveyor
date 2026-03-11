defmodule GorgonSurvey.LogWatcherTest do
  use ExUnit.Case

  alias GorgonSurvey.LogWatcher

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "logwatch_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    log_path = Path.join(tmp_dir, "chat.log")
    File.write!(log_path, "")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    session_id = "test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")

    {:ok, log_path: log_path, session_id: session_id}
  end

  test "starts and returns initial state", %{log_path: log_path, session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    state = LogWatcher.get_state(pid)
    assert state.surveys == []
    GenServer.stop(pid)
  end

  test "detects new survey line appended to log", %{log_path: log_path, session_id: session_id} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 815m west and 1441m north.\n", [:append])
    Process.sleep(500)
    state = LogWatcher.get_state(pid)
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.name == "Good Metal Slab"
    GenServer.stop(pid)
  end

  test "broadcasts state updates via scoped PubSub", %{
    log_path: log_path,
    session_id: session_id
  } do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: session_id)
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    assert_receive {:state_updated, %GorgonSurvey.AppState{}}, 2000
    GenServer.stop(pid)
  end

  test "different sessions do not receive each other's broadcasts", %{log_path: log_path} do
    other_session = "other-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{other_session}")

    {:ok, pid} = LogWatcher.start_link(log_path: log_path, session_id: "isolated-session")
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    refute_receive {:state_updated, _}, 1000
    GenServer.stop(pid)
  end

  describe "remote mode" do
    setup do
      session_id = "remote-test-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state:#{session_id}")
      {:ok, session_id: session_id}
    end

    test "starts in remote mode without log path", %{session_id: session_id} do
      {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)
      state = LogWatcher.get_state(pid)
      assert state.surveys == []
      GenServer.stop(pid)
    end

    test "ingest_lines parses and broadcasts survey lines", %{session_id: session_id} do
      {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)

      LogWatcher.ingest_lines(pid, "The Good Metal Slab is 815m west and 1441m north.\n")

      assert_receive {:state_updated, %GorgonSurvey.AppState{} = app_state}, 1000
      assert length(app_state.surveys) == 1
      [s] = app_state.surveys
      assert s.name == "Good Metal Slab"

      GenServer.stop(pid)
    end

    test "multiple ingest_lines accumulate surveys", %{session_id: session_id} do
      {:ok, pid} = LogWatcher.start_link(mode: :remote, session_id: session_id)

      LogWatcher.ingest_lines(pid, "The Good Metal Slab is 815m west and 1441m north.\n")
      assert_receive {:state_updated, _}, 1000

      LogWatcher.ingest_lines(pid, "The Amazing Geode is 200m east and 300m south.\n")
      assert_receive {:state_updated, %GorgonSurvey.AppState{} = app_state}, 1000
      assert length(app_state.surveys) == 2

      GenServer.stop(pid)
    end
  end
end
