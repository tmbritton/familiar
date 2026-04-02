defmodule Familiar.Daemon.PidFile do
  @moduledoc """
  PID file management for the daemon process.

  Writes the OS PID to `.familiar/daemon.pid` and uses a lock file
  to prevent two daemons from starting simultaneously.
  """

  alias Familiar.Daemon.Paths

  @doc """
  Write the current OS PID to the PID file.

  Acquires an advisory lock first. If another daemon is running
  (PID file exists and process is alive), returns an error.
  """
  @spec write() :: {:ok, String.t()} | {:error, {atom(), map()}}
  def write do
    Paths.ensure_familiar_dir!()

    case acquire_lock() do
      :ok ->
        pid = os_pid()

        case check_existing() do
          :ok ->
            File.write!(Paths.daemon_pid_path(), pid)
            {:ok, pid}

          {:error, _} = error ->
            release_lock()
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc "Read the PID from the PID file."
  @spec read() :: {:ok, String.t()} | {:error, {atom(), map()}}
  def read do
    case File.read(Paths.daemon_pid_path()) do
      {:ok, content} ->
        trimmed = String.trim(content)

        if valid_pid_string?(trimmed) do
          {:ok, trimmed}
        else
          {:error, {:invalid_config, %{reason: :malformed_pid, content: trimmed}}}
        end

      {:error, :enoent} ->
        {:error, {:not_found, %{}}}

      {:error, reason} ->
        {:error, {:storage_failed, %{reason: reason}}}
    end
  end

  @doc "Remove the PID and lock files."
  @spec cleanup() :: :ok
  def cleanup do
    File.rm(Paths.daemon_pid_path())
    release_lock()
    :ok
  end

  @doc "Check if the PID in the file corresponds to a running process."
  @spec alive?() :: boolean()
  def alive? do
    case read() do
      {:ok, pid} -> process_alive?(pid)
      {:error, _} -> false
    end
  end

  # -- Private --

  defp acquire_lock do
    lock_path = Paths.daemon_lock_path()

    case File.open(lock_path, [:write, :exclusive]) do
      {:ok, file} ->
        File.close(file)
        :ok

      {:error, :eexist} ->
        handle_existing_lock(lock_path)

      {:error, reason} ->
        {:error, {:storage_failed, %{reason: reason}}}
    end
  end

  defp handle_existing_lock(lock_path) do
    case read() do
      {:ok, pid} when is_binary(pid) ->
        if process_alive?(pid) do
          {:error, {:daemon_already_running, %{pid: pid}}}
        else
          File.rm(lock_path)
          acquire_lock()
        end

      _ ->
        File.rm(lock_path)
        acquire_lock()
    end
  end

  defp release_lock do
    File.rm(Paths.daemon_lock_path())
    :ok
  end

  defp check_existing do
    case read() do
      {:ok, existing_pid} ->
        if process_alive?(existing_pid) do
          {:error, {:daemon_already_running, %{pid: existing_pid}}}
        else
          :ok
        end

      {:error, {:not_found, _}} ->
        :ok

      {:error, {:invalid_config, _}} ->
        # Corrupted PID file — safe to overwrite
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp process_alive?(pid_string) do
    if valid_pid_string?(pid_string) do
      case System.cmd("kill", ["-0", pid_string], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp valid_pid_string?(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> true
      _ -> false
    end
  end

  defp os_pid do
    :os.getpid() |> to_string()
  end
end
