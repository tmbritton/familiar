defmodule Familiar.Execution do
  @moduledoc """
  Public API for the Execution context.

  Manages task dispatch, agent runner supervision, tool call execution,
  validation pipeline, and self-repair logic.
  """

  use Boundary,
    deps: [Familiar.Knowledge, Familiar.Work, Familiar.Files, Familiar.Providers],
    exports: [Familiar.Extension, Familiar.Hooks, Familiar.Execution.ToolRegistry]

  @doc "Dispatch a task for execution."
  @spec dispatch(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def dispatch(_task_id), do: {:error, {:not_implemented, %{}}}

  @doc "Cancel a running task and rollback in-progress changes."
  @spec cancel(integer()) :: :ok | {:error, {atom(), map()}}
  def cancel(_task_id), do: {:error, {:not_implemented, %{}}}

  @doc "Get current execution status."
  @spec status() :: {:ok, map()} | {:error, {atom(), map()}}
  def status, do: {:error, {:not_implemented, %{}}}
end
