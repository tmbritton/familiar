defmodule Familiar.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        FamiliarWeb.Telemetry,
        Familiar.Repo,
        {Task.Supervisor, name: Familiar.TaskSupervisor},
        {Ecto.Migrator,
         repos: Application.fetch_env!(:familiar, :ecto_repos), skip: skip_migrations?()},
        # Recovery gate — runs synchronously after Repo/Migrator, returns :ignore
        Familiar.Daemon.RecoveryGate,
        {DNSCluster, query: Application.get_env(:familiar, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Familiar.PubSub},
        # Hooks GenServer — must start before extensions load
        Familiar.Hooks,
        # Tool registry — must start before extensions register tools
        Familiar.Execution.ToolRegistry,
        # Daemon lifecycle — conditionally started (disabled in test env)
        if(Application.get_env(:familiar, :start_daemon, true),
          do: Familiar.Daemon.Server
        ),
        # Start to serve requests, typically the last entry
        FamiliarWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Familiar.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Load extensions after supervisor is up (Hooks and TaskSupervisor are running)
    case result do
      {:ok, _pid} ->
        load_extensions()
        result

      _ ->
        result
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamiliarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end

  defp load_extensions do
    alias Familiar.Execution.ExtensionLoader
    alias Familiar.Execution.ToolRegistry

    # Register core built-in tool stubs before extensions (extensions can override)
    ToolRegistry.register_builtins()

    extensions = Application.get_env(:familiar, :extensions, [])

    case ExtensionLoader.load_extensions(extensions) do
      {:ok, %{loaded: loaded, failed: failed, tools: tools, child_specs: child_specs}} ->
        register_extension_tools(tools)
        start_extension_children(child_specs)
        log_extension_results(loaded, failed)
        Familiar.Hooks.event(:on_startup, %{extensions: loaded})

      _ ->
        :ok
    end
  end

  defp register_extension_tools(tools) do
    alias Familiar.Execution.ToolRegistry

    for {name, function, description, extension_name} <- tools do
      ToolRegistry.register(name, function, description, extension_name)
    end
  end

  defp start_extension_children(child_specs) do
    for spec <- child_specs do
      case Supervisor.start_child(Familiar.Supervisor, spec) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("[Application] Failed to start extension child: #{inspect(reason)}")
      end
    end
  end

  defp log_extension_results(loaded, failed) do
    if failed != [] do
      Logger.warning(
        "[Application] #{length(failed)} extension(s) failed to load: " <>
          inspect(Enum.map(failed, &elem(&1, 0)))
      )
    end

    if loaded != [] do
      Logger.info("[Application] Loaded extensions: #{Enum.join(loaded, ", ")}")
    end
  end
end
