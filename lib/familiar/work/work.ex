defmodule Familiar.Work do
  @moduledoc """
  Public API for the Work context.

  Manages the four-level work hierarchy (Epic → Group → Task → Subtask),
  state machine transitions, dependency resolution, and triage roll-up.
  """

  use Boundary, deps: [], exports: [Familiar.Work]

  @doc "Fetch a single task by ID."
  @spec fetch_task(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def fetch_task(_id), do: {:error, {:not_implemented, %{}}}

  @doc "List tasks matching the given filters."
  @spec list_tasks(keyword()) :: [map()]
  def list_tasks(_filters \\ []), do: []

  @doc "Update a task's status."
  @spec update_status(integer(), atom()) :: {:ok, map()} | {:error, {atom(), map()}}
  def update_status(_id, _status), do: {:error, {:not_implemented, %{}}}
end
