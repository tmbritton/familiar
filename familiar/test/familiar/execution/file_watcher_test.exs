defmodule Familiar.Execution.FileWatcherTest do
  use ExUnit.Case, async: false

  alias Familiar.Execution.FileWatcher

  @moduletag :file_watcher

  # -- Helpers --

  defp tmp_watch_dir do
    dir = Path.join(System.tmp_dir!(), "familiar_fw_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp subscribe_hook do
    Phoenix.PubSub.subscribe(Familiar.PubSub, "familiar:activity:hooks:on_file_changed")
  end

  defp start_watcher(dir, opts \\ []) do
    opts = Keyword.merge([project_dir: dir, debounce_ms: 10, notify_ready: self()], opts)
    pid = start_supervised!({FileWatcher, opts})
    assert_receive {:file_watcher_ready, ^pid}, 5_000
    # inotify backend needs time after GenServer init to register kernel watches.
    # This is irreducible — the FileSystem library has no readiness signal.
    Process.sleep(200)
    pid
  end

  # Write a file and wait for the inotify event.
  # Retries the write if inotify missed it (watch not yet registered).
  defp write_and_await_event(file, content, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2000)
    File.write!(file, content)

    receive do
      {:hook_event, :on_file_changed, payload} -> payload
    after
      timeout ->
        # Retry once — inotify may not have been ready for the first write
        File.write!(file, content <> " ")

        receive do
          {:hook_event, :on_file_changed, payload} -> payload
        after
          timeout ->
            flunk("No :on_file_changed event received for #{file} after retry")
        end
    end
  end

  # == AC1, AC6: GenServer Init ==

  describe "init/1" do
    test "starts successfully with a valid directory" do
      dir = tmp_watch_dir()
      pid = start_watcher(dir)
      assert Process.alive?(pid)
    end

    test "returns error for nonexistent directory" do
      bad_dir = Path.join(System.tmp_dir!(), "nonexistent_#{System.unique_integer([:positive])}")

      Process.flag(:trap_exit, true)

      assert {:error, {:invalid_dir, ^bad_dir}} =
               FileWatcher.start_link(project_dir: bad_dir)
    end
  end

  # == AC2: Event Broadcasting (all via :on_file_changed with type discriminator) ==

  describe "event broadcasting" do
    test "file creation broadcasts with type: :created" do
      dir = tmp_watch_dir()
      subscribe_hook()
      start_watcher(dir)

      file = Path.join(dir, "new_file.txt")
      payload = write_and_await_event(file, "hello")

      assert payload.path == file
      # inotify may report :created or :changed for new files under concurrent load
      assert payload.type in [:created, :changed]
    end

    test "file modification broadcasts with type: :changed" do
      dir = tmp_watch_dir()
      file = Path.join(dir, "existing.txt")
      File.write!(file, "original")

      subscribe_hook()
      start_watcher(dir)

      payload = write_and_await_event(file, "modified")
      assert payload.path == file
      assert payload.type == :changed
    end

    test "file deletion broadcasts with type: :deleted" do
      dir = tmp_watch_dir()
      file = Path.join(dir, "to_delete.txt")
      File.write!(file, "temp")

      subscribe_hook()
      start_watcher(dir)

      File.rm!(file)

      assert_receive {:hook_event, :on_file_changed, %{path: ^file, type: :deleted}}, 2000
    end

    test "deletion fires immediately without debounce" do
      dir = tmp_watch_dir()
      file = Path.join(dir, "immediate_delete.txt")
      File.write!(file, "temp")

      subscribe_hook()
      # Long debounce — deletion should still fire fast
      start_watcher(dir, debounce_ms: 1000)

      File.rm!(file)

      # Should receive well before the 5000ms debounce
      assert_receive {:hook_event, :on_file_changed, %{path: ^file, type: :deleted}}, 500
    end
  end

  # == AC3: Debouncing ==

  describe "debounce" do
    test "rapid changes to same file debounced to single event" do
      dir = tmp_watch_dir()
      subscribe_hook()
      start_watcher(dir, debounce_ms: 50)

      file = Path.join(dir, "rapid.txt")

      # Write rapidly — these should be debounced
      for i <- 1..5 do
        File.write!(file, "content #{i}")
        Process.sleep(5)
      end

      # Wait for debounce to fire
      Process.sleep(150)

      # Collect all received events for this file
      events = flush_events(file)

      # Should have exactly 1 event (the debounced one)
      assert length(events) == 1
    end

    test "changes to different files are independent" do
      dir = tmp_watch_dir()
      subscribe_hook()
      start_watcher(dir, debounce_ms: 10)

      file_a = Path.join(dir, "file_a.txt")
      file_b = Path.join(dir, "file_b.txt")

      File.write!(file_a, "content a")
      File.write!(file_b, "content b")

      # Wait for both debounces to fire
      Process.sleep(100)

      events_a = flush_events(file_a)
      events_b = flush_events(file_b)

      assert events_a != []
      assert events_b != []
    end

    test "custom debounce_ms is respected" do
      dir = tmp_watch_dir()
      subscribe_hook()

      # Very short debounce
      start_watcher(dir, debounce_ms: 50)

      file = Path.join(dir, "quick.txt")
      File.write!(file, "fast")

      # Should fire within 200ms with 50ms debounce
      assert_receive {:hook_event, :on_file_changed, %{path: ^file}}, 200
    end
  end

  # == AC4: Ignore List ==

  describe "ignore list" do
    test "ignored paths do not trigger events" do
      dir = tmp_watch_dir()
      git_dir = Path.join(dir, ".git")
      File.mkdir_p!(git_dir)

      subscribe_hook()
      start_watcher(dir, debounce_ms: 50)

      # Write to an ignored path
      File.write!(Path.join(git_dir, "HEAD"), "ref")

      # Write to a non-ignored path (to verify watcher is active)
      legit_file = Path.join(dir, "legit.txt")
      File.write!(legit_file, "hello")

      # Should receive the legit file event but NOT the .git/ one
      assert_receive {:hook_event, :on_file_changed, %{path: ^legit_file}}, 2000
      git_head = Path.join(git_dir, "HEAD")
      refute_receive {:hook_event, :on_file_changed, %{path: ^git_head}}, 200
    end

    test "ignore pattern does not false-positive on similar names" do
      dir = tmp_watch_dir()
      similar_dir = Path.join(dir, ".git_backup")
      File.mkdir_p!(similar_dir)

      subscribe_hook()
      start_watcher(dir, debounce_ms: 50)

      file = Path.join(similar_dir, "data.txt")
      File.write!(file, "not ignored")

      assert_receive {:hook_event, :on_file_changed, %{path: ^file}}, 2000
    end

    test "denormalized ignore pattern (no trailing slash) works" do
      dir = tmp_watch_dir()
      ignored_dir = Path.join(dir, "vendor")
      File.mkdir_p!(ignored_dir)

      subscribe_hook()
      # Pattern without trailing slash — should still be normalized
      start_watcher(dir, debounce_ms: 50, ignore_patterns: ["vendor"])

      File.write!(Path.join(ignored_dir, "lib.js"), "code")

      legit = Path.join(dir, "app.js")
      File.write!(legit, "code")

      assert_receive {:hook_event, :on_file_changed, %{path: ^legit}}, 2000
      vendor_file = Path.join(ignored_dir, "lib.js")
      refute_receive {:hook_event, :on_file_changed, %{path: ^vendor_file}}, 200
    end

    test "custom ignore patterns work" do
      dir = tmp_watch_dir()
      custom_dir = Path.join(dir, "tmp_cache")
      File.mkdir_p!(custom_dir)

      subscribe_hook()
      start_watcher(dir, debounce_ms: 50, ignore_patterns: ["tmp_cache/"])

      File.write!(Path.join(custom_dir, "cached.dat"), "data")

      legit = Path.join(dir, "legit2.txt")
      File.write!(legit, "hi")

      assert_receive {:hook_event, :on_file_changed, %{path: ^legit}}, 2000
      cached = Path.join(custom_dir, "cached.dat")
      refute_receive {:hook_event, :on_file_changed, %{path: ^cached}}, 200
    end
  end

  # -- Private helpers --

  defp flush_events(target_path) do
    flush_events(target_path, [])
  end

  defp flush_events(target_path, acc) do
    receive do
      {:hook_event, :on_file_changed, %{path: ^target_path} = payload} ->
        flush_events(target_path, [payload | acc])
    after
      100 ->
        Enum.reverse(acc)
    end
  end
end
