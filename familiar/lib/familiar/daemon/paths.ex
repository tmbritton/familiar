defmodule Familiar.Daemon.Paths do
  @moduledoc """
  Path resolution for the `.familiar/` directory structure.

  ## Precedence model

  `resolve_project_dir/2` is the single authoritative chain every entry
  point should use (CLI commands, daemon boot, workflow runner resume,
  background jobs, `fam where`, tests). Precedence:

  1. **Explicit argument** (e.g. a `--project-dir` flag). `:explicit`.
  2. **`FAMILIAR_PROJECT_DIR` env var**, non-nil, non-empty. `:env`.
  3. **Cwd walk-up** — starting at `File.cwd!/0`, walk parent directories
     looking for a `.familiar/` subdirectory, stopping at the filesystem
     root. Mirrors how `git` resolves the repository root, so `fam`
     commands work from any subdirectory of a project. `{:walk_up, dir}`.
  4. **Cwd fallback** — only when `allow_cwd_fallback: true` (for `fam init`
     and `fam where`). `:cwd_fallback`.
  5. **Hard error** — `{:error, {:project_dir_unresolvable, details}}`.

  ## Bootstrap safety

  `resolve_project_dir/2` is a pure function over its arguments, the
  `FAMILIAR_PROJECT_DIR` env var, and the filesystem. It has no
  dependency on `Familiar.Repo`, `Logger`, extensions, or anything that
  assumes the `:familiar` application has started. This means it is
  safe to call from `Familiar.CLI.Main.main/1` *before*
  `Application.ensure_all_started/1`.

  ## Backward compatibility

  `project_dir/0` continues to return a bare string. It reads
  `Application.get_env(:familiar, :project_dir)` (the test-override
  convention established in Story 7.5-5) and passes it as the explicit
  argument to `resolve_project_dir/2` with `allow_cwd_fallback: true`,
  so no existing caller needs to change.

  See `validate_familiar_project/1` for the separate validation step
  that commands requiring an initialized project should run after
  resolution.
  """

  @familiar_subdir ".familiar"

  # Max ancestors to check during walk-up. Caps runaway walks on stuck
  # NFS/FUSE mounts or pathological symlink chains. Real-world project
  # trees rarely exceed ~20; 64 is a generous safety margin.
  @max_walk_up_depth 64

  @type source ::
          :explicit
          | :env
          | {:walk_up, String.t()}
          | :cwd_fallback

  @type resolve_opts :: [
          env: String.t() | nil,
          cwd: String.t(),
          allow_cwd_fallback: boolean()
        ]

  @type resolve_error ::
          {:project_dir_unresolvable,
           %{
             cwd: String.t(),
             env: String.t() | nil,
             explicit: String.t() | nil,
             reason: atom()
           }}

  @doc """
  Returns the project root directory.

  Thin wrapper over `resolve_project_dir/2` that preserves the legacy
  signature for the 30+ existing callers. Never raises: falls back to
  the current working directory when no other signal is available.

  Reads `Application.get_env(:familiar, :project_dir)` and passes it as
  the explicit argument — this is how existing tests override the
  resolved project directory without mutating `System.put_env`.

  Defensive fallback: if `resolve_project_dir/2` ever returns an
  unexpected shape (e.g., a future refactor introduces a new error
  variant), this falls back to `File.cwd/0` rather than raising, to
  honor the "never raises" contract that load-bearing callers depend
  on.
  """
  @spec project_dir() :: String.t()
  def project_dir do
    explicit = Application.get_env(:familiar, :project_dir)

    case resolve_project_dir(explicit, allow_cwd_fallback: true) do
      {:ok, dir, _source} ->
        dir

      _other ->
        # Fallback for any future refactor that introduces a new return
        # shape. Never raise — 30+ callers depend on this contract.
        case File.cwd() do
          {:ok, cwd} -> Path.expand(cwd)
          _ -> "/"
        end
    end
  end

  @doc """
  Returns the resolved project directory or an error tuple describing
  what was checked.

  Use this from callers that need to surface an actionable error when
  no project directory can be resolved — notably `fam where` and CLI
  commands that require an initialized project.

  Unlike `project_dir/0`, this does NOT fall back to the current
  working directory. If walk-up fails, you get a structured error.
  """
  @spec project_dir_or_error() :: {:ok, String.t(), source()} | {:error, resolve_error()}
  def project_dir_or_error do
    explicit = Application.get_env(:familiar, :project_dir)
    resolve_project_dir(explicit)
  end

  @doc """
  Resolve the project directory through the full precedence chain.

  Options (all optional — injected for testability):

    * `:env` — override for the `FAMILIAR_PROJECT_DIR` env var read. Pass
      `nil` to simulate an unset env var. Pass the option explicitly
      (even as `nil`) to indicate the env was checked. Defaults to
      `System.get_env("FAMILIAR_PROJECT_DIR")`.
    * `:cwd` — override for the `File.cwd!/0` read. Defaults to the
      real cwd via `File.cwd/0` (not `File.cwd!/0`) so a deleted cwd
      falls through to `"(unknown)"` instead of raising.
    * `:allow_cwd_fallback` — when `true`, fall back to the cwd when
      walk-up finds no `.familiar/` ancestor. When `false` (default),
      return `{:error, {:project_dir_unresolvable, ...}}` instead.

  Validates both `:explicit` and `:env` values: rejects empty and
  whitespace-only strings, and rejects paths that exist but are not
  directories (e.g., `FAMILIAR_PROJECT_DIR=/etc/passwd`). A path that
  does NOT exist is accepted through the `:env` / `:explicit` branches
  — this preserves the ability to point at a future project dir and
  let `fam init` create it.

  Tests should pass `:env` and `:cwd` to avoid mutating global state
  (which leaks across parallel tests and creates flakes).
  """
  @spec resolve_project_dir(String.t() | nil, resolve_opts()) ::
          {:ok, String.t(), source()} | {:error, resolve_error()}
  def resolve_project_dir(explicit \\ nil, opts \\ []) do
    env =
      Keyword.get_lazy(opts, :env, fn -> System.get_env("FAMILIAR_PROJECT_DIR") end)

    cwd = cwd_from_opts(opts)
    allow_cwd_fallback = Keyword.get(opts, :allow_cwd_fallback, false)

    cond do
      usable_path?(explicit) ->
        validated_ok(explicit, :explicit, explicit, env, cwd)

      usable_path?(env) ->
        validated_ok(env, :env, explicit, env, cwd)

      true ->
        resolve_via_walk_up(cwd, explicit, env, allow_cwd_fallback)
    end
  end

  # `cwd` opt defaults to File.cwd/0 (returns {:ok, dir} | {:error, _}),
  # NOT File.cwd!/0 — a deleted cwd must not crash bootstrap.
  defp cwd_from_opts(opts) do
    case Keyword.fetch(opts, :cwd) do
      {:ok, value} when is_binary(value) ->
        value

      {:ok, _} ->
        "(unknown)"

      :error ->
        case File.cwd() do
          {:ok, dir} -> dir
          _ -> "(unknown)"
        end
    end
  end

  # Accept a path only if it's a non-empty, non-whitespace binary.
  defp usable_path?(value) when is_binary(value) do
    String.trim(value) != ""
  end

  defp usable_path?(_), do: false

  # Expand and validate a resolved path from the :explicit or :env branch.
  # If the path exists but is NOT a directory, return the unresolvable
  # error with reason :not_a_directory so the user sees a clear message.
  # Non-existent paths are accepted — `fam init` needs that.
  defp validated_ok(raw, source, explicit, env, cwd) do
    expanded = raw |> String.trim() |> Path.expand()

    cond do
      File.dir?(expanded) ->
        {:ok, expanded, source}

      File.exists?(expanded) ->
        {:error,
         {:project_dir_unresolvable,
          %{
            cwd: Path.expand(cwd),
            env: env,
            explicit: explicit,
            reason: :not_a_directory,
            offending_path: expanded
          }}}

      true ->
        # Path does not exist yet; accept it so `fam init` can create it.
        {:ok, expanded, source}
    end
  end

  defp resolve_via_walk_up(cwd, explicit, env, allow_cwd_fallback) do
    case find_familiar_root(cwd) do
      {:ok, found} ->
        {:ok, found, {:walk_up, found}}

      :not_found when allow_cwd_fallback ->
        {:ok, Path.expand(cwd), :cwd_fallback}

      :not_found ->
        {:error,
         {:project_dir_unresolvable,
          %{
            cwd: Path.expand(cwd),
            env: env,
            explicit: explicit,
            reason: :no_familiar_dir_found
          }}}
    end
  end

  @doc """
  Walk up from `start_dir` looking for a `.familiar/` subdirectory.

  Returns `{:ok, dir}` with the first ancestor (or `start_dir` itself)
  that contains `.familiar/` as a directory. Returns `:not_found` if the
  filesystem root is reached without a match or if the walk exceeds
  the safety cap (#{@max_walk_up_depth} ancestors).

  A `.familiar` entry that exists as a regular file (not a directory)
  is ignored — the check is strict.

  Safe to call with a starting path that does not exist; missing
  directories are treated as "no match here, walk up."
  """
  @spec find_familiar_root(String.t()) :: {:ok, String.t()} | :not_found
  def find_familiar_root(start_dir) when is_binary(start_dir) do
    start_dir
    |> Path.expand()
    |> walk_up(@max_walk_up_depth)
  end

  def find_familiar_root(_), do: :not_found

  defp walk_up(_dir, 0), do: :not_found

  defp walk_up(dir, depth) do
    cond do
      File.dir?(Path.join(dir, @familiar_subdir)) ->
        {:ok, dir}

      dir == "/" ->
        :not_found

      true ->
        parent = Path.dirname(dir)

        # `Path.dirname/1` is idempotent at the root ("/" → "/"), so guard
        # against that rather than looping forever if we're on a platform
        # with a non-"/" root (Windows). On Unix the `dir == "/"` clause
        # above catches us first; this is belt-and-braces.
        if parent == dir do
          :not_found
        else
          walk_up(parent, depth - 1)
        end
    end
  end

  @doc """
  Validate that `dir` is an initialized Familiar project.

  Returns `:ok` if `Path.join(dir, ".familiar")` is a directory,
  otherwise `{:error, {:not_a_familiar_project, %{path: dir}}}`.

  Commands that require an initialized project (most `fam` subcommands)
  should call this after `resolve_project_dir/2` / `project_dir/0`.
  `fam init` and `fam where` intentionally skip this check.
  """
  @spec validate_familiar_project(String.t()) ::
          :ok | {:error, {:not_a_familiar_project, %{path: String.t()}}}
  def validate_familiar_project(dir) do
    if File.dir?(Path.join(dir, @familiar_subdir)) do
      :ok
    else
      {:error, {:not_a_familiar_project, %{path: dir}}}
    end
  end

  @doc "Returns the `.familiar/` directory path."
  def familiar_dir do
    Path.join(project_dir(), @familiar_subdir)
  end

  @doc "Returns the daemon.json path."
  def daemon_json_path, do: Path.join(familiar_dir(), "daemon.json")

  @doc "Returns the daemon.pid path."
  def daemon_pid_path, do: Path.join(familiar_dir(), "daemon.pid")

  @doc "Returns the daemon.lock path."
  def daemon_lock_path, do: Path.join(familiar_dir(), "daemon.lock")

  @doc "Returns the shutdown marker path."
  def shutdown_marker_path, do: Path.join(familiar_dir(), "shutdown_marker")

  @doc "Returns the database path."
  def db_path, do: Path.join(familiar_dir(), "familiar.db")

  @doc "Returns the backups directory path."
  def backups_dir, do: Path.join(familiar_dir(), "backups")

  @doc "Returns the config.toml path."
  def config_path, do: Path.join(familiar_dir(), "config.toml")

  @doc "Creates the `.familiar/` directory if it doesn't exist."
  def ensure_familiar_dir! do
    dir = familiar_dir()

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to create #{dir}: #{reason}"
    end
  end
end
