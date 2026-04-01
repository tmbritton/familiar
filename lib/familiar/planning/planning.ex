defmodule Familiar.Planning do
  @moduledoc """
  Public API for the Planning context.

  Manages context-aware planning conversations, spec generation with
  verification marks, and task decomposition with dependency mapping.
  """

  use Boundary, deps: [Familiar.Knowledge, Familiar.Work, Familiar.Providers], exports: []

  @doc "Start a new planning conversation for a feature description."
  @spec start_plan(String.t()) :: {:ok, map()} | {:error, {atom(), map()}}
  def start_plan(_description), do: {:error, {:not_implemented, %{}}}

  @doc "Send a user response to an active planning conversation."
  @spec respond(integer(), String.t()) :: {:ok, map()} | {:error, {atom(), map()}}
  def respond(_session_id, _message), do: {:error, {:not_implemented, %{}}}

  @doc "Fetch a spec by ID."
  @spec get_spec(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def get_spec(_id), do: {:error, {:not_implemented, %{}}}
end
