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
        # Recovery gate — runs synchronously after Repo/Migrator (disabled in CLI mode)
        if(not cli_mode?(), do: Familiar.Daemon.RecoveryGate),
        {DNSCluster, query: Application.get_env(:familiar, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Familiar.PubSub},
        # Hooks GenServer — must start before extensions load
        Familiar.Hooks,
        # Tool registry — must start before extensions register tools
        Familiar.Execution.ToolRegistry,
        # File watcher — watches project directory for changes (disabled in test env)
        if(Application.get_env(:familiar, :start_file_watcher, true),
          do: Familiar.Execution.FileWatcher
        ),
        # Agent supervisor — DynamicSupervisor for all agent processes
        Familiar.Execution.AgentSupervisor,
        # MCP client supervisor — DynamicSupervisor for MCP server connections
        Familiar.MCP.ClientSupervisor,
        # Daemon lifecycle — disabled in test env and CLI mode
        if(Application.get_env(:familiar, :start_daemon, true) and not cli_mode?(),
          do: Familiar.Daemon.Server
        ),
        # Web endpoint — disabled in CLI mode
        if(not cli_mode?(), do: FamiliarWeb.Endpoint)
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Familiar.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Load extensions after supervisor is up (Hooks and TaskSupervisor are running)
    case result do
      {:ok, _pid} ->
        load_extensions()
        check_embedding_drift()
        result

      _ ->
        result
    end
  end

  # Warn the user once per VM lifetime when the configured embedding model
  # differs from the model that produced the stored vectors. Runs under
  # `Task.start/1` so a slow Repo can't block the boot path. Skipped
  # entirely in test env and in CLI mode before the Repo is reachable.
  defp check_embedding_drift do
    cond do
      Application.get_env(:familiar, :skip_embedding_drift_check, false) ->
        :ok

      :persistent_term.get({__MODULE__, :drift_warned}, false) ->
        :ok

      true ->
        Task.start(fn ->
          try do
            do_check_embedding_drift()
          rescue
            e ->
              Logger.warning("[Familiar] Embedding drift check failed: #{inspect(e)}")
          catch
            :exit, reason ->
              Logger.warning("[Familiar] Embedding drift check exited: #{inspect(reason)}")
          end
        end)

        :ok
    end
  end

  # Exposed via @doc false so tests can drive the drift-warning branches
  # without racing the Task.start path in check_embedding_drift/0.
  @doc false
  def do_check_embedding_drift do
    alias Familiar.Knowledge
    alias Familiar.Knowledge.EmbeddingMetadata

    configured = Knowledge.current_embedding_model()

    case EmbeddingMetadata.check_drift(configured) do
      :ok ->
        :ok

      {:warning, :model_changed, %{stored: stored, configured: configured}} ->
        :persistent_term.put({__MODULE__, :drift_warned}, true)

        Logger.warning(
          "[Familiar] Embedding model changed: stored=#{stored} configured=#{configured}. " <>
            "Run `fam context --reindex` to re-embed knowledge entries with the new model. " <>
            "Search results will be inaccurate until reindex completes. " <>
            "(Cost: ~$0.04 per 10k entries with text-embedding-3-small.)"
        )

      {:warning, :model_unset, %{configured: configured}} ->
        :persistent_term.put({__MODULE__, :drift_warned}, true)

        Logger.warning(
          "[Familiar] Embedding model is not recorded (stored=unset) but configured=#{configured}. " <>
            "Run `fam context --reindex` to re-embed knowledge entries and record the active model."
        )
    end
  end

  @doc """
  Clear the once-per-VM drift-warning sentinel.

  Used by tests that want to exercise the warning branches of
  `do_check_embedding_drift/0` multiple times in the same VM. Not called
  by production code.
  """
  @spec reset_drift_sentinel() :: :ok
  def reset_drift_sentinel do
    :persistent_term.erase({__MODULE__, :drift_warned})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamiliarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp cli_mode?, do: System.get_env("FAMILIAR_PROJECT_DIR") != nil

  defp skip_migrations? do
    # Run migrations when FAMILIAR_PROJECT_DIR is set (CLI mode) or in a release
    # Skip in dev/test when running the Phoenix server normally
    System.get_env("FAMILIAR_PROJECT_DIR") == nil and
      System.get_env("RELEASE_NAME") == nil
  end

  defp load_extensions do
    alias Familiar.Daemon.Paths
    alias Familiar.Execution.ExtensionLoader
    alias Familiar.Execution.ToolRegistry
    alias Familiar.Execution.ToolSchemas

    # Load tool schemas from .familiar/tools/ (or compiled-in defaults)
    if File.dir?(Paths.familiar_dir()) do
      ToolSchemas.load(Paths.familiar_dir())
    else
      ToolSchemas.load_defaults()
    end

    # Register core built-in tool stubs before extensions (extensions can override)
    ToolRegistry.register_builtins()

    # Register real tool implementations (overrides stubs)
    alias Familiar.Execution.WorkflowRunner
    WorkflowRunner.register_signal_ready_tool()

    extensions = Application.get_env(:familiar, :extensions, [])

    case ExtensionLoader.load_extensions(extensions) do
      {:ok, %{loaded: loaded, failed: failed, tools: tools, child_specs: child_specs}} ->
        register_extension_tools(tools)
        start_extension_children(child_specs)
        log_extension_results(loaded, failed)
        Familiar.Hooks.event(:on_startup, %{extensions: loaded})
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
