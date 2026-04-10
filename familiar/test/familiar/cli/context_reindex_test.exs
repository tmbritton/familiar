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
end
