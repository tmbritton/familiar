defmodule Familiar.CLI.ContextReindexTest do
  @moduledoc """
  CLI-layer tests for `fam context --reindex` (Story 7.5-7).
  Stubs `Knowledge.reindex_embeddings/1` via the deps map so the
  tests don't hit the repo or embedder.
  """

  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  defp base_deps(overrides) do
    base = %{
      ensure_running_fn: fn _ -> {:ok, 4000} end,
      health_fn: fn _ -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _ -> {:stopped, %{}} end,
      stop_daemon_fn: fn _ -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, Map.new(overrides))
  end

  describe "fam context --reindex" do
    test "returns the reindex summary from Knowledge.reindex_embeddings/1" do
      test_pid = self()

      deps =
        base_deps(
          reindex_fn: fn opts ->
            send(test_pid, {:reindex_called, opts})

            {:ok,
             %{
               processed: 5,
               failed: 0,
               errors: [],
               model: "text-embedding-3-small",
               dimensions: 1536
             }}
          end
        )

      assert {:ok, %{reindex: summary}} =
               Main.run({"context", [], %{reindex: true}}, deps)

      assert summary.processed == 5
      assert summary.failed == 0
      assert summary.model == "text-embedding-3-small"

      assert_received {:reindex_called, opts}
      assert is_function(Keyword.get(opts, :on_progress), 2)
    end

    test "on_progress callback fires for the final entry (unthrottled)" do
      test_pid = self()

      deps =
        base_deps(
          reindex_fn: fn opts ->
            on_progress = Keyword.get(opts, :on_progress)
            # Invoke once as if a single entry just completed (processed == total)
            on_progress.(1, 1)
            {:ok, %{processed: 1, failed: 0, errors: [], model: "m", dimensions: 1536}}
          end
        )

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert {:ok, _} = Main.run({"context", [], %{reindex: true}}, deps)
          send(test_pid, :done)
        end)

      assert stderr =~ "Re-embedding 1/1"
      assert_received :done
    end

    test "rejects --reindex combined with --refresh" do
      deps =
        base_deps(
          reindex_fn: fn _opts ->
            flunk("reindex should not be called when combined with --refresh")
          end
        )

      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"context", [], %{reindex: true, refresh: true}}, deps)

      assert msg =~ "Cannot combine"
    end

    test "surfaces errors from Knowledge.reindex_embeddings/1" do
      deps =
        base_deps(
          reindex_fn: fn _opts ->
            {:error, {:provider_unavailable, %{reason: :missing_api_key}}}
          end
        )

      assert {:error, {:provider_unavailable, _}} =
               Main.run({"context", [], %{reindex: true}}, deps)
    end
  end

  describe "text formatter" do
    test "renders a clean summary when there are no errors" do
      formatter = Main.text_formatter("context")

      result = %{
        reindex: %{
          processed: 42,
          failed: 0,
          errors: [],
          model: "text-embedding-3-small",
          dimensions: 1536
        }
      }

      output = formatter.(result)
      assert output =~ "Reindexed 42 entries"
      assert output =~ "0 failed"
      assert output =~ "text-embedding-3-small"
    end

    test "preserves the actual error reason in each error line (no aggressive truncation)" do
      formatter = Main.text_formatter("context")

      result = %{
        reindex: %{
          processed: 0,
          failed: 1,
          errors: [{42, {:provider_unavailable, %{reason: :rate_limited, retry_after: 30}}}],
          model: "text-embedding-3-small",
          dimensions: 1536
        }
      }

      output = formatter.(result)
      assert output =~ "entry #42"
      assert output =~ "provider_unavailable"
      assert output =~ "rate_limited"
      assert output =~ "retry_after"
    end

    test "includes up to 10 error entries" do
      formatter = Main.text_formatter("context")

      errors = for i <- 1..15, do: {i, {:provider_unavailable, %{reason: :timeout}}}

      result = %{
        reindex: %{
          processed: 0,
          failed: 15,
          errors: errors,
          model: "text-embedding-3-small",
          dimensions: 1536
        }
      }

      output = formatter.(result)
      assert output =~ "Errors:"
      assert output =~ "entry #1"
      assert output =~ "entry #10"
      assert output =~ "(5 more)"
    end

    test "renders unset model gracefully" do
      formatter = Main.text_formatter("context")

      result = %{
        reindex: %{
          processed: 0,
          failed: 0,
          errors: [],
          model: nil,
          dimensions: 1536
        }
      }

      output = formatter.(result)
      assert output =~ "unset"
    end
  end

  describe "throttle_progress/5" do
    # Pure helper — no time manipulation needed. These tests cover the
    # non-final-case path that the higher-level context_reindex test can't
    # exercise deterministically without sleeping.

    test "first call before 500ms suppresses" do
      # start_ms = 1000, now = 1100 (100ms elapsed), no prior fire.
      assert Main.throttle_progress(1100, 1000, 0, 1, 10) == :suppress
    end

    test "first call past 500ms fires and records new offset" do
      # start_ms = 1000, now = 1600 (600ms elapsed), no prior fire.
      assert Main.throttle_progress(1600, 1000, 0, 1, 10) == {:fire, 600}
    end

    test "second call within 500ms of first fire suppresses" do
      # start_ms = 1000, last fire at 1600 (offset 600), now = 1800 (200ms later).
      assert Main.throttle_progress(1800, 1000, 600, 2, 10) == :suppress
    end

    test "second call past 500ms of first fire fires and records offset" do
      # start_ms = 1000, last fire at 1600 (offset 600), now = 2200 (600ms later).
      assert Main.throttle_progress(2200, 1000, 600, 3, 10) == {:fire, 1200}
    end

    test "final call (processed == total) always fires regardless of timing" do
      # Just fired 100ms ago — throttle would normally suppress — but this
      # is the terminal entry so the user must see it.
      assert Main.throttle_progress(1100, 1000, 100, 10, 10) == {:fire, 100}
    end

    test "final call fires even as the very first callback" do
      # Single-entry reindex: first and last callback are the same.
      assert Main.throttle_progress(1050, 1000, 0, 1, 1) == {:fire, 50}
    end

    test "elapsed_since_last exactly 500ms fires (boundary)" do
      assert Main.throttle_progress(1500, 1000, 0, 1, 10) == {:fire, 500}
    end

    test "elapsed_since_last 499ms suppresses (just under boundary)" do
      assert Main.throttle_progress(1499, 1000, 0, 1, 10) == :suppress
    end
  end
end
