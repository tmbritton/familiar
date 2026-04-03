defmodule Familiar.Execution.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for all agent processes.

  Every agent — coder, reviewer, librarian, project-manager, or any
  user-defined role — runs as an `AgentProcess` child under this
  supervisor. The supervisor provides crash isolation: one agent
  failure does not affect others.
  """

  use DynamicSupervisor

  @doc "Start the agent supervisor."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start an agent process under the supervisor.

  ## Options

    * `:role` — role name (required)
    * `:task` — task description (required)
    * `:parent` — parent pid to notify on completion (optional)
  """
  @spec start_agent(keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Familiar.Execution.AgentProcess, opts})
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
