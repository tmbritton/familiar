defmodule Familiar.System.Shell do
  @moduledoc """
  Behaviour for shell command execution.

  Abstracts system command calls so tests can use scripted mock results
  instead of running real commands.
  """

  @type cmd_opts :: keyword()

  @doc "Execute a shell command and return its output and exit status."
  @callback cmd(command :: String.t(), args :: [String.t()], opts :: cmd_opts()) ::
              {:ok, %{output: String.t(), exit_code: non_neg_integer()}}
              | {:error, {atom(), map()}}
end
