defmodule Familiar.Work do
  @moduledoc """
  Public API for the Work context.

  Manages the four-level work hierarchy (Epic → Group → Task → Subtask),
  state machine transitions, dependency resolution, and triage roll-up.
  """

  use Boundary, deps: [], exports: [Familiar.Work]

  @doc "Fetch a single task by ID."
  @spec fetch_task(integer()) :: {:error, {:not_implemented, %{}}}
  def fetch_task(_id), do: {:error, {:not_implemented, %{}}}

  @doc "List tasks matching the given filters."
  @spec list_tasks(keyword()) :: [map()]
  def list_tasks(_filters \\ []), do: []

  @doc "Update a task's status."
  @spec update_status(integer(), atom()) :: {:error, {:not_implemented, %{}}}
  def update_status(_id, _status), do: {:error, {:not_implemented, %{}}}
end
