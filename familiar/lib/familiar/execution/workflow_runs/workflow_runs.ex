defmodule Familiar.Execution.WorkflowRuns do
  @moduledoc """
  Persistence API for workflow runs.

  A `workflow_run` row durably records the progress of a
  `Familiar.Execution.WorkflowRunner` execution: which step is next,
  which steps have completed, and the initial context. When a run
  fails or is interrupted, the row is the handle a user can resume
  from via `Familiar.Execution.WorkflowRunner.resume_workflow/2`.

  This module is intentionally small — it holds zero workflow
  execution logic. It owns reading, writing, and listing rows.
  """

  import Ecto.Query

  alias Familiar.Execution.WorkflowRuns.Run
  alias Familiar.Repo

  @type run :: Run.t()

  @resumable_statuses ~w(running failed)

  @doc """
  Insert a new workflow run row with `status: "running"`.

  Options:
    * `:workflow_path` — absolute path to the source .md file (enables resume)
    * `:scope` — logical scope label, default `"workflow"`
    * `:initial_context` — map of the initial caller context (JSON-encoded on write)
  """
  @spec create(String.t(), keyword()) ::
          {:ok, run()} | {:error, {:workflow_run_create_failed, map()}}
  def create(name, opts \\ []) when is_binary(name) do
    attrs = %{
      name: name,
      workflow_path: Keyword.get(opts, :workflow_path),
      scope: Keyword.get(opts, :scope, "workflow"),
      status: "running",
      current_step_index: 0,
      step_results: [],
      initial_context: Keyword.get(opts, :initial_context)
    }

    attrs
    |> Run.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, run} -> {:ok, run}
      {:error, cs} -> {:error, {:workflow_run_create_failed, %{changeset: cs}}}
    end
  end

  @doc "Fetch a run by id."
  @spec get(integer()) :: {:ok, run()} | {:error, {:workflow_run_not_found, map()}}
  def get(id) when is_integer(id) do
    case Repo.get(Run, id) do
      nil -> {:error, {:workflow_run_not_found, %{id: id}}}
      run -> {:ok, run}
    end
  end

  @doc """
  Write a step-boundary checkpoint: update `current_step_index` and
  `step_results` atomically.
  """
  @spec checkpoint(integer(), non_neg_integer(), [map()]) ::
          {:ok, run()} | {:error, term()}
  def checkpoint(id, new_index, step_results)
      when is_integer(id) and is_integer(new_index) and is_list(step_results) do
    with {:ok, run} <- get(id) do
      run
      |> Run.update_changeset(%{
        current_step_index: new_index,
        step_results: step_results
      })
      |> Repo.update()
      |> case do
        {:ok, run} -> {:ok, run}
        {:error, cs} -> {:error, {:workflow_run_update_failed, %{changeset: cs}}}
      end
    end
  end

  @doc """
  Mark a run as completed.

  Clears `last_error` so a previously-failed run that has been resumed and
  successfully finished doesn't keep a stale error message in `list-runs`
  output or JSON consumers.
  """
  @spec complete(integer()) :: {:ok, run()} | {:error, term()}
  def complete(id) when is_integer(id) do
    with {:ok, run} <- get(id) do
      run
      |> Run.update_changeset(%{status: "completed", last_error: nil})
      |> Repo.update()
      |> case do
        {:ok, run} -> {:ok, run}
        {:error, cs} -> {:error, {:workflow_run_update_failed, %{changeset: cs}}}
      end
    end
  end

  @doc "Mark a run as failed, recording the error reason."
  @spec fail(integer(), term()) :: {:ok, run()} | {:error, term()}
  def fail(id, reason) when is_integer(id) do
    with {:ok, run} <- get(id) do
      run
      |> Run.update_changeset(%{
        status: "failed",
        last_error: inspect(reason, pretty: true, limit: :infinity)
      })
      |> Repo.update()
      |> case do
        {:ok, run} -> {:ok, run}
        {:error, cs} -> {:error, {:workflow_run_update_failed, %{changeset: cs}}}
      end
    end
  end

  @doc """
  List runs most-recent-first, with optional filters.

  Options:
    * `:status` — exact status match
    * `:scope` — exact scope match
    * `:limit` — max rows (default 50)
  """
  @spec list(keyword()) :: {:ok, [run()]}
  def list(opts \\ []) do
    status = Keyword.get(opts, :status)
    scope = Keyword.get(opts, :scope)
    limit = Keyword.get(opts, :limit, 50)

    # Secondary sort by id is required because `:utc_datetime` columns are
    # second-precision — two rows created in the same second would otherwise
    # have undefined relative order, surfacing as flaky test ordering.
    query =
      from(r in Run,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: ^limit
      )

    query = if status, do: where(query, [r], r.status == ^status), else: query
    query = if scope, do: where(query, [r], r.scope == ^scope), else: query

    {:ok, Repo.all(query)}
  end

  @doc """
  Return the most recently updated resumable run (`running` or `failed`),
  optionally filtered by scope.
  """
  @spec latest_resumable(keyword()) ::
          {:ok, run()} | {:error, {:no_resumable_workflow, map()}}
  def latest_resumable(opts \\ []) do
    scope = Keyword.get(opts, :scope)

    # Sort by inserted_at + id to match `list/1`. Both queries previously
    # disagreed (`list/1` used inserted_at, `latest_resumable/1` used
    # updated_at) which could surface a row in `list-runs` that was not
    # the same one resumed by `fam workflows resume`.
    query =
      from(r in Run,
        where: r.status in ^@resumable_statuses,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: 1
      )

    query = if scope, do: where(query, [r], r.scope == ^scope), else: query

    case Repo.one(query) do
      nil -> {:error, {:no_resumable_workflow, %{scope: scope}}}
      run -> {:ok, run}
    end
  end
end
