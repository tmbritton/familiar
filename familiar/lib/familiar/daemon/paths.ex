defmodule Familiar.Daemon.Paths do
  @moduledoc """
  Path resolution for `.familiar/` directory structure.

  All daemon runtime files (PID, state, database, markers) live under
  the project's `.familiar/` directory.
  """

  @doc "Returns the project root directory."
  def project_dir do
    Application.get_env(:familiar, :project_dir, File.cwd!())
  end

  @doc "Returns the `.familiar/` directory path."
  def familiar_dir do
    Path.join(project_dir(), ".familiar")
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
