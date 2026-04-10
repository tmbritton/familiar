defmodule Familiar.Execution.Tools do
  @moduledoc """
  Builtin tool implementations for the agent harness.

  Each function follows the tool contract: `fn(args, context) -> {:ok, result} | {:error, reason}`.
  File and shell operations delegate through behaviour ports (hexagonal architecture)
  so tests can use mocks. Safety enforcement is handled by the hooks pipeline
  before these functions execute — tools do NOT re-validate paths or commands.
  """

  alias Familiar.Activity
  alias Familiar.Daemon.Paths
  alias Familiar.Execution.AgentProcess
  alias Familiar.Execution.AgentSupervisor
  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Files

  # -- File Tools --

  @doc false
  def read_file(args, _context) do
    with {:ok, path} <- require_arg(args, :path) do
      case file_system().read(project_path(path)) do
        {:ok, content} -> {:ok, %{content: content}}
        {:error, _} = error -> error
      end
    end
  end

  @doc false
  def write_file(args, context) do
    with {:ok, path} <- require_arg(args, :path) do
      content = get_arg(args, :content) || ""
      do_write_file(project_path(path), content, Map.get(context, :task_id))
    end
  end

  defp do_write_file(path, content, nil) do
    case file_system().write(path, content) do
      :ok -> {:ok, %{path: path}}
      {:error, _} = error -> error
    end
  end

  defp do_write_file(path, content, task_id) do
    case Files.write(path, content, task_id) do
      {:ok, _transaction} -> {:ok, %{path: path}}
      {:error, {:conflict, _}} -> {:ok, %{path: path <> ".fam-pending", conflict: true}}
      {:error, _} = error -> error
    end
  end

  @doc false
  def delete_file(args, context) do
    with {:ok, path} <- require_arg(args, :path) do
      do_delete_file(project_path(path), Map.get(context, :task_id))
    end
  end

  defp do_delete_file(path, nil) do
    case file_system().delete(path) do
      :ok -> {:ok, %{path: path}}
      {:error, _} = error -> error
    end
  end

  defp do_delete_file(path, task_id) do
    case Files.delete(path, task_id) do
      {:ok, _transaction} -> {:ok, %{path: path}}
      {:error, {:conflict, _}} -> {:error, {:conflict, %{path: path}}}
      {:error, _} = error -> error
    end
  end

  @doc false
  def list_files(args, _context) do
    path = get_arg(args, :path) || "."

    case file_system().ls(project_path(path)) do
      {:ok, files} -> {:ok, %{files: files}}
      {:error, _} = error -> error
    end
  end

  @doc false
  def search_files(args, _context) do
    path = project_path(get_arg(args, :path) || ".")

    with {:ok, pattern} <- require_arg(args, :pattern) do
      if pattern == "" do
        {:error, {:invalid_args, %{reason: "pattern must not be empty"}}}
      else
        matches = search_recursive(path, pattern)
        {:ok, %{matches: matches}}
      end
    end
  end

  # -- Shell Tool --

  @doc false
  def run_command(args, _context) do
    with {:ok, command} <- require_arg(args, :command),
         {executable, cmd_args} <- parse_command(command),
         :ok <- validate_executable(executable) do
      cmd_opts = project_cmd_opts()

      case shell().cmd(executable, cmd_args, cmd_opts) do
        {:ok, result} -> {:ok, result}
        {:error, _} = error -> error
      end
    end
  end

  defp validate_executable(""),
    do: {:error, {:invalid_args, %{reason: "command must not be empty"}}}

  defp validate_executable(_), do: :ok

  # -- Agent Tools --

  @doc false
  def spawn_agent(args, _context) do
    with {:ok, role} <- require_arg(args, :role),
         {:ok, task} <- require_arg(args, :task) do
      opts = [role: role, task: task]

      case AgentSupervisor.start_agent(opts) do
        {:ok, pid} ->
          agent_id = get_agent_id(pid)
          {:ok, %{agent_id: agent_id}}

        {:error, reason} ->
          {:error, {:spawn_failed, %{role: role, reason: reason}}}
      end
    end
  end

  @max_workflow_depth 5

  @doc false
  def run_workflow(args, context) do
    with {:ok, path} <- require_arg(args, :path),
         {:ok, task} <- require_arg(args, :task),
         :ok <- check_workflow_depth(context),
         {:ok, expanded} <- resolve_workflow_path(path) do
      depth = Map.get(context, :workflow_depth, 0)
      opts = [timeout_ms: 300_000, workflow_depth: depth + 1]

      expanded
      |> WorkflowRunner.run_workflow(%{task: task}, opts)
      |> format_workflow_result(expanded)
    end
  end

  defp check_workflow_depth(context) do
    depth = Map.get(context, :workflow_depth, 0)

    if depth >= @max_workflow_depth do
      {:error, {:workflow_depth_exceeded, %{max: @max_workflow_depth, depth: depth}}}
    else
      :ok
    end
  end

  defp resolve_workflow_path(path) do
    project_dir = Paths.project_dir()
    expanded = Path.expand(path, project_dir)

    cond do
      not String.starts_with?(expanded, project_dir <> "/") ->
        {:error, {:path_outside_project, %{path: path}}}

      not String.ends_with?(expanded, ".md") ->
        {:error, {:invalid_workflow_path, %{path: path, reason: "must be a .md file"}}}

      true ->
        {:ok, expanded}
    end
  end

  defp format_workflow_result({:ok, results}, _path) do
    summary =
      Enum.map_join(results.steps, "\n", fn s -> "- #{s.step}: #{truncate_output(s.output)}" end)

    {:ok, %{status: "completed", steps: length(results.steps), summary: summary}}
  end

  defp format_workflow_result({:error, reason}, path) do
    {:error, {:workflow_failed, %{path: path, reason: reason}}}
  end

  defp truncate_output(nil), do: "(no output)"

  defp truncate_output(text) when is_binary(text) do
    if String.length(text) > 500, do: String.slice(text, 0, 500) <> "...", else: text
  end

  defp truncate_output(_), do: "(non-text output)"

  @doc false
  def monitor_agents(_args, _context) do
    agents =
      AgentProcess.list_agents()
      |> Enum.map(fn {pid, agent_id} ->
        %{pid: inspect(pid), agent_id: agent_id}
      end)

    {:ok, %{agents: agents}}
  end

  # -- Status Tool --

  @doc false
  def broadcast_status(args, context) do
    message = get_arg(args, :message) || ""
    scope_id = Map.get(context, :agent_id, "system")

    event = %Activity.Event{
      type: :status_update,
      detail: message,
      timestamp: DateTime.utc_now()
    }

    Activity.broadcast(scope_id, event)
    {:ok, %{status: "broadcast"}}
  end

  # -- Signal Ready Stub (overridden by WorkflowRunner at startup) --

  @doc false
  def signal_ready_stub(_args, _context) do
    {:ok, %{status: "no_workflow"}}
  end

  # -- Helpers --

  defp get_arg(args, key) do
    Map.get(args, key, Map.get(args, to_string(key)))
  end

  defp require_arg(args, key) do
    case get_arg(args, key) do
      nil -> {:error, {:missing_arg, %{arg: key}}}
      value when is_binary(value) -> {:ok, value}
      value -> {:ok, to_string(value)}
    end
  end

  defp file_system do
    Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
  end

  defp shell do
    Application.get_env(:familiar, Familiar.System.Shell, Familiar.System.RealShell)
  end

  defp project_cmd_opts do
    case System.get_env("FAMILIAR_PROJECT_DIR") do
      nil -> []
      dir -> [cd: dir]
    end
  end

  # Resolve a path relative to the project directory (not the Familiar source dir)
  # Only resolves when FAMILIAR_PROJECT_DIR is set (CLI mode via bin/fam)
  defp project_path(path) do
    case System.get_env("FAMILIAR_PROJECT_DIR") do
      nil ->
        path

      project_dir ->
        if Path.type(path) == :absolute do
          path
        else
          Path.join(project_dir, path)
        end
    end
  end

  defp parse_command(command) when is_binary(command) do
    case tokenize_command(command) do
      [executable | args] -> {executable, args}
      [] -> {"", []}
    end
  end

  # Split on whitespace, respecting single and double quotes (with escapes)
  defp tokenize_command(cmd) do
    ~r/(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|(\S+))/
    |> Regex.scan(cmd)
    |> Enum.map(fn
      [_, quoted, "", ""] -> unescape(quoted)
      [_, "", quoted, ""] -> unescape(quoted)
      [_, "", "", bare] -> bare
      [match | _] -> match
    end)
  end

  defp unescape(str), do: String.replace(str, ~r/\\(.)/, "\\1")

  defp get_agent_id(pid) do
    GenServer.call(pid, :agent_id, 5_000)
  rescue
    _ -> "agent_#{inspect(pid)}"
  end

  # -- Recursive File Search --

  @max_search_depth 10

  defp search_recursive(path, pattern, depth \\ 0)

  defp search_recursive(_path, _pattern, depth) when depth > @max_search_depth, do: []

  defp search_recursive(path, pattern, depth) do
    case file_system().ls(path) do
      {:ok, entries} ->
        Enum.flat_map(entries, &search_entry(Path.join(path, &1), pattern, depth))

      {:error, _} ->
        []
    end
  end

  defp search_entry(full_path, pattern, depth) do
    case file_system().read(full_path) do
      {:ok, content} ->
        search_in_content(full_path, content, pattern)

      {:error, _} ->
        # Could be a directory or unreadable file — try recursing
        search_recursive(full_path, pattern, depth + 1)
    end
  end

  defp search_in_content(path, content, pattern) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _num} -> String.contains?(line, pattern) end)
    |> Enum.map(fn {line, num} ->
      %{path: path, line: num, content: String.trim(line)}
    end)
  end
end
