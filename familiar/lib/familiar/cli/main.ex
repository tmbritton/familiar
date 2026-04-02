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
  alias Familiar.Knowledge
  alias Familiar.Knowledge.ConventionReviewer
  alias Familiar.Knowledge.Freshness
  alias Familiar.Knowledge.InitScanner
  alias Familiar.Knowledge.Management
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
        strict: [
          json: :boolean,
          quiet: :boolean,
          help: :boolean,
          refresh: :boolean,
          compact: :boolean,
          apply: :string
        ],
        aliases: [j: :json, q: :quiet, h: :help]
      )

    flag_map = Enum.into(flags, %{})

    format_flags = Map.take(flag_map, [:json, :quiet])
    context_flags = Map.take(flag_map, [:refresh, :compact, :apply])
    all_flags = Map.merge(format_flags, context_flags)

    if flag_map[:help] || args == [] do
      {"help", [], format_flags}
    else
      [command | rest] = args
      {command, rest, all_flags}
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

  defp run_with_daemon({"config", _, _}, _deps) do
    config_fn = &Familiar.Config.load/1
    config_path = Paths.config_path()

    case config_fn.(config_path) do
      {:ok, config} -> {:ok, config_to_map(config)}
      {:error, _} = error -> error
    end
  end

  defp run_with_daemon({"search", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam search <query>"}}}
  end

  defp run_with_daemon({"search", args, _}, deps) do
    query = Enum.join(args, " ")
    search_fn = Map.get(deps, :search_fn, &Knowledge.search/1)

    case search_fn.(query) do
      {:ok, results} -> {:ok, %{results: results, query: query}}
      {:error, _} = error -> error
    end
  end

  defp run_with_daemon({"entry", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam entry <id>"}}}
  end

  defp run_with_daemon({"entry", [id_string | _], _}, deps) do
    fetch_fn = Map.get(deps, :fetch_entry_fn, &Knowledge.fetch_entry/1)
    freshness_fn = Map.get(deps, :freshness_fn, &Freshness.validate_entries/2)

    case Integer.parse(id_string) do
      {id, ""} ->
        case fetch_fn.(id) do
          {:ok, entry} -> {:ok, format_entry_detail(entry, freshness_fn)}
          {:error, _} = error -> error
        end

      _ ->
        {:error, {:usage_error, %{message: "Invalid entry ID: #{id_string}"}}}
    end
  end

  defp run_with_daemon({"edit", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam edit <id> <new text>"}}}
  end

  defp run_with_daemon({"edit", [_id_string], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam edit <id> <new text>"}}}
  end

  defp run_with_daemon({"edit", [id_string | text_args], _}, deps) do
    update_fn = Map.get(deps, :update_entry_fn, &Knowledge.update_entry/2)
    fetch_fn = Map.get(deps, :fetch_entry_fn, &Knowledge.fetch_entry/1)

    case Integer.parse(id_string) do
      {id, ""} ->
        new_text = Enum.join(text_args, " ")

        with {:ok, entry} <- fetch_fn.(id),
             {:ok, updated} <- update_fn.(entry, %{text: new_text, source: "user"}) do
          {:ok, %{id: updated.id, text: updated.text, status: "edited"}}
        end

      _ ->
        {:error, {:usage_error, %{message: "Invalid entry ID: #{id_string}"}}}
    end
  end

  defp run_with_daemon({"delete", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam delete <id>"}}}
  end

  defp run_with_daemon({"delete", [id_string | _], _}, deps) do
    fetch_fn = Map.get(deps, :fetch_entry_fn, &Knowledge.fetch_entry/1)
    delete_fn = Map.get(deps, :delete_entry_fn, &Knowledge.delete_entry/1)

    case Integer.parse(id_string) do
      {id, ""} ->
        with {:ok, entry} <- fetch_fn.(id),
             :ok <- delete_fn.(entry) do
          {:ok, %{id: id, status: "deleted"}}
        end

      _ ->
        {:error, {:usage_error, %{message: "Invalid entry ID: #{id_string}"}}}
    end
  end

  defp run_with_daemon({"context", args, flags}, deps) do
    cond do
      Map.get(flags, :refresh, false) ->
        path_filter = find_path_arg(args)
        refresh_fn = Map.get(deps, :refresh_fn, &Management.refresh/2)
        project_dir = Map.get(deps, :project_dir, Paths.project_dir())
        refresh_fn.(project_dir, path: path_filter)

      Map.get(flags, :compact, false) ->
        run_compact(flags, deps)

      true ->
        {:error, {:usage_error, %{message: "Usage: fam context --refresh [path] | --compact [--apply <indices>]"}}}
    end
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

  defp run_compact(flags, deps) do
    candidates_fn = Map.get(deps, :compact_candidates_fn, &Management.find_consolidation_candidates/1)
    compact_fn = Map.get(deps, :compact_fn, &Management.compact/2)

    case Map.get(flags, :apply) do
      nil ->
        candidates_fn.([])

      indices_str ->
        with {:ok, %{candidates: candidates}} <- candidates_fn.([]),
             {:ok, pairs} <- parse_apply_indices(indices_str, candidates) do
          compact_fn.(pairs, [])
        end
    end
  end

  defp parse_apply_indices(indices_str, candidates) do
    indices =
      indices_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    if Enum.any?(indices, &(&1 == :error)) do
      {:error, {:usage_error, %{message: "Invalid indices: #{indices_str}. Use comma-separated numbers."}}}
    else
      pairs =
        indices
        |> Enum.map(fn {i, _} -> i - 1 end)
        |> Enum.filter(&(&1 >= 0 and &1 < length(candidates)))
        |> Enum.map(fn i ->
          c = Enum.at(candidates, i)
          {c.id_a, c.id_b}
        end)

      {:ok, pairs}
    end
  end

  defp format_entry_detail(entry, freshness_fn) do
    metadata =
      case Jason.decode(entry.metadata || "{}") do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end

    freshness = resolve_freshness(entry, freshness_fn)

    %{
      id: entry.id,
      text: entry.text,
      type: entry.type,
      source: entry.source,
      source_file: entry.source_file,
      metadata: metadata,
      freshness: freshness,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp resolve_freshness(entry, freshness_fn) do
    case freshness_fn.([entry], []) do
      {:ok, %{fresh: fresh, stale: stale, deleted: deleted}} ->
        cond do
          entry in fresh -> :fresh
          entry in stale -> :stale
          entry in deleted -> :deleted
          true -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp find_path_arg(args) do
    args
    |> Enum.reject(&String.starts_with?(&1, "--"))
    |> List.first()
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

  defp config_to_map(%Familiar.Config{} = config) do
    %{
      provider: config.provider,
      language: config.language,
      scan: config.scan,
      notifications: config.notifications
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

  defp text_formatter("search") do
    fn %{results: results, query: query} ->
      format_search_results(results, query)
    end
  end

  defp text_formatter("conventions") do
    fn %{conventions: conventions, review_mode: review_mode} ->
      format_conventions_text(conventions, review_mode)
    end
  end

  defp text_formatter("config") do
    fn config -> format_config_text(config) end
  end

  defp text_formatter("entry") do
    fn entry ->
      freshness_tag = if entry[:freshness], do: " [#{entry.freshness}]", else: ""

      lines = [
        "Entry ##{entry.id}#{freshness_tag}",
        "  Type: #{entry.type}",
        "  Source: #{entry.source}",
        "  Text: #{entry.text}"
      ]

      lines =
        if entry.source_file,
          do: lines ++ ["  File: #{entry.source_file}"],
          else: lines

      lines = lines ++ ["  Created: #{entry.inserted_at}"]

      lines =
        if entry.metadata != %{},
          do: lines ++ ["  Metadata: #{inspect(entry.metadata)}"],
          else: lines

      Enum.join(lines, "\n")
    end
  end

  defp text_formatter("edit") do
    fn %{id: id} -> "Entry ##{id} updated" end
  end

  defp text_formatter("delete") do
    fn %{id: id} -> "Entry ##{id} deleted" end
  end

  defp text_formatter("context") do
    fn
      %{scanned: s, updated: u, created: c, removed: r, preserved: p} ->
        lines = [
          "Context refresh complete:",
          "  Scanned: #{s}",
          "  Updated: #{u}",
          "  Created: #{c}",
          "  Removed: #{r}",
          "  Preserved (user): #{p}"
        ]

        Enum.join(lines, "\n")

      %{candidates: []} ->
        "No consolidation candidates found"

      %{candidates: candidates} ->
        format_compact_candidates(candidates)

      other ->
        inspect(other, pretty: true)
    end
  end

  defp text_formatter(_), do: nil

  defp format_compact_candidates(candidates) do
    header = "Consolidation candidates (#{length(candidates)}):\n"

    lines =
      candidates
      |> Enum.with_index(1)
      |> Enum.map(fn {c, idx} ->
        "  #{idx}. [#{c.type}] \"#{truncate(c.text_a, 40)}\" ↔ \"#{truncate(c.text_b, 40)}\" (distance: #{Float.round(c.distance, 3)})"
      end)

    header <> Enum.join(lines, "\n")
  end

  defp truncate(text, max) do
    if String.length(text) > max,
      do: String.slice(text, 0, max) <> "...",
      else: text
  end

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

  defp format_config_text(config) do
    lines = ["Configuration:"]

    lines =
      lines ++
        [
          "  [provider]",
          "    base_url = #{config.provider.base_url}",
          "    chat_model = #{config.provider.chat_model}",
          "    embedding_model = #{config.provider.embedding_model}",
          "    timeout = #{config.provider.timeout}"
        ]

    lines =
      if config.language != %{} do
        lang_lines =
          config.language
          |> Enum.sort()
          |> Enum.map(fn {k, v} -> "    #{k} = #{inspect(v)}" end)

        lines ++ ["  [language]"] ++ lang_lines
      else
        lines ++ ["  [language] (not configured)"]
      end

    lines =
      lines ++
        [
          "  [scan]",
          "    max_files = #{config.scan.max_files}",
          "    large_project_threshold = #{config.scan.large_project_threshold}",
          "  [notifications]",
          "    provider = #{config.notifications.provider}",
          "    enabled = #{config.notifications.enabled}"
        ]

    Enum.join(lines, "\n")
  end

  defp format_search_results([], query) do
    "No results found for \"#{query}\""
  end

  defp format_search_results(results, query) do
    header = "Search results for \"#{query}\" (#{length(results)} found):\n"

    lines =
      results
      |> Enum.with_index(1)
      |> Enum.map(&format_search_line/1)

    header <> Enum.join(lines, "\n\n")
  end

  defp format_search_line({result, idx}) do
    source_info =
      [result[:source_file], result[:source]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")

    freshness_tag = freshness_indicator(result[:freshness])

    "  #{idx}. [#{result.type}] #{result.text}#{freshness_tag}\n     Source: #{source_info}"
  end

  defp freshness_indicator(:stale), do: " [stale]"
  defp freshness_indicator(:unknown), do: " [?]"
  defp freshness_indicator(_), do: ""

  defp help_text do
    """
    fam - Familiar CLI

    Usage: fam <command> [options]

    Commands:
      init               Initialize Familiar on this project
      search <query>     Search knowledge store by semantic similarity
      entry <id>         Inspect a knowledge entry
      edit <id> <text>   Edit a knowledge entry (re-embeds, tags as user)
      delete <id>        Delete a knowledge entry
      context --refresh [path]  Re-scan project or path
      context --compact  Find and consolidate duplicate entries
      config             Show current configuration
      conventions        List discovered conventions
      conventions review Review and approve conventions
      health             Check daemon health and version
      version            Show CLI version
      daemon start       Start the daemon
      daemon stop        Stop the daemon
      daemon status      Show daemon status

    Options:
      --json, -j       Output as JSON
      --quiet, -q      Minimal output for scripting
      --help, -h       Show this help
    """
    |> String.trim()
  end
end
