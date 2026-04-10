defmodule Familiar.Execution.WorkflowRunsTest do
  use Familiar.DataCase, async: false

  alias Familiar.Execution.WorkflowRuns
  alias Familiar.Execution.WorkflowRuns.Run

  describe "create/2" do
    test "inserts a running row with default fields" do
      {:ok, run} = WorkflowRuns.create("feature-planning")

      assert %Run{} = run
      assert run.name == "feature-planning"
      assert run.status == "running"
      assert run.current_step_index == 0
      assert run.step_results == []
      assert run.scope == "workflow"
      assert run.workflow_path == nil
      assert run.initial_context == nil
    end

    test "persists workflow_path, scope, and initial_context" do
      ctx = %{"task" => "Build auth", "tenant" => "acme"}

      {:ok, run} =
        WorkflowRuns.create("feature-planning",
          workflow_path: "/tmp/wf.md",
          scope: "planning",
          initial_context: ctx
        )

      assert run.workflow_path == "/tmp/wf.md"
      assert run.scope == "planning"
      assert run.initial_context == ctx
    end

    test "rejects empty name" do
      assert {:error, {:workflow_run_create_failed, _}} = WorkflowRuns.create("")
    end
  end

  describe "get/1" do
    test "fetches an existing row" do
      {:ok, run} = WorkflowRuns.create("demo")
      assert {:ok, fetched} = WorkflowRuns.get(run.id)
      assert fetched.id == run.id
    end

    test "returns :workflow_run_not_found for missing id" do
      assert {:error, {:workflow_run_not_found, %{id: 99_999}}} = WorkflowRuns.get(99_999)
    end
  end

  describe "checkpoint/3" do
    test "updates current_step_index and step_results atomically" do
      {:ok, run} = WorkflowRuns.create("demo")

      results = [
        %{"step" => "research", "output" => "notes"},
        %{"step" => "draft", "output" => "spec"}
      ]

      {:ok, updated} = WorkflowRuns.checkpoint(run.id, 2, results)

      assert updated.current_step_index == 2
      assert updated.step_results == results
      assert updated.status == "running"
    end

    test "returns error for missing id" do
      assert {:error, {:workflow_run_not_found, _}} = WorkflowRuns.checkpoint(99_999, 1, [])
    end
  end

  describe "complete/1 and fail/2" do
    test "complete/1 sets status to completed" do
      {:ok, run} = WorkflowRuns.create("demo")
      {:ok, updated} = WorkflowRuns.complete(run.id)
      assert updated.status == "completed"
    end

    test "fail/2 records status and pretty-printed error" do
      {:ok, run} = WorkflowRuns.create("demo")
      {:ok, updated} = WorkflowRuns.fail(run.id, {:llm_error, %{message: "boom"}})

      assert updated.status == "failed"
      assert updated.last_error =~ "llm_error"
      assert updated.last_error =~ "boom"
    end
  end

  describe "list/1" do
    test "returns rows newest-first" do
      {:ok, a} = WorkflowRuns.create("a")
      {:ok, b} = WorkflowRuns.create("b")

      {:ok, runs} = WorkflowRuns.list()
      ids = Enum.map(runs, & &1.id)
      assert Enum.take(ids, 2) == [b.id, a.id]
    end

    test "filters by status and scope" do
      {:ok, done} = WorkflowRuns.create("done", scope: "planning")
      {:ok, _} = WorkflowRuns.complete(done.id)
      {:ok, _running} = WorkflowRuns.create("live", scope: "planning")

      {:ok, runs} = WorkflowRuns.list(status: "completed")
      assert length(runs) == 1
      assert hd(runs).name == "done"

      {:ok, planning} = WorkflowRuns.list(scope: "planning")
      assert length(planning) == 2
    end

    test "honors :limit" do
      for i <- 1..5, do: WorkflowRuns.create("run#{i}")

      {:ok, runs} = WorkflowRuns.list(limit: 3)
      assert length(runs) == 3
    end
  end

  describe "latest_resumable/1" do
    test "returns the most recent running or failed run" do
      {:ok, _} = WorkflowRuns.create("done") |> elem(1) |> then(&WorkflowRuns.complete(&1.id))
      {:ok, live} = WorkflowRuns.create("live")

      {:ok, found} = WorkflowRuns.latest_resumable()
      assert found.id == live.id
    end

    test "also returns failed runs" do
      {:ok, run} = WorkflowRuns.create("broken")
      {:ok, _} = WorkflowRuns.fail(run.id, :boom)

      {:ok, found} = WorkflowRuns.latest_resumable()
      assert found.id == run.id
    end

    test "returns :no_resumable_workflow when only completed rows exist" do
      {:ok, run} = WorkflowRuns.create("done")
      {:ok, _} = WorkflowRuns.complete(run.id)

      assert {:error, {:no_resumable_workflow, _}} = WorkflowRuns.latest_resumable()
    end

    test "filters by scope" do
      {:ok, a} = WorkflowRuns.create("a", scope: "planning")
      {:ok, _b} = WorkflowRuns.create("b", scope: "agent")

      {:ok, found} = WorkflowRuns.latest_resumable(scope: "planning")
      assert found.id == a.id
    end
  end

  describe "JSONField round-trip" do
    test "encodes and decodes nested structures and unicode" do
      payload = [
        %{"step" => "α", "output" => %{"nested" => [1, 2, 3], "flag" => true}},
        %{"step" => "β", "output" => "emoji 🦊 works"}
      ]

      {:ok, run} = WorkflowRuns.create("unicode")
      {:ok, updated} = WorkflowRuns.checkpoint(run.id, 2, payload)

      # Reload from the DB to force a decode
      {:ok, reloaded} = WorkflowRuns.get(updated.id)
      assert reloaded.step_results == payload
    end
  end

  describe "complete/1 clears last_error" do
    test "a previously-failed run that is then completed has last_error cleared" do
      {:ok, run} = WorkflowRuns.create("recoverable")
      {:ok, _} = WorkflowRuns.fail(run.id, {:llm_error, %{message: "transient"}})

      {:ok, completed} = WorkflowRuns.complete(run.id)
      assert completed.status == "completed"
      assert completed.last_error == nil

      # And a reload still shows it cleared
      {:ok, reloaded} = WorkflowRuns.get(run.id)
      assert reloaded.last_error == nil
    end
  end

  describe "list/1 stable ordering" do
    test "uses id as secondary sort to avoid same-second tie-break flakes" do
      # Force two rows with the same inserted_at (utc_datetime is second-precision).
      now = ~U[2026-04-10 12:00:00Z]
      {:ok, a} = WorkflowRuns.create("a")
      {:ok, b} = WorkflowRuns.create("b")

      Familiar.Repo.update_all(
        Familiar.Execution.WorkflowRuns.Run,
        set: [inserted_at: now]
      )

      {:ok, runs} = WorkflowRuns.list(limit: 5)
      ids = Enum.map(runs, & &1.id)
      # Even with identical inserted_at, the secondary `desc: r.id` sort makes
      # the order deterministic — newer id wins.
      assert Enum.take(ids, 2) == [b.id, a.id]
    end
  end

  describe "latest_resumable/1 stable ordering" do
    test "uses inserted_at + id (matching list/1) instead of updated_at" do
      now = ~U[2026-04-10 12:00:00Z]
      {:ok, _a} = WorkflowRuns.create("a")
      {:ok, b} = WorkflowRuns.create("b")

      Familiar.Repo.update_all(
        Familiar.Execution.WorkflowRuns.Run,
        set: [inserted_at: now]
      )

      {:ok, found} = WorkflowRuns.latest_resumable()
      assert found.id == b.id
    end
  end
end
