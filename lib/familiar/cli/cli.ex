defmodule Familiar.CLI do
  @moduledoc """
  Public API for the CLI context.

  The CLI is architecturally a CLIENT of the daemon — it calls HTTP
  endpoints and Channel topics only. It never imports from knowledge/,
  work/, planning/, or any other business domain context directly.
  """

  use Boundary, deps: [], exports: []

  @doc "CLI entry point — parse args and dispatch command."
  @spec main([String.t()]) :: :ok
  def main(_args), do: :ok
end
