defmodule Familiar.Daemon.RecoveryGate do
  @moduledoc """
  Synchronous recovery gate for the supervision tree.

  Placed after Repo and Migrator in the children list. Runs crash
  recovery synchronously during `start_link/1`, then returns `:ignore`
  so no process is kept running. The supervisor proceeds to the next
  child only after recovery completes.
  """

  alias Familiar.Daemon.Recovery

  def start_link(_opts) do
    Recovery.run_if_needed()
    :ignore
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end
end
