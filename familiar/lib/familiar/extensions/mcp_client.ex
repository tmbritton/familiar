defmodule Familiar.Extensions.MCPClient do
  @moduledoc """
  Extension that manages MCP server lifecycles.

  On init, merges server configurations from two sources:
    1. Database rows via `Familiar.MCP.Servers.list/0` (source: `:db`)
    2. `[[mcp.servers]]` entries from config.toml (source: `:config`)

  DB entries win on name collision. For each enabled entry, starts a
  `Familiar.MCP.Client` child under `Familiar.MCP.ClientSupervisor`.

  Tools are registered by individual Client GenServers, not by this
  extension — it is purely a lifecycle manager.
  """

  @behaviour Familiar.Extension

  require Logger

  alias Familiar.Execution.ToolRegistry
  alias Familiar.MCP.Client
  alias Familiar.MCP.ClientSupervisor
  alias Familiar.MCP.Servers

  @ets_table :familiar_mcp_servers

  # -- Extension Callbacks --

  @impl true
  def name, do: "mcp-client"

  @impl true
  def tools, do: []

  @impl true
  def hooks, do: []

  @impl true
  def init(opts) do
    init_ets()
    servers = merge_server_sources(opts)
    start_enabled_servers(servers, opts)
    :ok
  rescue
    error ->
      Logger.warning("[MCPClient] Init failed: #{Exception.message(error)}")
      :ok
  end

  # -- Public API --

  @doc "Get status of all tracked MCP servers."
  @spec server_status() :: [map()]
  def server_status do
    tool_counts = build_tool_count_map()

    @ets_table
    |> :ets.tab2list()
    |> Enum.map(fn {server_name, source, pid} ->
      {status, _reason} = safe_client_status(pid)
      count = Map.get(tool_counts, "mcp:#{server_name}", 0)
      %{name: server_name, source: source, status: status, tool_count: count}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_tool_count_map do
    ToolRegistry.list_tools()
    |> Enum.reduce(%{}, fn tool, acc ->
      Map.update(acc, tool.extension, 1, &(&1 + 1))
    end)
  rescue
    _ -> %{}
  end

  @doc "Reload a single server by name. Stops existing client, re-reads from DB, starts fresh."
  @spec reload_server(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def reload_server(server_name, opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, ClientSupervisor)
    stop_existing_client(server_name, supervisor)

    case Servers.get(server_name) do
      {:ok, server} ->
        if server.disabled do
          {:error, :disabled}
        else
          start_server_client(server_name, server_to_client_opts(server, :db, opts))
        end

      {:error, :not_found} ->
        :ets.delete(@ets_table, server_name)
        {:error, :not_found}
    end
  end

  # -- Private --

  defp init_ets do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :set, :public])
    end
  end

  defp merge_server_sources(opts) do
    db_servers = load_db_servers()
    config_servers = load_config_servers(opts)
    db_names = MapSet.new(db_servers, fn {name, _} -> name end)

    config_only =
      Enum.reject(config_servers, fn {name, _} ->
        if MapSet.member?(db_names, name) do
          Logger.warning("[MCPClient] Config server '#{name}' overridden by database entry")

          true
        else
          false
        end
      end)

    db_servers ++ config_only
  end

  defp load_db_servers do
    Servers.list()
    |> Enum.map(fn server ->
      {server.name, server_to_client_opts(server, :db, [])}
    end)
  rescue
    error ->
      Logger.warning("[MCPClient] Failed to load DB servers: #{Exception.message(error)}")
      []
  end

  defp load_config_servers(opts) do
    config = Keyword.get(opts, :config)
    mcp_servers = if config, do: config.mcp_servers, else: []

    mcp_servers
    |> Kernel.||([])
    |> dedup_config_entries()
    |> Enum.map(fn entry ->
      {entry.name, config_entry_to_client_opts(entry, opts)}
    end)
  end

  defp dedup_config_entries(entries) do
    {deduped, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, seen} ->
        if MapSet.member?(seen, entry.name) do
          Logger.warning(
            "[MCPClient] Duplicate config.toml server '#{entry.name}' — keeping first entry"
          )

          {acc, seen}
        else
          {[entry | acc], MapSet.put(seen, entry.name)}
        end
      end)

    Enum.reverse(deduped)
  end

  defp server_to_client_opts(server, source, extra_opts) do
    args = decode_json_field(server.args_json, [])
    env = decode_json_field(server.env_json, %{})

    base = [
      server_name: server.name,
      command: server.command,
      args: args,
      env: env,
      source: source,
      read_only: server.read_only,
      disabled: server.disabled
    ]

    merge_extra_opts(base, extra_opts)
  end

  defp config_entry_to_client_opts(entry, extra_opts) do
    base = [
      server_name: entry.name,
      command: entry.command,
      args: entry[:args] || [],
      env: entry[:env] || %{},
      source: :config,
      read_only: false
    ]

    merge_extra_opts(base, extra_opts)
  end

  defp merge_extra_opts(base, extra_opts) do
    port_opener = Keyword.get(extra_opts, :port_opener)
    if port_opener, do: Keyword.put(base, :port_opener, port_opener), else: base
  end

  defp decode_json_field(json, default) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, value} -> value
      {:error, _} -> default
    end
  end

  defp decode_json_field(_, default), do: default

  defp start_enabled_servers(servers, opts) do
    Enum.each(servers, fn {name, server_opts} ->
      start_or_skip_server(name, server_opts, opts)
    end)
  end

  defp start_or_skip_server(name, server_opts, opts) do
    if Keyword.get(server_opts, :disabled, false) do
      Logger.info("[MCPClient] Skipping disabled server '#{name}'")
    else
      client_opts = build_client_opts(server_opts, opts)
      source = Keyword.get(server_opts, :source, :db)

      case start_server_client(name, [{:source, source} | client_opts]) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("[MCPClient] Failed to start server '#{name}': #{inspect(reason)}")
      end
    end
  end

  defp build_client_opts(server_opts, extra_opts) do
    base =
      Keyword.take(server_opts, [
        :server_name,
        :command,
        :args,
        :env,
        :connect_timeout,
        :call_timeout,
        :port_opener,
        :read_only
      ])

    port_opener = Keyword.get(extra_opts, :port_opener)

    if port_opener && !Keyword.has_key?(base, :port_opener) do
      Keyword.put(base, :port_opener, port_opener)
    else
      base
    end
  end

  defp start_server_client(name, opts) do
    source = Keyword.get(opts, :source, :db)
    client_opts = Keyword.delete(opts, :source)
    supervisor = Keyword.get(opts, :supervisor, ClientSupervisor)
    client_opts = Keyword.delete(client_opts, :supervisor)

    case ClientSupervisor.start_client([{:supervisor, supervisor} | client_opts]) do
      {:ok, pid} ->
        :ets.insert(@ets_table, {name, source, pid})
        {:ok, pid}

      {:error, reason} = err ->
        Logger.warning("[MCPClient] Failed to start client '#{name}': #{inspect(reason)}")
        err
    end
  end

  defp stop_existing_client(name, supervisor) do
    case :ets.lookup(@ets_table, name) do
      [{^name, _source, pid}] ->
        ClientSupervisor.stop_client(supervisor, pid)
        :ets.delete(@ets_table, name)

      [] ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp safe_client_status(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Client.status(pid)
    else
      {:crashed, "process dead"}
    end
  rescue
    _ -> {:crashed, "unreachable"}
  end

  defp safe_client_status(_), do: {:crashed, "no pid"}
end
