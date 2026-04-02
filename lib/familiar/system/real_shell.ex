defmodule Familiar.System.RealShell do
  @moduledoc """
  Production adapter for the Shell behaviour.

  Delegates to `System.cmd/3` for executing shell commands.
  """

  @behaviour Familiar.System.Shell

  @impl true
  def cmd(command, args, opts \\ []) do
    cmd_opts = Keyword.merge([stderr_to_stdout: true], opts)

    case System.cmd(command, args, cmd_opts) do
      {output, exit_code} ->
        {:ok, %{output: output, exit_code: exit_code}}
    end
  rescue
    e in ErlangError ->
      {:error, {:shell_error, %{reason: inspect(e.original)}}}

    e ->
      {:error, {:shell_error, %{reason: Exception.message(e)}}}
  end
end
