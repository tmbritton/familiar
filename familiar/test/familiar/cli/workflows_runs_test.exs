defmodule Familiar.CLI.WorkflowsRunsTest do
  @moduledoc """
  CLI-layer tests for `fam workflows resume` and `fam workflows list-runs`
  (Story 7.5-6). These tests stub the underlying WorkflowRuns and
  WorkflowRunner functions via the deps map — they do NOT hit the repo.
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

  defp run_row(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        name: "resume-demo",
        workflow_path: nil,
        status: "failed",
        scope: "workflow",
        current_step_index: 2,
        step_results: [
          %{"step" => "analyze", "output" => "ok"},
          %{"step" => "build", "output" => "ok"}
        ],
        initial_context: %{"task" => "Build auth"},
        last_error: "llm_error: rate limited",
        inserted_at: ~U[2026-04-10 10:00:00Z],
        updated_at: ~U[2026-04-10 10:05:00Z]
      },
      overrides
    )
  end

  describe "fam workflows resume" do
    test "without --id uses latest_resumable and delegates to resume_workflow" do
      test_pid = self()

      deps =
        base_deps(
          latest_resumable_fn: fn _ ->
            send(test_pid, :latest_called)
            {:ok, run_row(%{name: "planning"})}
          end,
          resume_workflow_fn: fn id, _opts ->
            send(test_pid, {:resume_called, id})
            {:ok, %{steps: [%{step: "analyze", output: "ok"}]}}
          end
        )

      assert {:ok, %{workflow: "planning", run_id: 1, steps: [_]}} =
               Main.run({"workflows", ["resume"], %{}}, deps)

      assert_received :latest_called
      assert_received {:resume_called, 1}
    end

    test "with --id loads the specific run" do
      test_pid = self()

      deps =
        base_deps(
          get_workflow_run_fn: fn id ->
            send(test_pid, {:get_called, id})
            {:ok, run_row(%{id: 42, name: "specific"})}
          end,
          resume_workflow_fn: fn id, _opts ->
            send(test_pid, {:resume_called, id})
            {:ok, %{steps: []}}
          end
        )

      assert {:ok, %{workflow: "specific", run_id: 42}} =
               Main.run({"workflows", ["resume"], %{id: 42}}, deps)

      assert_received {:get_called, 42}
      assert_received {:resume_called, 42}
    end

    test "surfaces :no_resumable_workflow error" do
      deps =
        base_deps(
          latest_resumable_fn: fn _ -> {:error, {:no_resumable_workflow, %{scope: nil}}} end
        )

      assert {:error, {:no_resumable_workflow, _}} =
               Main.run({"workflows", ["resume"], %{}}, deps)
    end

    test "surfaces :workflow_run_not_found when --id is bogus" do
      deps =
        base_deps(
          get_workflow_run_fn: fn _id -> {:error, {:workflow_run_not_found, %{id: 999}}} end
        )

      assert {:error, {:workflow_run_not_found, _}} =
               Main.run({"workflows", ["resume"], %{id: 999}}, deps)
    end

    test "surfaces :workflow_already_completed from the runner" do
      deps =
        base_deps(
          latest_resumable_fn: fn _ -> {:ok, run_row()} end,
          resume_workflow_fn: fn _, _ ->
            {:error, {:workflow_already_completed, %{id: 1}}}
          end
        )

      assert {:error, {:workflow_already_completed, _}} =
               Main.run({"workflows", ["resume"], %{}}, deps)
    end

    test "rejects --id with a non-integer value (parse_args records :_invalid)" do
      # parse_args places rejected strict-flag values into the :_invalid list.
      # The resume command must surface a usage_error rather than silently
      # falling back to latest_resumable.
      flags = %{_invalid: [{"--id", "abc"}]}

      deps =
        base_deps(
          latest_resumable_fn: fn _ ->
            flunk("latest_resumable should not be called when --id is invalid")
          end,
          get_workflow_run_fn: fn _id ->
            flunk("get should not be called when --id is invalid")
          end
        )

      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"workflows", ["resume"], flags}, deps)

      assert msg =~ "--id"
      assert msg =~ "abc"
    end

    test "warns to stderr when resuming a row whose status is still 'running'" do
      deps =
        base_deps(
          latest_resumable_fn: fn _ -> {:ok, run_row(%{status: "running"})} end,
          resume_workflow_fn: fn _, _ -> {:ok, %{steps: []}} end
        )

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert {:ok, _} = Main.run({"workflows", ["resume"], %{}}, deps)
        end)

      assert stderr =~ "still marked running"
    end
  end

  describe "fam workflows list-runs" do
    test "returns the list from WorkflowRuns.list/1" do
      deps =
        base_deps(
          list_workflow_runs_fn: fn _opts ->
            {:ok, [run_row(), run_row(%{id: 2, name: "other", status: "completed"})]}
          end
        )

      assert {:ok, %{runs: runs}} =
               Main.run({"workflows", ["list-runs"], %{}}, deps)

      assert length(runs) == 2
      first = hd(runs)
      assert first.id == 1
      assert first.name == "resume-demo"
      assert first.status == "failed"
      assert first.step == 2
      assert first.last_error =~ "rate limited"
    end

    test "passes --status, --scope, and --limit through to the context" do
      test_pid = self()

      deps =
        base_deps(
          list_workflow_runs_fn: fn opts ->
            send(test_pid, {:list_called, opts})
            {:ok, []}
          end
        )

      assert {:ok, %{runs: []}} =
               Main.run(
                 {"workflows", ["list-runs"], %{status: "failed", scope: "planning", limit: 5}},
                 deps
               )

      assert_received {:list_called, opts}
      assert Keyword.get(opts, :status) == "failed"
      assert Keyword.get(opts, :scope) == "planning"
      assert Keyword.get(opts, :limit) == 5
    end

    test "truncates last_error to 60 chars with ellipsis" do
      long_error = String.duplicate("x", 200)

      deps =
        base_deps(
          list_workflow_runs_fn: fn _ ->
            {:ok, [run_row(%{last_error: long_error})]}
          end
        )

      assert {:ok, %{runs: [row]}} =
               Main.run({"workflows", ["list-runs"], %{}}, deps)

      assert String.length(row.last_error) == 60
      assert String.ends_with?(row.last_error, "...")
    end

    test "handles empty list cleanly" do
      deps = base_deps(list_workflow_runs_fn: fn _ -> {:ok, []} end)

      assert {:ok, %{runs: []}} =
               Main.run({"workflows", ["list-runs"], %{}}, deps)
    end
  end

  describe "fam workflows list-runs text formatter" do
    test "renders a fixed-width table when results are present" do
      formatter = Main.text_formatter("workflows")

      result = %{
        runs: [
          %{
            id: 1,
            name: "feature-planning",
            status: "failed",
            step: 2,
            updated_at: ~U[2026-04-10 12:34:56Z],
            last_error: "boom"
          },
          %{
            id: 2,
            name: "feature-implementation",
            status: "completed",
            step: 3,
            updated_at: ~U[2026-04-10 12:35:00Z],
            last_error: nil
          }
        ]
      }

      output = formatter.(result)

      assert output =~ "Workflow runs (2):"
      assert output =~ "ID"
      assert output =~ "NAME"
      assert output =~ "STATUS"
      assert output =~ "STEP"
      assert output =~ "UPDATED"
      assert output =~ "ERROR"
      assert output =~ "#1"
      assert output =~ "feature-planning"
      assert output =~ "failed"
      assert output =~ "boom"
      assert output =~ "#2"
      assert output =~ "feature-implementation"
      assert output =~ "completed"
      assert output =~ "2026-04-10 12:34:56"
    end

    test "renders an empty-state message when no runs exist" do
      formatter = Main.text_formatter("workflows")
      assert formatter.(%{runs: []}) == "No workflow runs found."
    end
  end
end
