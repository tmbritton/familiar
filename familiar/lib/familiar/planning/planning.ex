defmodule Familiar.Planning do
  @moduledoc """
  Public API for the Planning context.

  Manages context-aware planning conversations, spec generation with
  verification marks, and task decomposition with dependency mapping.
  """

  use Boundary, deps: [Familiar.Knowledge, Familiar.Work, Familiar.Providers], exports: []

  alias Familiar.Planning.Engine

  @doc "Start a new planning conversation for a feature description."
  @spec start_plan(String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def start_plan(description, opts \\ []), do: Engine.start_plan(description, opts)

  @doc "Send a user response to an active planning conversation."
  @spec respond(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def respond(session_id, message, opts \\ []), do: Engine.respond(session_id, message, opts)

  @doc "Resume a planning conversation by session ID."
  @spec resume(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def resume(session_id), do: Engine.resume(session_id)

  @doc "Find the latest active session."
  @spec latest_active_session() :: {:ok, integer()} | {:error, {atom(), map()}}
  def latest_active_session, do: Engine.latest_active_session()

  @doc "Generate a spec from a completed planning session."
  @spec generate_spec(integer(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def generate_spec(session_id, opts \\ []), do: Engine.generate_spec(session_id, opts)

  @doc "Fetch a spec by ID."
  @spec get_spec(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def get_spec(spec_id), do: Engine.get_spec(spec_id)
end
