defmodule Familiar.CLI.Main do
  @moduledoc """
  CLI entry point for the `fam` command.

  Parses arguments, detects init mode vs normal mode, ensures the daemon
  is running, dispatches commands, and formats output.
  """

  alias Familiar.CLI.DaemonManager
  alias Familiar.CLI.HttpClient
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  @version Mix.Project.config()[:version]

  @doc "Escript entry point."
  def main(argv) do
    parsed = parse_args(argv)
    mode = format_mode(elem(parsed, 2))
    deps = default_deps()

    result = run(parsed, deps)
    output = Output.format(result, mode, text_formatter(elem(parsed, 0)))
    Output.puts(output)
    System.halt(Output.exit_code(result))
  end

  @doc false
  @spec parse_args([String.t()]) :: {String.t(), [String.t()], map()}
  def parse_args(argv) do
    {flags, args, _invalid} =
      OptionParser.parse(argv,
        strict: [json: :boolean, quiet: :boolean, help: :boolean],
        aliases: [j: :json, q: :quiet, h: :help]
      )

    flag_map = Enum.into(flags, %{})

    format_flags = Map.take(flag_map, [:json, :quiet])

    if flag_map[:help] || args == [] do
      {"help", [], format_flags}
    else
      [command | rest] = args
      {command, rest, format_flags}
    end
  end

  @doc false
  @spec format_mode(map()) :: :json | :text | :quiet
  def format_mode(%{json: true}), do: :json
  def format_mode(%{quiet: true}), do: :quiet
  def format_mode(_), do: :text

  @doc false
  @spec run({String.t(), [String.t()], map()}, map()) ::
          {:ok, term()} | {:error, {atom(), map()}}
  def run(parsed, deps)

  # Local commands — no daemon needed
  def run({"version", _, _}, _deps) do
    {:ok, %{version: @version}}
  end

  def run({"help", _, _}, _deps) do
    {:ok, %{help: help_text()}}
  end

  # All other commands need .familiar/ to exist
  def run({command, args, flags}, deps) do
    if File.dir?(Paths.familiar_dir()) do
      run_with_daemon({command, args, flags}, deps)
    else
      {:error, {:init_required, %{}}}
    end
  end

  # -- Commands that need daemon --

  defp run_with_daemon({"health", _, _}, deps) do
    with {:ok, port} <- deps.ensure_running_fn.(health_fn: deps.health_fn),
         {:ok, health} <- deps.health_fn.(port) do
      check_version_compatibility(health.version, deps)
      {:ok, health}
    end
  end

  defp run_with_daemon({"daemon", ["start"], _}, deps) do
    case deps.ensure_running_fn.(health_fn: deps.health_fn) do
      {:ok, port} -> {:ok, %{status: "started", port: port}}
      {:error, _} = error -> error
    end
  end

  defp run_with_daemon({"daemon", ["stop"], _}, deps) do
    case deps.stop_daemon_fn.([]) do
      :ok -> {:ok, %{status: "stopped"}}
      {:error, _} = error -> error
    end
  end

  defp run_with_daemon({"daemon", ["status"], _}, deps) do
    case deps.daemon_status_fn.(health_fn: deps.health_fn) do
      {:running, info} ->
        {:ok, Map.merge(%{daemon: "running"}, info)}

      {:stale, info} ->
        {:ok, Map.merge(%{daemon: "stale"}, info)}

      {:stopped, _} ->
        {:ok, %{daemon: "stopped"}}
    end
  end

  defp run_with_daemon({"daemon", _, _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam daemon <start|stop|status>"}}}
  end

  defp run_with_daemon({command, _, _}, _deps) do
    {:error, {:unknown_command, %{command: command}}}
  end

  # -- Private --

  defp check_version_compatibility(daemon_version, deps) do
    version_compatible_fn =
      Map.get(deps, :version_compatible_fn, &HttpClient.version_compatible?/2)

    unless version_compatible_fn.(@version, daemon_version) do
      IO.puts(
        :stderr,
        "Warning: Daemon is running version #{daemon_version} but CLI is #{@version}. " <>
          "Run `fam daemon restart` to update."
      )
    end
  end

  defp default_deps do
    %{
      ensure_running_fn: &DaemonManager.ensure_running/1,
      health_fn: &HttpClient.health_check/1,
      daemon_status_fn: &DaemonManager.daemon_status/1,
      stop_daemon_fn: &DaemonManager.stop_daemon/1
    }
  end

  defp text_formatter("health") do
    fn %{status: status, version: version} ->
      "Daemon is #{status} (version #{version})"
    end
  end

  defp text_formatter("version") do
    fn %{version: version} -> "fam #{version}" end
  end

  defp text_formatter("help") do
    fn %{help: text} -> text end
  end

  defp text_formatter("daemon") do
    fn
      %{daemon: status, port: port} -> "Daemon: #{status} on port #{port}"
      %{daemon: status} -> "Daemon: #{status}"
      %{status: status, port: port} -> "Daemon #{status} on port #{port}"
      %{status: status} -> "Daemon #{status}"
      other -> inspect(other, pretty: true)
    end
  end

  defp text_formatter(_), do: nil

  defp help_text do
    """
    fam - Familiar CLI

    Usage: fam <command> [options]

    Commands:
      health           Check daemon health and version
      version          Show CLI version
      daemon start     Start the daemon
      daemon stop      Stop the daemon
      daemon status    Show daemon status

    Options:
      --json, -j       Output as JSON
      --quiet, -q      Minimal output for scripting
      --help, -h       Show this help
    """
    |> String.trim()
  end
end
