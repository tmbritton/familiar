defmodule Familiar.Files do
  @moduledoc """
  Public API for the Files context.

  Manages atomic file operations via transaction log, rollback on failure,
  and .fam-pending conflict detection.
  """

  use Boundary, deps: [], exports: [Familiar.Files]

  @doc "Write a file atomically via the transaction log."
  @spec write(integer(), String.t(), binary()) :: :ok | {:error, {atom(), map()}}
  def write(_task_id, _path, _content), do: {:error, {:not_implemented, %{}}}

  @doc "Rollback all file changes for a task."
  @spec rollback_task(integer()) :: :ok | {:error, {atom(), map()}}
  def rollback_task(_task_id), do: {:error, {:not_implemented, %{}}}

  @doc "List pending .fam-pending conflict files."
  @spec pending_conflicts() :: {:ok, [map()]} | {:error, {atom(), map()}}
  def pending_conflicts, do: {:ok, []}
end
