defmodule Familiar.Daemon.StateFile do
  @moduledoc """
  Manages `.familiar/daemon.json` — the runtime state file
  that stores the daemon's port, PID, and start time.

  The CLI reads this file to discover the running daemon.
  """

  alias Familiar.Daemon.Paths

  @doc "Write daemon state to daemon.json. Requires port, pid, and started_at keys."
  @spec write(map()) :: :ok
  def write(%{port: _, pid: _, started_at: _} = state) do
    Paths.ensure_familiar_dir!()
    json = Jason.encode!(state, pretty: true)
    File.write!(Paths.daemon_json_path(), json)
    :ok
  end

  @doc "Read and parse daemon.json."
  @spec read() :: {:ok, map()} | {:error, {atom(), map()}}
  def read do
    case File.read(Paths.daemon_json_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, state} ->
            {:ok, state}

          {:error, _} ->
            {:error, {:invalid_config, %{file: "daemon.json", reason: :invalid_json}}}
        end

      {:error, :enoent} ->
        {:error, {:not_found, %{}}}

      {:error, reason} ->
        {:error, {:storage_failed, %{reason: reason}}}
    end
  end

  @doc "Remove daemon.json."
  @spec cleanup() :: :ok
  def cleanup do
    File.rm(Paths.daemon_json_path())
    :ok
  end
end
