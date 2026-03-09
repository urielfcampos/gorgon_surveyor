defmodule GorgonSurvey.LogWatcherTest do
  use ExUnit.Case

  alias GorgonSurvey.LogWatcher

  setup do
    # Create a dedicated temp directory so inotify watches reliably
    tmp_dir = Path.join(System.tmp_dir!(), "logwatch_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    log_path = Path.join(tmp_dir, "chat.log")
    File.write!(log_path, "")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    # Subscribe to PubSub for state updates
    Phoenix.PubSub.subscribe(GorgonSurvey.PubSub, "game_state")

    {:ok, log_path: log_path}
  end

  test "starts and returns initial state", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    state = LogWatcher.get_state(pid)
    assert state.surveys == []
    GenServer.stop(pid)
  end

  test "detects new survey line appended to log", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    # Allow inotify watcher to fully initialize
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 815m west and 1441m north.\n", [:append])
    # Give file watcher time to detect and process
    Process.sleep(500)
    state = LogWatcher.get_state(pid)
    assert length(state.surveys) == 1
    [s] = state.surveys
    assert s.name == "Good Metal Slab"
    GenServer.stop(pid)
  end

  test "broadcasts state updates via PubSub", %{log_path: log_path} do
    {:ok, pid} = LogWatcher.start_link(log_path: log_path, name: nil)
    # Allow inotify watcher to fully initialize
    Process.sleep(200)
    File.write!(log_path, "The Good Metal Slab is 100m east and 200m north.\n", [:append])
    assert_receive {:state_updated, %GorgonSurvey.AppState{}}, 2000
    GenServer.stop(pid)
  end
end
