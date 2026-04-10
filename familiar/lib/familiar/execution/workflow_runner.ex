defmodule Familiar.Execution.WorkflowRunner do
  @moduledoc """
  Sequences agents through workflow steps defined in markdown.

  Each workflow run is a separate GenServer. The runner parses a workflow
  definition (YAML frontmatter), spawns `AgentProcess` instances for each
  step, collects results, and accumulates context between steps.

  ## Workflow File Format

      ---
      name: feature-planning
      description: Plan a new feature
      steps:
        - name: analyze
          role: analyst
        - name: research
          role: librarian
          input: [analyze]
      ---

  ## Usage

      {:ok, results} = WorkflowRunner.run_workflow("path/to/workflow.md", %{task: "Build auth"})
  """

  use GenServer

  require Logger

  alias Familiar.Daemon.Paths
  alias Familiar.Execution.AgentSupervisor
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Execution.WorkflowRuns

  # -- Data Structures --

  defmodule Workflow do
    @moduledoc false
    defstruct [:name, :description, steps: []]

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t() | nil,
            steps: [Familiar.Execution.WorkflowRunner.Step.t()]
          }
  end

  defmodule Step do
    @moduledoc false
    defstruct [:name, :role, mode: :autonomous, input: [], output: nil]

    @type t :: %__MODULE__{
            name: String.t(),
            role: String.t(),
            mode: :autonomous | :interactive,
            input: [String.t()],
            output: String.t() | nil
          }
  end

  # ETS table for agent_id → runner_pid mapping
  @registry_table :familiar_workflow_registry
  # 30 minutes — interactive workflows need time for human thinking
  @default_timeout_ms 1_800_000

  # -- Tool Registration --

  @doc """
  Register the `signal_ready` tool with the ToolRegistry.

  Replaces the builtin stub with a real implementation that notifies
  the managing workflow runner.
  """
  def register_signal_ready_tool do
    ToolRegistry.register(
      :signal_ready,
      &signal_ready_tool/2,
      "Signal that the current workflow step is complete",
      "harness"
    )
  end

  @doc false
  def signal_ready_tool(_args, context) do
    agent_id = Map.get(context, :agent_id)

    case find_runner(agent_id) do
      {:ok, runner_pid} ->
        send(runner_pid, {:signal_ready, agent_id})
        {:ok, %{status: "acknowledged"}}

      :error ->
        {:ok, %{status: "no_workflow"}}
    end
  end

  # -- Public API --

  @doc """
  Parse a workflow markdown file into a `%Workflow{}` struct.
  """
  @spec parse(String.t()) :: {:ok, Workflow.t()} | {:error, term()}
  def parse(path) do
    with {:ok, content} <- read_file(path),
         {:ok, yaml} <- split_frontmatter(content) do
      build_workflow(yaml)
    end
  end

  @doc """
  List all valid workflows in the workflows directory.

  Parses each `.md` file in `.familiar/workflows/`, collects successes,
  and logs warnings for invalid files.
  """
  @spec list_workflows(keyword()) :: {:ok, [Workflow.t()]}
  def list_workflows(opts \\ []) do
    familiar_dir = Keyword.get_lazy(opts, :familiar_dir, &Paths.familiar_dir/0)
    workflows_dir = Path.join(familiar_dir, "workflows")

    case File.ls(workflows_dir) do
      {:ok, files} ->
        workflows =
          files
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.sort()
          |> Enum.reduce([], &try_parse_workflow(Path.join(workflows_dir, &1), &2))
          |> Enum.reverse()

        {:ok, workflows}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  defp try_parse_workflow(path, acc) do
    case parse(path) do
      {:ok, wf} ->
        [wf | acc]

      {:error, reason} ->
        Logger.warning(
          "[WorkflowRunner] Skipping invalid workflow #{Path.basename(path)}: #{inspect(reason)}"
        )

        acc
    end
  end

  @doc """
  Start a workflow runner GenServer.

  ## Options

    * `:workflow` — parsed `%Workflow{}` (required)
    * `:context` — initial context map (optional, default `%{}`)
    * `:caller` — pid to notify on completion (optional, default `self()`)
    * `:familiar_dir` — path to `.familiar/` directory (optional)
    * `:supervisor` — DynamicSupervisor for agents (optional)
    * `:scope` — conversation scope for agents (optional, default `"agent"`)
    * `:timeout_ms` — max time to wait for workflow completion (optional, default 5 min)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Begin workflow execution."
  def run(pid) do
    GenServer.cast(pid, :run)
  end

  @doc "Get current workflow status."
  @spec status(pid()) :: map()
  def status(pid) do
    GenServer.call(pid, :status)
  end

  @doc """
  Parse and run a workflow in one call. Blocks until completion.

  Returns `{:ok, %{steps: [%{step: name, output: result}]}}` or `{:error, reason}`.
  """
  @spec run_workflow(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_workflow(path, context \\ %{}, opts \\ []) do
    with {:ok, workflow} <- parse(path) do
      # Stash the absolute path so resume_workflow/2 can reparse later.
      run_workflow_parsed(workflow, context, Keyword.put(opts, :workflow_path, Path.expand(path)))
    end
  end

  @doc """
  Run a pre-parsed workflow. Blocks until completion.
  """
  @spec run_workflow_parsed(Workflow.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_workflow_parsed(%Workflow{} = workflow, context \\ %{}, opts \\ []) do
    caller = self()
    runner_opts = Keyword.merge(opts, workflow: workflow, context: context, caller: caller)

    case start_link(runner_opts) do
      {:ok, pid} ->
        run(pid)
        timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
        input_fn = Keyword.get(opts, :input_fn)
        await_completion(pid, timeout, input_fn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume a previously persisted workflow run from its last checkpoint.

  Loads the row via `Familiar.Execution.WorkflowRuns.get/1`, re-parses the
  workflow markdown from the stored `workflow_path`, and starts a new
  `WorkflowRunner` GenServer preloaded with `current_step_index` and
  `step_results`. The new runner reuses the same `run_id` so subsequent
  checkpoints update the same row.

  Returns:
    * `{:ok, %{steps: [...]}}` on completion
    * `{:error, {:workflow_run_not_found, _}}`
    * `{:error, {:workflow_already_completed, %{id: id}}}`
    * `{:error, {:workflow_path_missing, %{id: id}}}`
    * any parse error from the stored workflow path
  """
  @spec resume_workflow(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def resume_workflow(run_id, opts \\ []) when is_integer(run_id) do
    with {:ok, run} <- WorkflowRuns.get(run_id),
         :ok <- check_resumable(run),
         {:ok, workflow_path} <- require_workflow_path(run),
         {:ok, workflow} <- parse(workflow_path),
         :ok <- ensure_incomplete(run, workflow) do
      context = run.initial_context || %{}

      resume_opts =
        opts
        |> Keyword.merge(
          workflow: workflow,
          context: atomize_context(context),
          caller: self(),
          run_id: run.id,
          resume_from: %{
            current_step_index: run.current_step_index,
            # DB stores step_results chronologically; memory wants newest-first.
            step_results:
              run.step_results |> List.wrap() |> atomize_step_results() |> Enum.reverse()
          }
        )

      case start_link(resume_opts) do
        {:ok, pid} ->
          run(pid)
          timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
          input_fn = Keyword.get(opts, :input_fn)
          await_completion(pid, timeout, input_fn)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp check_resumable(%{status: "completed", id: id}),
    do: {:error, {:workflow_already_completed, %{id: id}}}

  defp check_resumable(_run), do: :ok

  defp require_workflow_path(%{workflow_path: nil, id: id}),
    do: {:error, {:workflow_path_missing, %{id: id}}}

  defp require_workflow_path(%{workflow_path: path}), do: {:ok, path}

  # Edge case: row was already advanced past the final step but never marked
  # completed (e.g., the GenServer crashed between checkpoint and complete).
  # Treat it as done and finalize the row. If the finalize itself fails, the
  # row is permanently stuck — surface a distinct error so the user knows
  # they need to intervene rather than seeing the same `already_completed`
  # error on every subsequent resume attempt.
  defp ensure_incomplete(run, workflow) do
    if run.current_step_index >= length(workflow.steps) do
      case WorkflowRuns.complete(run.id) do
        {:ok, _} ->
          {:error, {:workflow_already_completed, %{id: run.id}}}

        {:error, reason} ->
          {:error, {:workflow_finalize_failed, %{id: run.id, reason: reason}}}
      end
    else
      :ok
    end
  end

  # Ecto JSON load gives us string keys; convert top-level atoms agents
  # expect (:task) so existing workflows keep working without change.
  defp atomize_context(ctx) when is_map(ctx) do
    Map.new(ctx, fn {k, v} -> {atomize_key(k), v} end)
  end

  defp atomize_context(_), do: %{}

  defp atomize_key("task"), do: :task
  defp atomize_key(k) when is_atom(k), do: k
  defp atomize_key(k), do: k

  defp atomize_step_results(results) do
    Enum.map(results, fn
      %{"step" => s, "output" => o} -> %{step: s, output: o}
      %{step: _, output: _} = m -> m
      other -> other
    end)
  end

  @doc """
  Find the workflow runner managing a given agent.

  Used by the `signal_ready` tool to send completion signals.
  """
  @spec find_runner(String.t()) :: {:ok, pid()} | :error
  def find_runner(agent_id) do
    ensure_registry()

    case :ets.lookup(@registry_table, agent_id) do
      [{^agent_id, pid}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: :error

      [] ->
        :error
    end
  rescue
    ArgumentError -> :error
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    workflow = Keyword.fetch!(opts, :workflow)
    context = Keyword.get(opts, :context, %{})
    caller = Keyword.get(opts, :caller)
    scope = Keyword.get(opts, :scope, "agent")
    workflow_path = Keyword.get(opts, :workflow_path)
    run_id = Keyword.get(opts, :run_id)
    resume_from = Keyword.get(opts, :resume_from)
    extra_opts = Keyword.take(opts, [:familiar_dir, :supervisor])

    {current_step_index, step_results} =
      case resume_from do
        %{current_step_index: idx, step_results: results}
        when is_integer(idx) and is_list(results) ->
          {idx, results}

        _ ->
          {0, []}
      end

    state = %{
      workflow: workflow,
      workflow_path: workflow_path,
      initial_context: context,
      caller: caller,
      scope: scope,
      status: :pending,
      current_step_index: current_step_index,
      step_results: step_results,
      agent_pid: nil,
      agent_id: nil,
      monitor_ref: nil,
      step_handled: false,
      extra_opts: extra_opts,
      run_id: run_id
    }

    if is_nil(run_id) do
      # Fresh run — defer the DB insert to handle_continue so a slow repo
      # can't block the caller's start_link timeout window.
      {:ok, state, {:continue, :persist_start}}
    else
      # Resume path — row already exists, nothing to persist yet.
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:persist_start, state) do
    opts = [
      workflow_path: state.workflow_path,
      scope: state.scope,
      initial_context: sanitize_context(state.initial_context)
    ]

    case safe_call(fn -> WorkflowRuns.create(state.workflow.name, opts) end) do
      {:ok, run} ->
        {:noreply, %{state | run_id: run.id}}

      {:error, reason} ->
        Logger.warning(
          "[WorkflowRunner] Failed to persist workflow start for '#{state.workflow.name}': " <>
            inspect(reason)
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:run, %{status: :pending} = state) do
    Logger.info("[WorkflowRunner] Starting workflow: #{state.workflow.name}")
    state = %{state | status: :running}
    {:noreply, start_next_step(state)}
  end

  def handle_cast(:run, state), do: {:noreply, state}

  @impl true
  def handle_call(:status, _from, state) do
    summary = %{
      workflow: state.workflow.name,
      status: state.status,
      current_step: current_step_name(state),
      completed_steps: length(state.step_results),
      total_steps: length(state.workflow.steps)
    }

    {:reply, summary, state}
  end

  @impl true
  # Agent reports its ID at startup — register for signal_ready lookup
  def handle_info({:agent_started, agent_id, _pid}, %{status: :running} = state) do
    register_agent(agent_id, self())
    {:noreply, %{state | agent_id: agent_id}}
  end

  # Agent completed — only handle once per step (guards against signal_ready + agent_done race)
  def handle_info(
        {:agent_done, _agent_id, result},
        %{status: :running, step_handled: false} = state
      ) do
    cleanup_agent_registration(state.agent_id)
    if state.monitor_ref, do: Process.demonitor(state.monitor_ref, [:flush])

    state = %{state | step_handled: true}

    case result do
      {:ok, content} -> handle_step_success(state, content)
      {:error, reason} -> handle_step_failure(state, reason)
    end
  end

  # signal_ready — treat as step completion (only if not already handled)
  def handle_info({:signal_ready, _agent_id}, %{status: :running, step_handled: false} = state) do
    cleanup_agent_registration(state.agent_id)
    if state.monitor_ref, do: Process.demonitor(state.monitor_ref, [:flush])

    # Stop the agent to prevent further LLM calls after signal_ready
    stop_agent(state.agent_pid)

    state = %{state | step_handled: true}
    handle_step_success(state, "Step completed via signal_ready")
  end

  # Interactive agent needs user input — forward to caller
  def handle_info(
        {:agent_needs_input, _agent_id, content},
        %{status: :running, step_handled: false} = state
      ) do
    step = Enum.at(state.workflow.steps, state.current_step_index)
    Logger.info("[WorkflowRunner] Step '#{step.name}' waiting for user input")
    notify_caller(state, {:workflow_needs_input, self(), step.name, content})
    {:noreply, state}
  end

  # User input received — forward to the running agent
  def handle_info({:user_input, text}, %{status: :running, agent_pid: pid} = state)
      when is_pid(pid) do
    GenServer.cast(pid, {:user_message, text})
    {:noreply, state}
  end

  # Agent crashed — only if step not already handled
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{monitor_ref: ref, step_handled: false} = state
      ) do
    cleanup_agent_registration(state.agent_id)
    state = %{state | step_handled: true}
    handle_step_failure(state, {:agent_crashed, reason})
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_agent_registration(state.agent_id)
    :ok
  end

  # -- Private: Step Execution --

  defp start_next_step(%{current_step_index: idx, workflow: workflow} = state) do
    if idx >= length(workflow.steps) do
      complete_workflow(state)
    else
      step = Enum.at(workflow.steps, idx)
      task_description = build_task_description(step, state)

      agent_opts =
        [
          role: step.role,
          task: task_description,
          parent: self(),
          mode: step.mode,
          scope: state.scope
        ] ++ state.extra_opts

      case AgentSupervisor.start_agent(agent_opts) do
        {:ok, pid} ->
          ref = Process.monitor(pid)

          Logger.info("[WorkflowRunner] Started step '#{step.name}' (role: #{step.role})")

          %{state | agent_pid: pid, agent_id: nil, monitor_ref: ref, step_handled: false}

        {:error, reason} ->
          Logger.error("[WorkflowRunner] Failed to start step '#{step.name}': #{inspect(reason)}")
          fail_workflow(state, {:start_failed, %{step: step.name, reason: reason}})
      end
    end
  end

  defp handle_step_success(state, content) do
    step = Enum.at(state.workflow.steps, state.current_step_index)

    Logger.info("[WorkflowRunner] Step '#{step.name}' completed successfully")

    step_result = %{step: step.name, output: content}
    new_results = [step_result | state.step_results]
    new_index = state.current_step_index + 1

    persist_checkpoint(state, new_index, new_results)

    state = %{
      state
      | step_results: new_results,
        current_step_index: new_index,
        agent_pid: nil,
        agent_id: nil,
        monitor_ref: nil,
        step_handled: false
    }

    {:noreply, start_next_step(state)}
  end

  defp handle_step_failure(state, reason) do
    step = Enum.at(state.workflow.steps, state.current_step_index)
    Logger.error("[WorkflowRunner] Step '#{step.name}' failed: #{inspect(reason)}")
    state = fail_workflow(state, {:step_failed, %{step: step.name, reason: reason}})
    {:noreply, state}
  end

  defp complete_workflow(state) do
    Logger.info("[WorkflowRunner] Workflow '#{state.workflow.name}' completed successfully")

    persist_complete(state)

    state = %{state | status: :completed}
    result = {:ok, %{steps: Enum.reverse(state.step_results)}}
    notify_caller(state, {:workflow_done, self(), result})
    state
  end

  defp fail_workflow(state, reason) do
    persist_fail(state, reason)

    state = %{state | status: :failed}
    notify_caller(state, {:workflow_done, self(), {:error, reason}})
    state
  end

  # -- Private: Persistence (fail-soft) --

  defp persist_checkpoint(%{run_id: nil}, _index, _results), do: :ok

  defp persist_checkpoint(%{run_id: id, workflow: workflow}, index, results)
       when is_integer(id) do
    # step_results live newest-first in memory; persist chronologically so
    # the row is human-readable and `fam workflows list-runs` surfaces steps
    # in execution order.
    chronological = Enum.reverse(results)

    case safe_call(fn -> WorkflowRuns.checkpoint(id, index, chronological) end) do
      {:ok, _run} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[WorkflowRunner] Failed to persist checkpoint for '#{workflow.name}' " <>
            "step #{index}: #{inspect(reason)}"
        )
    end
  end

  defp persist_complete(%{run_id: nil}), do: :ok

  defp persist_complete(%{run_id: id, workflow: workflow}) when is_integer(id) do
    case safe_call(fn -> WorkflowRuns.complete(id) end) do
      {:ok, _run} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[WorkflowRunner] Failed to mark '#{workflow.name}' completed: #{inspect(reason)}"
        )
    end
  end

  defp persist_fail(%{run_id: nil}, _reason), do: :ok

  defp persist_fail(%{run_id: id, workflow: workflow}, reason) when is_integer(id) do
    case safe_call(fn -> WorkflowRuns.fail(id, reason) end) do
      {:ok, _run} ->
        :ok

      {:error, write_error} ->
        Logger.warning(
          "[WorkflowRunner] Failed to mark '#{workflow.name}' failed: #{inspect(write_error)}"
        )
    end
  end

  # Wraps a persistence call so DB errors or repo-not-running crashes
  # never propagate out of the runner GenServer.
  defp safe_call(fun) do
    fun.()
  rescue
    e -> {:error, {:persistence_exception, e}}
  catch
    :exit, reason -> {:error, {:persistence_exit, reason}}
  end

  # Ensure the initial context can be JSON-encoded. Any PIDs/refs/tuples
  # sneak in via integration tests and planning sessions; strip or stringify
  # them rather than crashing the GenServer.
  #
  # Detects key collisions caused by stringification — e.g., a context with
  # both `:foo` (atom) and `"foo"` (binary) keys would otherwise collapse
  # silently into a single entry, dropping one of the values. When a
  # collision is detected we keep the first value and log a warning so the
  # data loss isn't invisible.
  defp sanitize_context(ctx) when is_map(ctx) do
    Enum.reduce(ctx, %{}, fn {k, v}, acc ->
      key = to_json_key(k)
      value = json_safe(v)

      if Map.has_key?(acc, key) do
        Logger.warning(
          "[WorkflowRunner] sanitize_context dropped a value: key #{inspect(k)} " <>
            "stringifies to #{inspect(key)} which already exists in the sanitized map"
        )

        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp sanitize_context(_), do: %{}

  defp to_json_key(k) when is_atom(k), do: Atom.to_string(k)
  defp to_json_key(k) when is_binary(k), do: k
  defp to_json_key(k), do: inspect(k)

  defp json_safe(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp json_safe(v) when is_atom(v), do: Atom.to_string(v)
  defp json_safe(v) when is_list(v), do: Enum.map(v, &json_safe/1)
  defp json_safe(v) when is_map(v), do: sanitize_context(v)
  defp json_safe(v), do: inspect(v)

  defp notify_caller(%{caller: nil}, _msg), do: :ok
  defp notify_caller(%{caller: pid}, msg), do: send(pid, msg)

  # -- Private: Context Building --

  defp build_task_description(step, state) do
    base_task = Map.get(state.initial_context, :task) || ""
    base_task = if is_binary(base_task), do: base_task, else: ""
    previous = format_previous_steps(step, state.step_results)

    parts =
      ["[Workflow: #{state.workflow.name} — Step: #{step.name}]"]
      |> maybe_add(previous, previous != "")
      |> maybe_add(base_task, base_task != "")

    Enum.join(parts, "\n\n")
  end

  defp format_previous_steps(_step, []), do: ""

  defp format_previous_steps(step, results) do
    # step_results stored newest-first — reverse for chronological context
    chronological = Enum.reverse(results)

    relevant =
      if step.input == [] do
        chronological
      else
        Enum.filter(chronological, &(&1.step in step.input))
      end

    if relevant == [] do
      ""
    else
      entries =
        Enum.map_join(relevant, "\n", fn r -> "- #{r.step}: #{truncate(r.output, 500)}" end)

      "Previous step results:\n#{entries}"
    end
  end

  defp truncate(nil, _max), do: "(no output)"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) <= max, do: text, else: String.slice(text, 0, max) <> "..."
  end

  defp truncate(_text, _max), do: "(non-text output)"

  defp maybe_add(parts, _text, false), do: parts
  defp maybe_add(parts, text, true), do: parts ++ [text]

  # -- Private: Agent Registration --

  defp ensure_registry do
    :ets.new(@registry_table, [:set, :named_table, :public])
  catch
    :error, :badarg -> :ok
  end

  defp register_agent(agent_id, runner_pid) do
    ensure_registry()
    :ets.insert(@registry_table, {agent_id, runner_pid})
  end

  defp stop_agent(nil), do: :ok

  defp stop_agent(pid) do
    if Process.alive?(pid) do
      # Use Task to avoid blocking the GenServer if the agent is slow to stop
      Task.start(fn -> GenServer.stop(pid, :normal, 5_000) end)
    end
  catch
    :exit, _ -> :ok
  end

  defp cleanup_agent_registration(nil), do: :ok

  defp cleanup_agent_registration(agent_id) do
    if :ets.whereis(@registry_table) != :undefined do
      :ets.delete(@registry_table, agent_id)
    end
  rescue
    ArgumentError -> :ok
  end

  # -- Private: Parsing --

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end

  defp split_frontmatter(content) do
    case Regex.split(~r/^---\s*$/m, content, parts: 3) do
      [_, yaml, _body] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
          {:ok, _} -> {:error, {:malformed_yaml, "frontmatter must be a YAML mapping"}}
          {:error, _} -> {:error, {:malformed_yaml, "invalid YAML syntax"}}
        end

      _ ->
        {:error, {:malformed_yaml, "missing YAML frontmatter (expected --- delimiters)"}}
    end
  end

  defp build_workflow(yaml) do
    name = yaml["name"]
    description = yaml["description"]
    raw_steps = yaml["steps"]

    cond do
      is_nil(name) ->
        {:error, {:invalid_workflow, "missing required field: name"}}

      !is_list(raw_steps) or raw_steps == [] ->
        {:error, {:invalid_workflow, "missing or empty steps list"}}

      true ->
        with {:ok, steps} <- build_steps(raw_steps),
             :ok <- validate_step_inputs(steps) do
          {:ok, %Workflow{name: name, description: description, steps: steps}}
        end
    end
  end

  defp build_steps(raw_steps) do
    steps = Enum.map(raw_steps, &build_step/1)

    case Enum.find(steps, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(steps, fn {:ok, step} -> step end)}
      error -> error
    end
  end

  defp build_step(raw) do
    name = raw["name"]
    role = raw["role"]

    if is_nil(name) or is_nil(role) do
      {:error, {:invalid_step, "step missing required field: name or role"}}
    else
      mode = if raw["mode"] == "interactive", do: :interactive, else: :autonomous

      input =
        case raw["input"] do
          list when is_list(list) -> Enum.map(list, &to_string/1)
          _ -> []
        end

      {:ok, %Step{name: name, role: role, mode: mode, input: input, output: raw["output"]}}
    end
  end

  defp validate_step_inputs(steps) do
    # Build set of prior step names at each position (no self or forward refs)
    {_, invalid} =
      Enum.reduce(steps, {MapSet.new(), []}, fn step, {prior_names, bad} ->
        bad_refs = Enum.reject(step.input, &(&1 in prior_names))
        {MapSet.put(prior_names, step.name), bad ++ bad_refs}
      end)

    case invalid do
      [] -> :ok
      refs -> {:error, {:invalid_step_input, "unknown step references: #{Enum.join(refs, ", ")}"}}
    end
  end

  defp current_step_name(%{current_step_index: idx, workflow: workflow}) do
    case Enum.at(workflow.steps, idx) do
      nil -> nil
      step -> step.name
    end
  end

  defp await_completion(pid, timeout, input_fn) do
    ref = Process.monitor(pid)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(pid, ref, deadline, input_fn)
  end

  defp do_await(pid, ref, deadline, input_fn) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Process.demonitor(ref, [:flush])
      {:error, {:workflow_timeout, :deadline_exceeded}}
    else
      receive do
        {:workflow_done, ^pid, result} ->
          Process.demonitor(ref, [:flush])
          result

        {:workflow_needs_input, ^pid, step_name, content} ->
          handle_interactive_input(pid, ref, deadline, input_fn, step_name, content)

        {:DOWN, ^ref, :process, ^pid, reason} ->
          {:error, {:runner_crashed, reason}}
      after
        remaining ->
          Process.demonitor(ref, [:flush])
          {:error, {:workflow_timeout, :deadline_exceeded}}
      end
    end
  end

  defp handle_interactive_input(pid, ref, deadline, input_fn, step_name, content)
       when is_function(input_fn) do
    case input_fn.(step_name, content) do
      {:ok, text} ->
        send(pid, {:user_input, text})
        do_await(pid, ref, deadline, input_fn)

      {:halt, _reason} ->
        cleanup_on_halt(pid, ref)
        {:error, {:interactive_halted, %{step: step_name}}}
    end
  end

  defp handle_interactive_input(pid, ref, deadline, nil, step_name, content) do
    # No input_fn provided — use IO.gets as default
    IO.puts(content)
    text = IO.gets("> ")

    if is_binary(text) do
      send(pid, {:user_input, String.trim(text)})
      do_await(pid, ref, deadline, nil)
    else
      cleanup_on_halt(pid, ref)
      {:error, {:interactive_halted, %{step: step_name}}}
    end
  end

  defp cleanup_on_halt(runner_pid, ref) do
    Process.demonitor(ref, [:flush])
    # Stop the runner GenServer — its terminate/2 will clean up agent registration
    Task.start(fn -> GenServer.stop(runner_pid, :normal, 5_000) end)
  catch
    :exit, _ -> :ok
  end
end
