defmodule Familiar.CLI.DaemonManager do
  @moduledoc """
  Daemon auto-start and lifecycle management for the CLI.

  Provides `ensure_running/1` which checks if the daemon is healthy,
  starts it if needed, and waits for the health check to pass.
  """

  require Logger

  alias Familiar.CLI.HttpClient
  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.PidFile
  alias Familiar.Daemon.StateFile

  @default_poll_interval 200
  @default_max_wait 10_000

  @doc """
  Check daemon status.

  Returns `{:running, info}`, `{:stale, info}`, or `{:stopped, info}`.

  Options:
  - `:health_fn` — override health check function (for testing)
  """
  @spec daemon_status(keyword()) :: {:running | :stale | :stopped, map()}
  def daemon_status(opts \\ []) do
    health_fn = Keyword.get(opts, :health_fn, &HttpClient.health_check/1)

    case StateFile.read() do
      {:ok, %{"port" => port}} ->
        case health_fn.(port) do
          {:ok, %{version: version}} ->
            {:running, %{port: port, version: version}}

          {:error, _} ->
            {:stale, %{port: port}}
        end

      {:error, _} ->
        {:stopped, %{}}
    end
  end

  @doc """
  Ensure the daemon is running. Start it if needed.

  Returns `{:ok, port}` or `{:error, reason}`.

  Options:
  - `:health_fn` — override health check function
  - `:start_fn` — override daemon start function
  - `:poll_interval` — ms between health check retries (default: 200)
  - `:max_wait` — max ms to wait for daemon (default: 10000)
  """
  @spec ensure_running(keyword()) :: {:ok, integer()} | {:error, {atom(), map()}}
  def ensure_running(opts \\ []) do
    health_fn = Keyword.get(opts, :health_fn, &HttpClient.health_check/1)
    start_fn = Keyword.get(opts, :start_fn, &start_daemon/0)

    case daemon_status(health_fn: health_fn) do
      {:running, %{port: port}} ->
        {:ok, port}

      _not_running ->
        case start_fn.() do
          {:ok, port} ->
            wait_for_health(port, health_fn, opts)

          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Start the daemon as a detached background process.

  Spawns a new BEAM instance running the Phoenix app via `mix phx.server`.
  """
  @spec start_daemon() :: {:ok, integer()} | {:error, {atom(), map()}}
  def start_daemon do
    project_dir = Paths.project_dir()

    case System.find_executable("mix") do
      nil ->
        {:error, {:daemon_unavailable, %{reason: :mix_not_found}}}

      mix_path ->
        do_start_daemon(mix_path, project_dir)
    end
  end

  defp do_start_daemon(mix_path, project_dir) do
    env = [{"MIX_ENV", to_string(Mix.env())}, {"PHX_SERVER", "true"}]
    env_args = Enum.flat_map(env, fn {k, v} -> ["#{k}=#{v}"] end)

    # Use nohup + shell to fully detach the daemon from the CLI process
    spawn(fn ->
      System.cmd("env", env_args ++ [mix_path, "phx.server"],
        cd: project_dir,
        stderr_to_stdout: true,
        into: File.stream!(Path.join(project_dir, ".familiar/daemon.log"), [:append])
      )
    end)

    # Return configured port — caller will poll via wait_for_health
    {:ok, configured_port()}
  rescue
    e ->
      {:error, {:daemon_unavailable, %{reason: Exception.message(e)}}}
  end

  @doc """
  Stop the running daemon.

  Primary: POST /api/daemon/stop
  Fallback: SIGTERM via PID file

  Options:
  - `:stop_fn` — override HTTP stop function
  """
  @spec stop_daemon(keyword()) :: :ok | {:error, {atom(), map()}}
  def stop_daemon(opts \\ []) do
    stop_fn = Keyword.get(opts, :stop_fn, &http_stop/1)

    case StateFile.read() do
      {:ok, %{"port" => port}} ->
        case stop_fn.(port) do
          {:ok, _} -> :ok
          {:error, _} -> fallback_stop()
        end

      {:error, _} ->
        fallback_stop()
    end
  end

  # -- Private --

  defp wait_for_health(port, health_fn, opts) do
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    max_wait = Keyword.get(opts, :max_wait, @default_max_wait)
    deadline = System.monotonic_time(:millisecond) + max_wait

    do_wait_for_health(port, health_fn, poll_interval, deadline)
  end

  defp do_wait_for_health(port, health_fn, poll_interval, deadline) do
    case health_fn.(port) do
      {:ok, _} ->
        {:ok, port}

      {:error, _} ->
        now = System.monotonic_time(:millisecond)

        if now >= deadline do
          {:error, {:timeout, %{reason: :health_check}}}
        else
          Process.sleep(poll_interval)
          do_wait_for_health(port, health_fn, poll_interval, deadline)
        end
    end
  end

  defp http_stop(port) do
    HttpClient.request(:post, "/api/daemon/stop", port: port, timeout: 5_000)
  end

  defp fallback_stop do
    case PidFile.read() do
      {:ok, pid_str} ->
        System.cmd("kill", [pid_str], stderr_to_stdout: true)
        :ok

      {:error, _} ->
        {:error, {:daemon_unavailable, %{reason: :no_running_daemon}}}
    end
  end

  defp configured_port do
    case Application.get_env(:familiar, FamiliarWeb.Endpoint) do
      nil -> 4000
      config -> get_in(config, [:http, :port]) || 4000
    end
  end
end
