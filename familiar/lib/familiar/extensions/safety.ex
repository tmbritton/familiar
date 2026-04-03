defmodule Familiar.Extensions.Safety do
  @moduledoc """
  Default safety extension that vetoes dangerous tool calls.

  Operates entirely via the `before_tool_call` alter hook at priority 1
  (runs first in the pipeline). Enforces:

    * **Path sandboxing** — all file operations must target paths within
      the project directory
    * **`.git/` protection** — write/delete operations on `.git/` paths
      are blocked (reads allowed)
    * **Shell command allow-list** — only approved commands may execute
    * **Delete restrictions** — directory deletion is blocked

  ## Configuration

    * `:project_dir` — sandbox root directory (default: `File.cwd!/0`)
    * `:allowed_commands` — list of permitted command prefixes
      (default: `["mix test", "mix format", "mix credo", "mix compile", "mix deps.get"]`)
  """

  @behaviour Familiar.Extension

  @default_allowed_commands [
    "mix test",
    "mix format",
    "mix credo",
    "mix compile",
    "mix deps.get"
  ]

  @ets_table :familiar_safety_config

  # Tools that require path validation
  @write_tools [:write_file, :delete_file]
  @read_tools [:read_file, :list_files, :search_files]
  @file_tools @write_tools ++ @read_tools

  # -- Extension Callbacks --

  @impl true
  def name, do: "safety"

  @impl true
  def tools, do: []

  @impl true
  def hooks do
    [
      %{
        hook: :before_tool_call,
        handler: &check_tool_call/2,
        priority: 1,
        type: :alter
      }
    ]
  end

  @impl true
  def init(opts) do
    project_dir =
      opts
      |> Keyword.get_lazy(:project_dir, &File.cwd!/0)
      |> Path.expand()

    allowed_commands = Keyword.get(opts, :allowed_commands, @default_allowed_commands)

    # Create or re-initialize the ETS table
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete(@ets_table)
    end

    :ets.new(@ets_table, [:set, :named_table, :protected, read_concurrency: true])
    :ets.insert(@ets_table, {:project_dir, project_dir})
    :ets.insert(@ets_table, {:allowed_commands, allowed_commands})

    :ok
  end

  # -- Alter Hook Handler --

  @doc false
  def check_tool_call(%{tool: tool, args: args} = payload, _context) do
    config = load_config()

    case check(tool, args, config) do
      :ok -> {:ok, payload}
      {:halt, _reason} = halt -> halt
    end
  end

  # -- Private: Per-Tool Checks --

  defp check(tool, args, config) when tool in @file_tools do
    raw_path = Map.get(args, :path, Map.get(args, "path"))

    if raw_path do
      expanded = Path.expand(raw_path, config.project_dir)

      with :ok <- validate_path(expanded, raw_path, config.project_dir),
           :ok <- check_git_protection(tool, expanded, config.project_dir) do
        check_delete_restrictions(tool, expanded)
      end
    else
      # No path arg — passthrough (tool will handle missing arg error)
      :ok
    end
  end

  defp check(:run_command, args, config) do
    command = Map.get(args, :command, Map.get(args, "command")) || ""
    command = to_string(command)
    check_command_allowed(command, config.allowed_commands)
  end

  defp check(_tool, _args, _config), do: :ok

  # -- Path Validation --

  defp validate_path(expanded, raw_path, project_dir) do
    if String.starts_with?(expanded, project_dir <> "/") or expanded == project_dir do
      :ok
    else
      {:halt, "path_outside_project: #{raw_path}"}
    end
  end

  # -- Git Protection --

  defp check_git_protection(tool, path, project_dir) when tool in @write_tools do
    if in_git_dir?(path, project_dir) do
      {:halt, "git_dir_protected: #{path}"}
    else
      :ok
    end
  end

  defp check_git_protection(_tool, _path, _project_dir), do: :ok

  defp in_git_dir?(expanded_path, project_dir) do
    relative = Path.relative_to(expanded_path, project_dir)

    case Path.split(relative) do
      [".git" | _] -> true
      _ -> false
    end
  end

  # -- Command Allow-List --

  defp check_command_allowed(command, allowed_commands) do
    if Enum.any?(allowed_commands, fn prefix -> command_matches_prefix?(command, prefix) end) do
      :ok
    else
      {:halt, "command_not_allowed: #{command}"}
    end
  end

  # Matches if command equals the prefix exactly, or continues with a space.
  # This prevents "mix test;evil" from matching "mix test" while allowing
  # "mix test test/my_test.exs". Best-effort — not a security boundary.
  defp command_matches_prefix?(command, prefix) do
    command == prefix or String.starts_with?(command, prefix <> " ")
  end

  # -- Delete Restrictions --

  defp check_delete_restrictions(:delete_file, path) do
    if File.dir?(path) do
      {:halt, "directory_delete_blocked: #{path}"}
    else
      :ok
    end
  end

  defp check_delete_restrictions(_tool, _path), do: :ok

  # -- Config --

  defp load_config do
    [{:project_dir, project_dir}] = :ets.lookup(@ets_table, :project_dir)
    [{:allowed_commands, allowed_commands}] = :ets.lookup(@ets_table, :allowed_commands)
    %{project_dir: project_dir, allowed_commands: allowed_commands}
  end
end
