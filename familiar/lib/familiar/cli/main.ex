defmodule Familiar.CLI.Main do
  @moduledoc """
  CLI entry point for the `fam` command.

  Parses arguments, detects init mode vs normal mode, ensures the daemon
  is running, dispatches commands, and formats output.
  """

  alias Familiar.CLI.DaemonManager
  alias Familiar.CLI.HttpClient
  alias Familiar.CLI.Output
  alias Familiar.Config.Generator, as: ConfigGenerator
  alias Familiar.Daemon.Paths
  alias Familiar.Execution.AgentSupervisor
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRuns
  alias Familiar.Knowledge
  alias Familiar.Knowledge.Backup
  alias Familiar.Knowledge.ConventionReviewer
  alias Familiar.Knowledge.Freshness
  alias Familiar.Knowledge.InitScanner
  alias Familiar.Knowledge.Management
  alias Familiar.Knowledge.Prerequisites
  alias Familiar.Roles

  @version Mix.Project.config()[:version]

  @doc "Escript entry point."
  @dialyzer {:no_return, main: 1}
  def main(argv) do
    # Check if this is a bare `fam` in an uninitialized project
    # Use env var directly since Application config isn't loaded yet
    project_dir = System.get_env("FAMILIAR_PROJECT_DIR") || File.cwd!()
    familiar_dir = Path.join(project_dir, ".familiar")

    initialized = File.dir?(Path.join(familiar_dir, "roles"))

    if argv == [] and not initialized do
      bootstrap()
      IO.puts("Run `fam` again to start chatting.")
      System.halt(0)
    end

    bootstrap()

    parsed = parse_args(argv)
    mode = format_mode(elem(parsed, 2))
    deps = default_deps()

    result = run(parsed, deps)
    output = Output.format(result, mode, text_formatter(elem(parsed, 0)))
    Output.puts(output)
    System.halt(Output.exit_code(result))
  end

  defp bootstrap do
    # Start the OTP application (Repo, PubSub, ToolRegistry, Hooks, etc.)
    {:ok, _} = Application.ensure_all_started(:familiar)
    ensure_project_initialized()
  rescue
    e ->
      IO.puts(:stderr, "Failed to start Familiar: #{Exception.message(e)}")
      System.halt(1)
  end

  defp ensure_project_initialized do
    familiar_dir = Paths.familiar_dir()
    roles_dir = Path.join(familiar_dir, "roles")

    unless File.dir?(roles_dir) do
      IO.puts(:stderr, "[familiar] First run — initializing project...")

      File.mkdir_p!(roles_dir)
      File.mkdir_p!(Path.join(familiar_dir, "skills"))
      File.mkdir_p!(Path.join(familiar_dir, "workflows"))

      Knowledge.DefaultFiles.install(familiar_dir)
      detected_lang = ConfigGenerator.detect_project_language(Paths.project_dir())
      ConfigGenerator.generate_default(familiar_dir, detected_lang)

      if detected_lang do
        IO.puts(:stderr, "[familiar] Detected language: #{detected_lang}")
      end

      IO.puts(:stderr, "[familiar] Edit .familiar/config.toml to configure your LLM provider")
    end
  end

  @doc false
  @spec parse_args([String.t()]) :: {String.t(), [String.t()], map()}
  def parse_args(argv) do
    {flags, args, invalid} =
      OptionParser.parse(argv,
        strict: [
          json: :boolean,
          quiet: :boolean,
          help: :boolean,
          refresh: :boolean,
          compact: :boolean,
          health: :boolean,
          force: :boolean,
          apply: :string,
          resume: :boolean,
          session: :integer,
          raw: :boolean,
          role: :string,
          scope: :string,
          cleanup: :boolean,
          provider: :string,
          id: :integer,
          status: :string,
          limit: :integer,
          reindex: :boolean
        ],
        aliases: [j: :json, q: :quiet, h: :help, r: :role]
      )

    # Stash any rejected switches so command handlers can fail loudly instead
    # of silently ignoring bad input (e.g., `--id abc` previously fell through
    # to the no-arg path of `fam workflows resume`).
    flag_map =
      flags
      |> Enum.into(%{})
      |> Map.put(:_invalid, invalid)

    format_flags = Map.take(flag_map, [:json, :quiet])

    context_flags =
      Map.take(flag_map, [
        :refresh,
        :compact,
        :health,
        :force,
        :apply,
        :resume,
        :session,
        :raw,
        :role,
        :scope,
        :cleanup,
        :provider,
        :id,
        :status,
        :limit,
        :reindex,
        :_invalid
      ])

    all_flags = Map.merge(format_flags, context_flags)

    cond do
      flag_map[:help] ->
        {"help", [], format_flags}

      args == [] ->
        # No command: chat if initialized, init if not
        if File.dir?(Paths.familiar_dir()) do
          {"chat", [], all_flags}
        else
          {"init", [], all_flags}
        end

      true ->
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

  defp run_with_daemon({"status", _, _}, deps) do
    health_fn = Map.get(deps, :context_health_fn, &Knowledge.health/1)

    case health_fn.([]) do
      {:ok, health} -> {:ok, Map.put(health, :command, "status")}
      {:error, _} = error -> error
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

  # -- Chat mode --

  defp run_with_daemon({"chat", _, %{resume: true} = flags}, deps) do
    session_id = Map.get(flags, :session)
    resume_chat(session_id, deps)
  end

  defp run_with_daemon({"chat", _, %{session: session_id}}, deps) when is_integer(session_id) do
    resume_chat(session_id, deps)
  end

  defp run_with_daemon({"chat", _, flags}, deps) do
    role = Map.get(flags, :role, "user-manager")
    run_chat(role, deps)
  end

  # -- Workflow commands --

  defp run_with_daemon({"plan", _, %{resume: true} = flags}, deps) do
    session_id = Map.get(flags, :session)
    resume_planning(session_id, deps)
  end

  defp run_with_daemon({"plan", _, %{session: session_id}}, deps) when is_integer(session_id) do
    resume_planning(session_id, deps)
  end

  defp run_with_daemon({"plan", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam plan <description>"}}}
  end

  defp run_with_daemon({"plan", args, _flags}, deps) do
    run_workflow_command("plan", "feature-planning", args, deps)
  end

  defp run_with_daemon({"do", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam do <description>"}}}
  end

  defp run_with_daemon({"do", args, _flags}, deps) do
    run_workflow_command("do", "feature-implementation", args, deps)
  end

  defp run_with_daemon({"fix", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam fix <description>"}}}
  end

  defp run_with_daemon({"fix", args, _flags}, deps) do
    run_workflow_command("fix", "task-fix", args, deps)
  end

  defp run_with_daemon({"search", [], _}, _deps) do
    {:error, {:usage_error, %{message: "Usage: fam search <query>"}}}
  end

  defp run_with_daemon({"search", args, _flags}, deps) do
    query = Enum.join(args, " ")
    run_raw_search(query, deps)
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

  defp run_with_daemon({"backup", _, _}, deps) do
    backup_fn = Map.get(deps, :backup_fn, &Backup.create/1)
    backup_fn.([])
  end

  defp run_with_daemon({"restore", args, flags}, deps) do
    run_restore(args, flags, deps)
  end

  defp run_with_daemon({"context", args, flags}, deps) do
    reindex = Map.get(flags, :reindex, false)
    refresh = Map.get(flags, :refresh, false)

    cond do
      reindex and refresh ->
        {:error,
         {:usage_error,
          %{message: "Cannot combine --reindex and --refresh; run them separately."}}}

      Map.get(flags, :health, false) ->
        health_fn = Map.get(deps, :context_health_fn, &Knowledge.health/1)
        health_fn.([])

      refresh ->
        path_filter = find_path_arg(args)
        refresh_fn = Map.get(deps, :refresh_fn, &Management.refresh/2)
        project_dir = Map.get(deps, :project_dir, Paths.project_dir())
        refresh_fn.(project_dir, path: path_filter)

      Map.get(flags, :compact, false) ->
        run_compact(flags, deps)

      reindex ->
        run_context_reindex(deps)

      true ->
        {:error,
         {:usage_error,
          %{
            message:
              "Usage: fam context --refresh [path] | --compact [--apply <indices>] | --health | --reindex"
          }}}
    end
  end

  defp run_with_daemon({"conventions", args, _}, deps) do
    with {:ok, port} <- deps.ensure_running_fn.(health_fn: deps.health_fn),
         {:ok, conventions} <-
           Map.get(deps, :conventions_fn, &default_conventions/1).(port) do
      handle_conventions(conventions, args, deps)
    end
  end

  # -- Role & Skill management --

  defp run_with_daemon({"roles", [], _}, deps) do
    list_fn = Map.get(deps, :list_roles_fn, &Roles.list_roles/1)

    case list_fn.(familiar_dir_opts()) do
      {:ok, roles} ->
        {:ok,
         %{
           roles:
             Enum.map(roles, fn r ->
               %{name: r.name, description: r.description, skills_count: length(r.skills)}
             end)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp run_with_daemon({"roles", [name | _], _}, deps) do
    load_fn = Map.get(deps, :load_role_fn, &Roles.load_role/2)

    case load_fn.(name, familiar_dir_opts()) do
      {:ok, role} ->
        {:ok,
         %{
           role: %{
             name: role.name,
             description: role.description,
             model: role.model,
             lifecycle: role.lifecycle,
             skills: role.skills,
             prompt_preview: String.slice(role.system_prompt, 0, 200)
           }
         }}

      {:error, _} = error ->
        error
    end
  end

  defp run_with_daemon({"skills", [], _}, deps) do
    list_fn = Map.get(deps, :list_skills_fn, &Roles.list_skills/1)

    case list_fn.(familiar_dir_opts()) do
      {:ok, skills} ->
        {:ok,
         %{
           skills:
             Enum.map(skills, fn s ->
               %{name: s.name, description: s.description, tools_count: length(s.tools)}
             end)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp run_with_daemon({"skills", [name | _], _}, deps) do
    load_fn = Map.get(deps, :load_skill_fn, &Roles.load_skill/2)

    case load_fn.(name, familiar_dir_opts()) do
      {:ok, skill} ->
        {:ok,
         %{
           skill: %{
             name: skill.name,
             description: skill.description,
             tools: skill.tools,
             constraints: skill.constraints,
             instructions_preview: String.slice(skill.instructions, 0, 200)
           }
         }}

      {:error, _} = error ->
        error
    end
  end

  # -- Session management --

  defp run_with_daemon({"sessions", _, %{cleanup: true}}, deps) do
    cleanup_fn = Map.get(deps, :cleanup_sessions_fn, &Familiar.Conversations.cleanup_stale/1)
    cleanup_fn.([])
  end

  defp run_with_daemon({"sessions", [id_string], _}, deps) do
    get_fn = Map.get(deps, :get_session_fn, &Familiar.Conversations.get/1)
    messages_fn = Map.get(deps, :messages_fn, &Familiar.Conversations.messages/1)

    with {id, ""} <- Integer.parse(id_string),
         {:ok, conv} <- get_fn.(id),
         {:ok, msgs} <- messages_fn.(id) do
      recent = msgs |> Enum.take(-5) |> Enum.map(&format_session_message/1)

      {:ok,
       %{
         session: %{
           id: conv.id,
           scope: conv.scope,
           status: conv.status,
           description: conv.description,
           created_at: conv.inserted_at,
           message_count: length(msgs),
           recent_messages: recent
         }
       }}
    else
      :error -> {:error, {:usage_error, %{message: "Invalid session ID: #{id_string}"}}}
      {:error, _} = error -> error
    end
  end

  defp run_with_daemon({"sessions", [], flags}, deps) do
    list_fn = Map.get(deps, :list_sessions_fn, &Familiar.Conversations.list/1)
    scope = Map.get(flags, :scope)
    opts = if scope, do: [scope: scope], else: []

    case list_fn.(opts) do
      {:ok, conversations} ->
        {:ok,
         %{
           sessions:
             Enum.map(conversations, fn c ->
               %{
                 id: c.id,
                 scope: c.scope,
                 status: c.status,
                 description: truncate(c.description || "", 40),
                 updated_at: c.updated_at
               }
             end)
         }}

      {:error, _} = error ->
        error
    end
  end

  # -- Workflow & Extension management --

  defp run_with_daemon({"workflows", [], _}, deps) do
    list_fn = Map.get(deps, :list_workflows_fn, &WorkflowRunner.list_workflows/1)

    case list_fn.(familiar_dir_opts()) do
      {:ok, workflows} ->
        {:ok,
         %{
           workflows:
             Enum.map(workflows, fn wf ->
               %{name: wf.name, description: wf.description, step_count: length(wf.steps)}
             end)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp run_with_daemon({"workflows", ["resume" | _], flags}, deps) do
    run_workflows_resume(flags, deps)
  end

  defp run_with_daemon({"workflows", ["list-runs" | _], flags}, deps) do
    run_workflows_list_runs(flags, deps)
  end

  defp run_with_daemon({"workflows", [name | _], _}, deps) do
    parse_fn = Map.get(deps, :parse_workflow_fn, &WorkflowRunner.parse/1)
    path = Path.join([Paths.familiar_dir(), "workflows", "#{name}.md"])

    case parse_fn.(path) do
      {:ok, wf} ->
        {:ok,
         %{
           workflow: %{
             name: wf.name,
             description: wf.description,
             steps:
               Enum.map(wf.steps, fn s ->
                 %{name: s.name, role: s.role, mode: s.mode}
               end)
           }
         }}

      {:error, _} = error ->
        error
    end
  end

  defp run_with_daemon({"extensions", _, _}, deps) do
    list_fn = Map.get(deps, :list_extensions_fn, &list_loaded_extensions/0)
    list_fn.()
  end

  # -- Validate commands --

  defp run_with_daemon({"validate", args, _}, deps) do
    validate_fn = Map.get(deps, :validate_fn, &run_validation/2)
    validate_fn.(args, familiar_dir_opts())
  end

  defp run_with_daemon({command, _, _}, _deps) do
    {:error, {:unknown_command, %{command: command}}}
  end

  defp run_validation(args, opts) do
    target =
      case args do
        ["roles"] -> :roles
        ["skills"] -> :skills
        ["workflows"] -> :workflows
        _ -> :all
      end

    roles_results = if target in [:all, :roles], do: validate_all_roles(opts), else: []
    skills_results = if target in [:all, :skills], do: validate_all_skills(opts), else: []

    workflows_results =
      if target in [:all, :workflows], do: validate_all_workflows(opts), else: []

    all = roles_results ++ skills_results ++ workflows_results
    passed = Enum.count(all, &(&1.status == :pass))
    warnings = Enum.count(all, &(&1.status == :warn))
    errors = Enum.count(all, &(&1.status == :error))

    {:ok,
     %{
       validation: %{
         roles: roles_results,
         skills: skills_results,
         workflows: workflows_results,
         summary: %{passed: passed, warnings: warnings, errors: errors}
       }
     }}
  end

  defp validate_all_roles(opts) do
    {:ok, roles} = Roles.list_roles(opts)

    Enum.map(roles, fn role ->
      case Roles.validate_role(role.name, opts) do
        :ok ->
          %{name: role.name, type: :role, status: :pass}

        {:error, {_, %{reason: reason}}} ->
          %{name: role.name, type: :role, status: :error, message: reason}
      end
    end)
  end

  defp validate_all_skills(opts) do
    {:ok, skills} = Roles.list_skills(opts)

    Enum.map(skills, fn skill ->
      unknown =
        Enum.reject(skill.tools, &(&1 in Roles.Validator.mvp_tools()))

      if unknown == [] do
        %{name: skill.name, type: :skill, status: :pass}
      else
        %{
          name: skill.name,
          type: :skill,
          status: :warn,
          message: "references unknown tools: #{Enum.join(unknown, ", ")}"
        }
      end
    end)
  end

  defp validate_all_workflows(opts) do
    {:ok, workflows} = WorkflowRunner.list_workflows(opts)

    Enum.map(workflows, fn wf ->
      missing_roles =
        wf.steps
        |> Enum.reject(fn step ->
          match?({:ok, _}, Roles.load_role(step.role, opts))
        end)
        |> Enum.map(& &1.role)
        |> Enum.uniq()

      if missing_roles == [] do
        %{name: wf.name, type: :workflow, status: :pass}
      else
        %{
          name: wf.name,
          type: :workflow,
          status: :error,
          message: "references unknown roles: #{Enum.join(missing_roles, ", ")}"
        }
      end
    end)
  end

  defp list_loaded_extensions do
    modules = Application.get_env(:familiar, :extensions, [])

    tools =
      try do
        ToolRegistry.list_tools()
      catch
        :exit, _ -> []
      end

    extensions =
      Enum.map(modules, fn mod ->
        ext_name = mod.name()
        ext_tools = Enum.filter(tools, &(&1.extension == ext_name))

        %{
          name: ext_name,
          tools_count: length(ext_tools),
          tools: Enum.map(ext_tools, & &1.name)
        }
      end)

    {:ok, %{extensions: extensions}}
  end

  defp format_session_message(msg) do
    %{role: msg.role, content: truncate(msg.content || "", 100)}
  end

  defp run_raw_search(query, deps) do
    search_fn = Map.get(deps, :search_fn, &Knowledge.search/1)

    case search_fn.(query) do
      {:ok, results} -> {:ok, %{results: results, query: query}}
      {:error, _} = error -> error
    end
  end

  defp run_compact(flags, deps) do
    candidates_fn =
      Map.get(deps, :compact_candidates_fn, &Management.find_consolidation_candidates/1)

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

  defp run_context_reindex(deps) do
    reindex_fn = Map.get(deps, :reindex_fn, &Knowledge.reindex_embeddings/1)

    last_progress = :counters.new(1, [:atomics])
    start_ms = System.monotonic_time(:millisecond)

    on_progress = fn processed, total ->
      now = System.monotonic_time(:millisecond)
      last_offset = :counters.get(last_progress, 1)

      case throttle_progress(now, start_ms, last_offset, processed, total) do
        {:fire, new_offset} ->
          :counters.put(last_progress, 1, new_offset)
          IO.puts(:stderr, "[familiar] Re-embedding #{processed}/#{total}")

        :suppress ->
          :ok
      end
    end

    case reindex_fn.(on_progress: on_progress) do
      {:ok, %{} = summary} ->
        {:ok, %{reindex: summary}}

      {:error, _} = error ->
        error
    end
  end

  # Decide whether a reindex progress callback should emit a stderr line.
  #
  # Pure helper extracted for testability. Returns `{:fire, new_offset}` when
  # the callback should emit (and the counter should be updated to the new
  # offset-from-start), or `:suppress` when the call should be throttled
  # away. The final callback (where `processed == total`) always fires
  # regardless of timing so the user sees the terminal state.
  #
  # * `now` — current monotonic ms timestamp
  # * `start_ms` — monotonic ms captured when the reindex started
  # * `last_offset` — `:counters` value, i.e. (last_fire_time - start_ms),
  #   or 0 if nothing has fired yet
  # * `processed` / `total` — progress counts
  @doc false
  @spec throttle_progress(integer(), integer(), integer(), non_neg_integer(), non_neg_integer()) ::
          {:fire, integer()} | :suppress
  def throttle_progress(now, start_ms, last_offset, processed, total) do
    last_fire_time = last_offset + start_ms
    elapsed_since_last = now - last_fire_time

    cond do
      processed == total ->
        {:fire, now - start_ms}

      elapsed_since_last >= 500 ->
        {:fire, now - start_ms}

      true ->
        :suppress
    end
  end

  defp run_workflows_resume(flags, deps) do
    latest_fn = Map.get(deps, :latest_resumable_fn, &WorkflowRuns.latest_resumable/1)
    get_fn = Map.get(deps, :get_workflow_run_fn, &WorkflowRuns.get/1)
    resume_fn = Map.get(deps, :resume_workflow_fn, &WorkflowRunner.resume_workflow/2)

    with :ok <- reject_invalid_id(flags),
         {:ok, run} <- find_resumable_run(Map.get(flags, :id), latest_fn, get_fn) do
      # Step count is shown as "step N+" without a total to avoid re-parsing
      # the workflow file here — the runner parses it inside resume_workflow/2
      # anyway, and any parse error surfaces as a real return value.
      IO.puts(
        :stderr,
        "[familiar] Resuming workflow run ##{run.id}: #{run.name} " <>
          "(next step: #{run.current_step_index})"
      )

      maybe_warn_running_row(run)

      case resume_fn.(run.id, familiar_dir: Paths.familiar_dir()) do
        {:ok, result} ->
          {:ok, %{workflow: run.name, run_id: run.id, steps: result.steps}}

        {:error, _} = error ->
          error
      end
    end
  end

  # Resuming a row that is still marked `running` is allowed (the design
  # explicitly supports the "I killed fam, pick back up" use case), but if
  # another instance is genuinely still processing the row, both runners
  # will race to update the same checkpoint. Warn so the user can decide.
  defp maybe_warn_running_row(%{status: "running", id: id}) do
    IO.puts(
      :stderr,
      "[familiar] Warning: run ##{id} is still marked running. If another " <>
        "instance is processing it, both will race the same checkpoint."
    )
  end

  defp maybe_warn_running_row(_), do: :ok

  defp find_resumable_run(nil, latest_fn, _get_fn), do: latest_fn.([])
  defp find_resumable_run(id, _latest_fn, get_fn) when is_integer(id), do: get_fn.(id)

  # OptionParser puts unparseable strict-flag values into the `:_invalid` list.
  # Detect a rejected `--id` (or any other flag here) and refuse rather than
  # silently falling through to `latest_resumable`.
  defp reject_invalid_id(%{_invalid: invalid}) when is_list(invalid) do
    case Enum.find(invalid, fn {name, _} -> name == "--id" end) do
      nil ->
        :ok

      {_, raw} ->
        {:error,
         {:usage_error, %{message: "Invalid --id value: #{inspect(raw)} (expected integer)"}}}
    end
  end

  defp reject_invalid_id(_), do: :ok

  defp run_workflows_list_runs(flags, deps) do
    list_fn = Map.get(deps, :list_workflow_runs_fn, &WorkflowRuns.list/1)

    list_opts =
      []
      |> maybe_put(:status, Map.get(flags, :status))
      |> maybe_put(:scope, Map.get(flags, :scope))
      |> maybe_put(:limit, Map.get(flags, :limit, 20))

    case list_fn.(list_opts) do
      {:ok, runs} ->
        {:ok,
         %{
           runs:
             Enum.map(runs, fn run ->
               %{
                 id: run.id,
                 name: run.name,
                 status: run.status,
                 step: run.current_step_index,
                 updated_at: run.updated_at,
                 last_error: truncate_error(run.last_error)
               }
             end)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp truncate_error(nil), do: nil

  defp truncate_error(msg) when is_binary(msg) do
    if String.length(msg) > 60, do: String.slice(msg, 0, 57) <> "...", else: msg
  end

  defp run_workflow_command(command, workflow_name, args, deps) do
    description = args |> Enum.join(" ") |> String.trim()

    if description == "" do
      {:error, {:usage_error, %{message: "Usage: fam #{command} <description>"}}}
    else
      scope = if command == "plan", do: "planning", else: "agent"
      run_workflow(workflow_name, description, deps, scope)
    end
  end

  defp run_workflow(workflow_name, description, deps, scope) do
    path = Path.join([Paths.familiar_dir(), "workflows", "#{workflow_name}.md"])
    workflow_fn = Map.get(deps, :workflow_fn, &WorkflowRunner.run_workflow/3)

    opts =
      [scope: scope, familiar_dir: Paths.familiar_dir()]
      |> maybe_add_input_fn(deps)

    case workflow_fn.(path, %{task: description}, opts) do
      {:ok, result} ->
        {:ok, %{workflow: workflow_name, steps: result.steps}}

      {:error, {kind, msg}} when is_binary(msg) ->
        {:error, {kind, %{message: msg}}}

      {:error, _} = error ->
        error
    end
  end

  defp resume_planning(session_id, deps) do
    find_fn = Map.get(deps, :find_conversation_fn, &find_planning_conversation/1)

    case find_fn.(session_id) do
      {:ok, conversation} ->
        if conversation.status == "completed" do
          {:error,
           {:conversation_completed,
            %{message: "Planning session ##{conversation.id} is already completed."}}}
        else
          resume_with_context(conversation, deps)
        end

      {:error, _} = error ->
        error
    end
  end

  defp find_planning_conversation(nil) do
    case Familiar.Conversations.latest_active(scope: "planning") do
      {:ok, id} -> Familiar.Conversations.get(id)
      {:error, _} = error -> error
    end
  end

  defp find_planning_conversation(id) when is_integer(id) do
    Familiar.Conversations.get(id)
  end

  defp resume_with_context(conversation, deps) do
    messages_fn = Map.get(deps, :messages_fn, &Familiar.Conversations.messages/1)

    case messages_fn.(conversation.id) do
      {:ok, messages} ->
        # Build context from conversation history for the agent
        context_summary = format_conversation_context(messages)
        description = "Resume planning session ##{conversation.id}\n\n#{context_summary}"
        run_workflow("feature-planning", description, deps, "planning")

      {:error, _} = error ->
        error
    end
  end

  defp format_conversation_context(messages) do
    messages
    |> Enum.filter(&(&1.role in ~w(user assistant)))
    |> Enum.map_join("\n\n", fn msg ->
      role_label = String.capitalize(msg.role)
      "#{role_label}: #{String.slice(msg.content || "", 0, 500)}"
    end)
  end

  # -- Chat Mode --

  defp run_chat(role, deps) do
    chat_fn = Map.get(deps, :chat_fn, &default_chat/3)
    chat_fn.(role, %{}, deps)
  end

  defp resume_chat(session_id, deps) do
    find_fn = Map.get(deps, :find_conversation_fn, &find_chat_conversation/1)

    case find_fn.(session_id) do
      {:ok, %{status: "completed"} = conv} ->
        {:error,
         {:conversation_completed, %{message: "Chat session ##{conv.id} is already completed."}}}

      {:ok, conversation} ->
        load_and_resume_chat(conversation, deps)

      {:error, _} = error ->
        error
    end
  end

  defp load_and_resume_chat(conversation, deps) do
    messages_fn = Map.get(deps, :messages_fn, &Familiar.Conversations.messages/1)

    case messages_fn.(conversation.id) do
      {:ok, messages} ->
        context_summary = format_conversation_context(messages)
        role = extract_chat_role(conversation)
        chat_fn = Map.get(deps, :chat_fn, &default_chat/3)
        chat_fn.(role, %{resume_context: context_summary, session_id: conversation.id}, deps)

      {:error, _} = error ->
        error
    end
  end

  defp find_chat_conversation(nil) do
    case Familiar.Conversations.latest_active(scope: "chat") do
      {:ok, id} -> Familiar.Conversations.get(id)
      {:error, _} = error -> error
    end
  end

  defp find_chat_conversation(id) when is_integer(id) do
    Familiar.Conversations.get(id)
  end

  defp extract_chat_role(%{description: desc}) when is_binary(desc) do
    # Description format from AgentProcess.init: "role_name: task"
    case String.split(desc, ":", parts: 2) do
      [role, _task] -> String.trim(role)
      [_no_colon] -> "user-manager"
    end
  end

  defp extract_chat_role(_), do: "user-manager"

  defp default_chat(role, context, deps) do
    familiar_dir = Paths.familiar_dir()
    input_fn = Map.get(deps, :input_fn)

    task =
      case context do
        %{resume_context: ctx, session_id: sid} ->
          "Resume chat session ##{sid}\n\n#{ctx}"

        _ ->
          "Interactive chat session. Help the user with their software engineering tasks."
      end

    opts =
      [
        familiar_dir: familiar_dir,
        scope: "chat",
        mode: :interactive
      ]
      |> maybe_add_input_fn_value(input_fn)

    case AgentSupervisor.start_agent([role: role, task: task, parent: self()] ++ opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        await_chat(pid, ref, input_fn)

      {:error, reason} ->
        {:error, {:chat_failed, %{message: "Failed to start chat agent: #{inspect(reason)}"}}}
    end
  end

  defp await_chat(pid, ref, input_fn) do
    receive do
      {:agent_needs_input, _agent_id, content} ->
        case get_chat_input(input_fn, content) do
          {:ok, text} ->
            GenServer.cast(pid, {:user_message, text})
            await_chat(pid, ref, input_fn)

          {:halt, _} ->
            Process.demonitor(ref, [:flush])
            stop_chat_agent(pid)
            {:ok, %{chat: "ended", status: "user_exit"}}
        end

      {:agent_done, _agent_id, {:ok, content}} ->
        Process.demonitor(ref, [:flush])
        {:ok, %{chat: "ended", status: "agent_complete", last_response: content}}

      {:agent_done, _agent_id, {:error, reason}} ->
        Process.demonitor(ref, [:flush])
        {:error, {:chat_failed, %{reason: reason}}}

      {:agent_started, _agent_id, _pid} ->
        await_chat(pid, ref, input_fn)

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, {:chat_crashed, %{reason: reason}}}
    after
      # 30 minutes — chat sessions need time for human thinking
      1_800_000 ->
        Process.demonitor(ref, [:flush])

        {:error,
         {:chat_timeout, %{message: "Chat session timed out after 10 minutes of inactivity"}}}
    end
  end

  defp get_chat_input(input_fn, content) when is_function(input_fn) do
    input_fn.("chat", content)
  end

  defp get_chat_input(nil, content) do
    IO.puts("\n#{content}\n")
    text = IO.gets("> ")

    cond do
      !is_binary(text) -> {:halt, :eof}
      String.trim(text) in ~w(exit quit) -> {:halt, :user_exit}
      String.trim(text) == "" -> get_chat_input(nil, "")
      true -> {:ok, String.trim(text)}
    end
  end

  defp stop_chat_agent(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end
  catch
    :exit, _ -> :ok
  end

  defp maybe_add_input_fn_value(opts, nil), do: opts
  defp maybe_add_input_fn_value(opts, input_fn), do: Keyword.put(opts, :input_fn, input_fn)

  defp maybe_add_input_fn(opts, deps) do
    case Map.get(deps, :input_fn) do
      nil -> opts
      input_fn -> Keyword.put(opts, :input_fn, input_fn)
    end
  end

  defp run_restore([], _flags, deps) do
    list_fn = Map.get(deps, :backup_list_fn, &Backup.list/1)
    list_fn.([])
  end

  defp run_restore([timestamp | _], flags, deps) do
    list_fn = Map.get(deps, :backup_list_fn, &Backup.list/1)
    restore_fn = Map.get(deps, :restore_fn, &Backup.restore/2)
    confirm_fn = Map.get(deps, :confirm_fn, &default_confirm/1)
    force = Map.get(flags, :force, false) or Map.get(flags, :json, false)

    with {:ok, backups} <- list_fn.([]),
         {:ok, backup} <- find_backup_by_timestamp(backups, timestamp),
         :ok <- maybe_confirm(backup, confirm_fn, force),
         :ok <- restore_fn.(backup.path, []) do
      {:ok, %{restored: backup.filename, status: "restored"}}
    end
  end

  defp find_backup_by_timestamp(backups, timestamp) do
    case Enum.find(backups, &String.contains?(&1.filename, timestamp)) do
      nil -> {:error, {:not_found, %{timestamp: timestamp}}}
      backup -> {:ok, backup}
    end
  end

  defp maybe_confirm(_backup, _confirm_fn, true), do: :ok

  defp maybe_confirm(backup, confirm_fn, false) do
    prompt = "Restore from #{backup.filename} backup? Current database will be replaced. (y/n): "

    case confirm_fn.(prompt) do
      response when is_binary(response) ->
        if String.starts_with?(String.trim(String.downcase(response)), "y"),
          do: :ok,
          else: {:error, {:cancelled, %{}}}

      _ ->
        {:error, {:cancelled, %{}}}
    end
  end

  defp default_confirm(prompt), do: IO.gets(prompt)

  defp parse_apply_indices(indices_str, candidates) do
    indices =
      indices_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    if Enum.any?(indices, &(&1 == :error)) do
      {:error,
       {:usage_error, %{message: "Invalid indices: #{indices_str}. Use comma-separated numbers."}}}
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

  defp familiar_dir_opts, do: [familiar_dir: Paths.familiar_dir()]

  defp default_deps do
    %{
      ensure_running_fn: &DaemonManager.ensure_running/1,
      health_fn: &HttpClient.health_check/1,
      daemon_status_fn: &DaemonManager.daemon_status/1,
      stop_daemon_fn: &DaemonManager.stop_daemon/1
    }
  end

  @doc false
  def text_formatter(command)

  def text_formatter("roles") do
    fn
      %{roles: roles} ->
        header = "Available roles (#{length(roles)}):\n"

        lines =
          roles
          |> Enum.sort_by(& &1.name)
          |> Enum.map(fn r ->
            "  #{String.pad_trailing(r.name, 18)}— #{r.description} (#{r.skills_count} skills)"
          end)

        header <> Enum.join(lines, "\n")

      %{role: role} ->
        lines = [
          "Role: #{role.name}",
          "  Description: #{role.description}",
          "  Model: #{role.model}",
          "  Lifecycle: #{role.lifecycle}",
          "  Skills: #{Enum.join(role.skills, ", ")}",
          "  Prompt: #{truncate(role.prompt_preview, 200)}"
        ]

        Enum.join(lines, "\n")

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("skills") do
    fn
      %{skills: skills} ->
        header = "Available skills (#{length(skills)}):\n"

        lines =
          skills
          |> Enum.sort_by(& &1.name)
          |> Enum.map(fn s ->
            "  #{String.pad_trailing(s.name, 22)}— #{s.description} (#{s.tools_count} tools)"
          end)

        header <> Enum.join(lines, "\n")

      %{skill: skill} ->
        lines = [
          "Skill: #{skill.name}",
          "  Description: #{skill.description}",
          "  Tools: #{Enum.join(skill.tools, ", ")}",
          "  Instructions: #{truncate(skill.instructions_preview, 200)}"
        ]

        lines =
          if skill.constraints != %{} do
            lines ++ ["  Constraints: #{inspect(skill.constraints)}"]
          else
            lines
          end

        Enum.join(lines, "\n")

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("validate") do
    fn
      %{validation: v} ->
        format_validation_results(v)

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("sessions") do
    fn
      %{sessions: sessions} ->
        format_sessions_list(sessions)

      %{session: s} ->
        msg_lines =
          Enum.map(s.recent_messages, fn m ->
            "    [#{m.role}] #{m.content}"
          end)

        lines =
          [
            "Session ##{s.id}",
            "  Scope: #{s.scope}",
            "  Status: #{s.status}",
            "  Description: #{s.description}",
            "  Created: #{s.created_at}",
            "  Messages: #{s.message_count}",
            ""
          ] ++
            if msg_lines != [] do
              ["  Recent messages:" | msg_lines]
            else
              []
            end

        Enum.join(lines, "\n")

      %{cleaned: count} ->
        "Cleaned up #{count} stale session(s)."

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("workflows") do
    fn
      %{workflows: workflows} ->
        header = "Available workflows (#{length(workflows)}):\n"

        lines =
          workflows
          |> Enum.sort_by(& &1.name)
          |> Enum.map(fn wf ->
            desc = wf.description || "(no description)"
            "  #{String.pad_trailing(wf.name, 26)}— #{desc} (#{wf.step_count} steps)"
          end)

        header <> Enum.join(lines, "\n")

      %{workflow: wf} ->
        format_workflow_detail(wf)

      %{runs: runs} ->
        format_workflow_runs_table(runs)

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("extensions") do
    fn
      %{extensions: extensions} ->
        format_extensions_list(extensions)

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("chat") do
    fn
      %{chat: "ended", status: status, last_response: response} ->
        "Chat session #{status}.\n\n#{response}"

      %{chat: "ended", status: status} ->
        "Chat session #{status}."

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter(cmd) when cmd in ~w(plan do fix) do
    fn
      %{workflow: workflow, steps: steps} ->
        header = "Workflow: #{workflow} (#{length(steps)} steps)\n"

        lines =
          steps
          |> Enum.with_index(1)
          |> Enum.map(fn {step, idx} ->
            output = truncate(step.output || "", 200)
            "  #{idx}. #{step.step} — #{output}"
          end)

        header <> Enum.join(lines, "\n")

      other ->
        inspect(other, pretty: true)
    end
  end

  def text_formatter("health") do
    fn %{status: status, version: version} ->
      "Daemon is #{status} (version #{version})"
    end
  end

  def text_formatter("version") do
    fn %{version: version} -> "fam #{version}" end
  end

  def text_formatter("help") do
    fn %{help: text} -> text end
  end

  def text_formatter("daemon") do
    fn
      %{daemon: status, port: port} -> "Daemon: #{status} on port #{port}"
      %{daemon: status} -> "Daemon: #{status}"
      %{status: status, port: port} -> "Daemon #{status} on port #{port}"
      %{status: status} -> "Daemon #{status}"
      other -> inspect(other, pretty: true)
    end
  end

  def text_formatter("init") do
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

  def text_formatter("search") do
    fn
      %{results: results, query: query, summary: summary} ->
        "#{summary}\n\n---\nRaw results (#{length(results)} found) for \"#{query}\""

      %{results: results, query: query} ->
        format_search_results(results, query)
    end
  end

  def text_formatter("conventions") do
    fn %{conventions: conventions, review_mode: review_mode} ->
      format_conventions_text(conventions, review_mode)
    end
  end

  def text_formatter("config") do
    fn config -> format_config_text(config) end
  end

  def text_formatter("entry") do
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

  def text_formatter("edit") do
    fn %{id: id} -> "Entry ##{id} updated" end
  end

  def text_formatter("delete") do
    fn %{id: id} -> "Entry ##{id} deleted" end
  end

  def text_formatter("status") do
    fn data -> format_health_text(Map.delete(data, :command)) end
  end

  def text_formatter("backup") do
    fn %{path: path, size: size, filename: _} ->
      "Backup created: #{path} (#{format_size(size)})"
    end
  end

  def text_formatter("restore") do
    fn
      %{restored: filename, status: _} ->
        "Restored from #{filename}. Restart daemon with `fam daemon restart`."

      %{} = backups_list ->
        format_backups_list(backups_list)

      backups when is_list(backups) ->
        format_backups_list(backups)
    end
  end

  def text_formatter("context") do
    fn
      %{entry_count: _, signal: _} = health ->
        format_health_text(health)

      %{reindex: summary} ->
        format_reindex_summary(summary)

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

  def text_formatter(_), do: nil

  defp format_reindex_summary(%{processed: processed, failed: failed} = summary) do
    model = Map.get(summary, :model) || "unset"
    errors = Map.get(summary, :errors, [])

    base =
      "Reindexed #{processed} entr#{if processed == 1, do: "y", else: "ies"} " <>
        "(#{failed} failed). Embedding model is now #{model}."

    if errors == [] do
      base
    else
      error_lines =
        errors
        |> Enum.take(10)
        |> Enum.map(fn {id, reason} ->
          # `limit: 3` previously truncated useful tuples like
          # `{:provider_unavailable, %{reason: :timeout, details: ...}}` to
          # `%{...}`. `limit: 50` + a `printable_limit` preserves the full
          # reason while still capping pathological recursive structures.
          "  - entry ##{id}: #{inspect(reason, limit: 50, printable_limit: 500)}"
        end)

      truncated =
        if length(errors) > 10 do
          ["  ... (#{length(errors) - 10} more)"]
        else
          []
        end

      Enum.join([base, "Errors:" | error_lines ++ truncated], "\n")
    end
  end

  defp format_workflow_detail(wf) do
    step_lines =
      wf.steps
      |> Enum.with_index(1)
      |> Enum.map(fn {s, idx} ->
        mode_tag = if s.mode == :interactive, do: " [interactive]", else: ""
        "  #{idx}. #{s.name} (role: #{s.role})#{mode_tag}"
      end)

    lines = [
      "Workflow: #{wf.name}",
      "  Description: #{wf.description || "(none)"}",
      "  Steps:" | step_lines
    ]

    List.flatten(lines) |> Enum.join("\n")
  end

  defp format_workflow_runs_table([]) do
    "No workflow runs found."
  end

  defp format_workflow_runs_table(runs) do
    header_row =
      [
        String.pad_trailing("ID", 6),
        String.pad_trailing("NAME", 24),
        String.pad_trailing("STATUS", 10),
        String.pad_trailing("STEP", 6),
        String.pad_trailing("UPDATED", 20),
        "ERROR"
      ]
      |> Enum.join(" ")

    lines =
      Enum.map(runs, fn r ->
        [
          String.pad_trailing("##{r.id}", 6),
          String.pad_trailing(truncate_str(r.name, 24), 24),
          String.pad_trailing(r.status, 10),
          String.pad_trailing("#{r.step}", 6),
          String.pad_trailing(format_dt(r.updated_at), 20),
          r.last_error || ""
        ]
        |> Enum.join(" ")
      end)

    "Workflow runs (#{length(runs)}):\n" <> header_row <> "\n" <> Enum.join(lines, "\n")
  end

  defp truncate_str(str, max) when is_binary(str) do
    if String.length(str) > max, do: String.slice(str, 0, max - 1) <> "…", else: str
  end

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_dt(_), do: ""

  defp format_extensions_list([]), do: "No extensions loaded."

  defp format_extensions_list(extensions) do
    header = "Loaded extensions (#{length(extensions)}):\n"

    lines =
      Enum.map(extensions, fn ext ->
        tools = Enum.map_join(ext.tools, ", ", &to_string/1)
        "  #{String.pad_trailing(ext.name, 20)}— #{ext.tools_count} tools: #{tools}"
      end)

    header <> Enum.join(lines, "\n")
  end

  defp format_validation_results(v) do
    sections =
      [
        format_validation_section("Roles", v.roles),
        format_validation_section("Skills", v.skills),
        format_validation_section("Workflows", v.workflows)
      ]
      |> Enum.reject(&(&1 == ""))

    s = v.summary
    summary = "\nSummary: #{s.passed} passed, #{s.warnings} warnings, #{s.errors} errors"

    Enum.join(sections, "\n\n") <> summary
  end

  defp format_validation_section(_title, []), do: ""

  defp format_validation_section(title, results) do
    lines =
      Enum.map(results, fn r ->
        status_tag =
          case r.status do
            :pass -> "OK"
            :warn -> "WARN"
            :error -> "FAIL"
          end

        base = "  [#{status_tag}] #{r.name}"
        if Map.has_key?(r, :message), do: "#{base} — #{r.message}", else: base
      end)

    "#{title}:\n" <> Enum.join(lines, "\n")
  end

  defp format_sessions_list([]), do: "No sessions found."

  defp format_sessions_list(sessions) do
    header = "Sessions (#{length(sessions)}):\n"

    lines =
      Enum.map(sessions, fn s ->
        id = String.pad_leading("#{s.id}", 4)
        scope = String.pad_trailing(s.scope, 10)
        status = String.pad_trailing(s.status, 10)
        "  #{id}  #{scope}  #{status}  #{s.description}"
      end)

    header <> Enum.join(lines, "\n")
  end

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

  defp format_health_text(health) do
    signal_icon = signal_indicator(health.signal)

    lines = [
      "Knowledge Store Health: #{signal_icon} #{health.signal}",
      "  Entries: #{health.entry_count}",
      "  Staleness: #{Float.round(health.staleness_ratio * 100, 1)}%",
      "  Last refresh: #{health.last_refresh || "never"}",
      "  Backups: #{health.backup.count} (last: #{health.backup.last || "never"})"
    ]

    type_lines =
      health.types
      |> Enum.sort()
      |> Enum.map(fn {type, count} -> "    #{type}: #{count}" end)

    if type_lines != [] do
      Enum.join(lines ++ ["  Types:"] ++ type_lines, "\n")
    else
      Enum.join(lines, "\n")
    end
  end

  defp signal_indicator(:green), do: "[OK]"
  defp signal_indicator(:amber), do: "[WARN]"
  defp signal_indicator(:red), do: "[CRITICAL]"

  defp format_backups_list(backups) when is_list(backups) do
    case backups do
      [] ->
        "No backups available"

      _ ->
        header = "Available backups (#{length(backups)}):\n"

        lines =
          backups
          |> Enum.with_index(1)
          |> Enum.map(fn {b, idx} ->
            "  #{idx}. #{b.filename} (#{format_size(b.size)})"
          end)

        header <> Enum.join(lines, "\n")
    end
  end

  defp format_backups_list(_), do: "No backups available"

  defp format_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_size(bytes), do: "#{bytes} B"

  defp help_text do
    """
    fam - Familiar CLI

    Usage: fam <command> [options]

    Commands:
      chat               Interactive conversation with full tool access (default)
      chat --role <name> Chat with a specific agent role
      init               Initialize Familiar on this project
      plan <description> Plan a feature (research → draft-spec → review)
      do <description>   Implement a feature (implement → test → review)
      fix <description>  Fix a bug (diagnose → fix → verify)
      roles              List all available agent roles
      roles <name>       Show details for a specific role
      skills             List all available skills
      skills <name>      Show details for a specific skill
      workflows          List all available workflows
      workflows <name>   Show details for a specific workflow
      workflows resume [--id <n>]       Resume an interrupted workflow run
      workflows list-runs [--status s] [--scope s] [--limit n]  List workflow runs
      extensions         List loaded extensions and their tools
      sessions           List conversation sessions
      sessions <id>      Show session details and recent messages
      sessions --scope <s> Filter sessions by scope (chat, planning)
      sessions --cleanup Close stale active sessions
      validate           Validate all roles, skills, and workflows
      validate roles     Validate only roles (skill cross-references)
      validate skills    Validate only skills (tool references)
      validate workflows Validate only workflows (parse + role refs)
      search <query>     Search knowledge store (curated by Librarian)
      search --raw <q>   Search knowledge store directly (no curation)
      entry <id>         Inspect a knowledge entry
      edit <id> <text>   Edit a knowledge entry (re-embeds, tags as user)
      delete <id>        Delete a knowledge entry
      context --refresh [path]  Re-scan project or path
      context --compact  Find and consolidate duplicate entries
      context --health   Show knowledge store health metrics
      context --reindex  Re-embed all knowledge entries with the current model
      backup             Create knowledge store backup
      restore            List available backups
      restore <timestamp> Restore from a specific backup
      status             Show knowledge store health and status
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
