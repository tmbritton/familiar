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
  alias Familiar.Knowledge.ConventionReviewer
  alias Familiar.Knowledge.InitScanner
  alias Familiar.Knowledge.Prerequisites

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

  # Init command — runs without daemon
  def run({"init", _, _}, deps) do
    if File.dir?(Paths.familiar_dir()) do
      {:error, {:already_initialized, %{path: Paths.familiar_dir()}}}
    else
      run_init(deps)
    end
  end

  # All other commands need .familiar/ to exist
  def run({command, args, flags}, deps) do
    if File.dir?(Paths.familiar_dir()) do
      run_with_daemon({command, args, flags}, deps)
    else
      # Auto-init: run init first, then retry the original command
      case run_init(deps) do
        {:ok, _init_summary} ->
          run_with_daemon({command, args, flags}, deps)

        {:error, _} = error ->
          error
      end
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

  defp run_with_daemon({"conventions", args, _}, deps) do
    with {:ok, port} <- deps.ensure_running_fn.(health_fn: deps.health_fn),
         {:ok, conventions} <-
           Map.get(deps, :conventions_fn, &default_conventions/1).(port) do
      handle_conventions(conventions, args, deps)
    end
  end

  defp run_with_daemon({command, _, _}, _deps) do
    {:error, {:unknown_command, %{command: command}}}
  end

  defp handle_conventions(conventions, args, deps) do
    if "review" in args do
      review_fn = Map.get(deps, :review_fn, &ConventionReviewer.review/2)

      with {:ok, review_result} <- review_fn.(conventions, []) do
        {:ok, Map.merge(%{conventions: conventions, review_mode: true}, review_result)}
      end
    else
      {:ok, %{conventions: conventions, review_mode: false}}
    end
  end

  # -- Init --

  defp run_init(deps) do
    prerequisites_fn = Map.get(deps, :prerequisites_fn, &Prerequisites.check/1)
    init_fn = Map.get(deps, :init_fn, &default_init/1)

    with {:ok, _provider_info} <- prerequisites_fn.([]) do
      init_fn.(progress_fn: &init_progress/1)
    end
  end

  defp default_init(opts) do
    project_dir = Paths.project_dir()

    InitScanner.run_with_cleanup(project_dir, fn ->
      Paths.ensure_familiar_dir!()
      InitScanner.run(project_dir, opts)
    end)
  end

  defp init_progress(msg) do
    IO.puts(:stderr, msg)
  end

  defp default_conventions(port) do
    _ = port

    entries =
      Familiar.Knowledge.Entry
      |> Familiar.Knowledge.list_by_type("convention")
      |> Enum.map(&format_convention_entry/1)

    {:ok, entries}
  end

  defp format_convention_entry(entry) do
    meta =
      case Jason.decode(entry.metadata || "{}") do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end

    %{
      id: entry.id,
      text: entry.text,
      evidence_count: meta["evidence_count"] || 0,
      evidence_total: meta["evidence_total"] || 0,
      evidence_ratio: meta["evidence_ratio"] || 0.0,
      reviewed: meta["reviewed"] || false
    }
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

  defp text_formatter("init") do
    fn summary ->
      lines = [
        "Initialization complete!",
        "  Files scanned: #{summary.files_scanned}",
        "  Knowledge entries: #{summary.entries_created}",
        "  Conventions discovered: #{summary[:conventions_discovered] || 0}"
      ]

      lines =
        if summary[:deferred] && summary.deferred > 0 do
          lines ++ ["  Deferred: #{summary.deferred} files (will be processed later)"]
        else
          lines
        end

      lines =
        if summary[:warning] do
          lines ++ ["  Warning: #{summary.warning}"]
        else
          lines ++ ["", "Try: fam plan \"describe a feature\" — your spec will appear for review"]
        end

      Enum.join(lines, "\n")
    end
  end

  defp text_formatter("conventions") do
    fn %{conventions: conventions, review_mode: review_mode} ->
      format_conventions_text(conventions, review_mode)
    end
  end

  defp text_formatter(_), do: nil

  defp format_conventions_text([], _review_mode) do
    "No conventions discovered yet. Run `fam init` first."
  end

  defp format_conventions_text(conventions, review_mode) do
    header =
      if review_mode,
        do: "Conventions for review (#{length(conventions)}):",
        else: "Discovered conventions (#{length(conventions)}):"

    lines =
      conventions
      |> Enum.with_index(1)
      |> Enum.map(&format_convention_line/1)

    Enum.join([header | lines], "\n")
  end

  defp format_convention_line({conv, idx}) do
    status = if conv[:reviewed], do: " [reviewed]", else: ""
    evidence = "(#{conv.evidence_count}/#{conv.evidence_total})"
    "  #{idx}. #{conv.text} #{evidence}#{status}"
  end

  defp help_text do
    """
    fam - Familiar CLI

    Usage: fam <command> [options]

    Commands:
      init             Initialize Familiar on this project
      conventions      List discovered conventions
      conventions review  Review and approve conventions
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
