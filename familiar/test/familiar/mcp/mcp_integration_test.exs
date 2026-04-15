defmodule Familiar.MCP.MCPIntegrationTest do
  @moduledoc """
  End-to-end integration test for MCP client pipeline.

  Exercises real SQLite (Ecto sandbox), real MCPClient extension,
  real ToolRegistry, and real CLI dispatch with a FakePort standing
  in for the MCP server subprocess.
  """

  use Familiar.DataCase, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Extensions.MCPClient
  alias Familiar.MCP.Client
  alias Familiar.MCP.Protocol
  alias Familiar.MCP.Servers
  alias Familiar.Test.FakeMCPServer
  alias Familiar.Test.FakeMCPServer.FakePort

  defdelegate send_line(client, fake_port, json), to: FakeMCPServer
  defdelegate receive_fake_port(), to: FakeMCPServer

  @moduletag :tmp_dir
  @moduletag :integration

  # -- Setup --

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()

    # Start test-specific DynamicSupervisor
    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Start the real ToolRegistry. MCP Client registers tools via the
    # module name, so we need the global instance running.
    registry =
      case ToolRegistry.start_link([]) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # Clean ETS between tests
    if :ets.whereis(:familiar_mcp_servers) != :undefined do
      :ets.delete_all_objects(:familiar_mcp_servers)
    end

    on_exit(fn ->
      Application.delete_env(:familiar, :project_dir)

      try do
        if Process.alive?(sup), do: DynamicSupervisor.stop(sup)
      catch
        :exit, _ -> :ok
      end

      # Unregister any leftover MCP tools
      try do
        for tool <- ToolRegistry.list_tools(),
            String.starts_with?(tool.extension, "mcp:") do
          ToolRegistry.unregister(tool.name)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{supervisor: sup, registry: registry}
  end

  # -- Helpers --

  defp make_port_opener do
    FakeMCPServer.make_port_opener_notify(self())
  end

  defp complete_handshake(client, fake_port) do
    FakeMCPServer.complete_handshake(client, fake_port)
  end

  defp complete_handshake_with_tools(client, fake_port, tools) do
    FakeMCPServer.complete_handshake(client, fake_port, tools: tools)
  end

  defp mixed_tools do
    [
      %{"name" => "list_repos", "description" => "List repos", "inputSchema" => %{}},
      %{"name" => "get_issue", "description" => "Get issue", "inputSchema" => %{}},
      %{"name" => "create_issue", "description" => "Create issue", "inputSchema" => %{}},
      %{"name" => "delete_repo", "description" => "Delete repo", "inputSchema" => %{}},
      %{"name" => "search_code", "description" => "Search code", "inputSchema" => %{}}
    ]
  end

  defp cli_deps(overrides \\ %{}) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, overrides)
  end

  defp cli_run(argv, deps \\ nil) do
    parsed = Main.parse_args(argv)
    Main.run(parsed, deps || cli_deps())
  end

  defp mcp_tools_for(server_name) do
    ToolRegistry.list_tools()
    |> Enum.filter(&(&1.extension == "mcp:#{server_name}"))
  end

  defp wait_for_status(client, expected, attempts \\ 20) do
    status = poll_status(client)

    cond do
      status == expected ->
        :ok

      attempts > 0 ->
        Process.sleep(50)
        wait_for_status(client, expected, attempts - 1)

      true ->
        flunk("Expected client status #{expected}, got #{status}")
    end
  end

  defp poll_status(client) do
    if Process.alive?(client) do
      {status, _reason} = Client.status(client)
      status
    else
      :dead
    end
  end

  # == AC2: Golden Path ==

  describe "golden path: add, connect, list, remove" do
    test "full lifecycle with CLI and real MCP client", %{supervisor: sup} do
      port_opener = make_port_opener()

      # 1. Init MCPClient extension with no servers
      MCPClient.init(config: %{mcp_servers: []}, supervisor: sup)

      # 2. Add server via CLI (DB operation)
      assert {:ok, %{server: %{name: "integ-server"}}} =
               Main.run({"mcp", ["add", "integ-server", "echo", "hello"], %{}}, cli_deps())

      assert {:ok, server} = Servers.get("integ-server")
      assert server.command == "echo"

      # 3. Reload server with test infrastructure (starts client)
      assert {:ok, client} =
               MCPClient.reload_server("integ-server",
                 port_opener: port_opener,
                 supervisor: sup
               )

      # 4. Complete handshake
      fake_port = receive_fake_port()
      complete_handshake(client, fake_port)
      wait_for_status(client, :connected)

      # 5. Verify tools registered in ToolRegistry
      tools = mcp_tools_for("integ-server")
      assert length(tools) == 2
      tool_names = Enum.map(tools, & &1.name) |> Enum.sort()
      assert tool_names == [:"integ-server__read_data", :"integ-server__write_data"]

      # 6. Dispatch a tool call and verify round-trip
      dispatch_task =
        Task.async(fn ->
          ToolRegistry.dispatch(:"integ-server__read_data", %{"query" => "test"})
        end)

      # The dispatch sends a tools/call JSON-RPC request to the fake port.
      # Wait for it to arrive, then respond.
      Process.sleep(100)
      sent = FakePort.get_sent(fake_port)
      call_request = sent |> List.last() |> Jason.decode!()
      assert call_request["method"] == "tools/call"
      assert call_request["params"]["name"] == "read_data"

      call_response =
        Protocol.encode_response(call_request["id"], %{
          "content" => [%{"type" => "text", "text" => "result data"}]
        })

      send_line(client, fake_port, call_response)
      result = Task.await(dispatch_task, 5_000)
      assert {:ok, %{"content" => [%{"text" => "result data"}]}} = result

      # 7. Verify `fam mcp list` shows connected status
      list_deps =
        cli_deps(%{
          list_mcp_servers_fn: fn ->
            {:ok, %{servers: MCPClient.server_status()}}
          end
        })

      assert {:ok, %{servers: servers}} = Main.run({"mcp", [], %{}}, list_deps)
      integ = Enum.find(servers, &(&1.name == "integ-server"))
      assert integ.status == :connected
      assert integ.tool_count == 2

      # 7. Remove server via CLI (DB deletion)
      assert {:ok, %{removed: "integ-server"}} =
               Main.run({"mcp", ["remove", "integ-server"], %{}}, cli_deps())

      assert {:error, :not_found} = Servers.get("integ-server")

      # The client may have been killed by the CLI's best_effort_reload
      # (which fires a real subprocess that dies). Ensure clean teardown
      # by manually unregistering any leftover tools.
      if Process.alive?(client) do
        DynamicSupervisor.terminate_child(sup, client)
      else
        # Client already dead — manually unregister tools
        for tool <- mcp_tools_for("integ-server") do
          ToolRegistry.unregister(tool.name)
        end
      end

      Process.sleep(50)
      assert mcp_tools_for("integ-server") == []
    end
  end

  # == AC3: Disable/Enable Cycle ==

  describe "disable/enable cycle" do
    test "disable tears down client, enable restarts it", %{supervisor: sup} do
      port_opener = make_port_opener()

      MCPClient.init(config: %{mcp_servers: []}, supervisor: sup)
      Main.run({"mcp", ["add", "toggle-srv", "echo"], %{}}, cli_deps())

      {:ok, client1} =
        MCPClient.reload_server("toggle-srv",
          port_opener: port_opener,
          supervisor: sup
        )

      fake_port1 = receive_fake_port()
      complete_handshake(client1, fake_port1)
      wait_for_status(client1, :connected)
      assert length(mcp_tools_for("toggle-srv")) == 2

      # Disable via CLI
      assert {:ok, %{disabled: "toggle-srv"}} =
               Main.run({"mcp", ["disable", "toggle-srv"], %{}}, cli_deps())

      # Clean up client and tools. In production, best_effort_reload
      # handles this via ClientSupervisor. In tests, the client is under
      # our test supervisor, so cleanup is explicit.
      if Process.alive?(client1) do
        DynamicSupervisor.terminate_child(sup, client1)
      else
        for tool <- mcp_tools_for("toggle-srv") do
          ToolRegistry.unregister(tool.name)
        end
      end

      Process.sleep(50)
      assert mcp_tools_for("toggle-srv") == []

      # Verify reload confirms disabled status
      assert {:error, :disabled} =
               MCPClient.reload_server("toggle-srv",
                 port_opener: port_opener,
                 supervisor: sup
               )

      # Enable via CLI
      assert {:ok, %{enabled: "toggle-srv"}} =
               Main.run({"mcp", ["enable", "toggle-srv"], %{}}, cli_deps())

      # Reload to restart client
      {:ok, client2} =
        MCPClient.reload_server("toggle-srv",
          port_opener: port_opener,
          supervisor: sup
        )

      fake_port2 = receive_fake_port()
      complete_handshake(client2, fake_port2)
      wait_for_status(client2, :connected)
      assert length(mcp_tools_for("toggle-srv")) == 2
    end
  end

  # == AC4: Config + DB Merge ==

  describe "config + DB merge" do
    test "DB wins on name collision, warning logged", %{supervisor: sup} do
      port_opener = make_port_opener()

      {:ok, _} =
        Servers.create(%{
          name: "shared-srv",
          command: "db-echo",
          args_json: "[]",
          env_json: "{}"
        })

      config = %{
        mcp_servers: [
          %{name: "shared-srv", command: "config-echo", args: [], env: %{}}
        ]
      }

      log =
        capture_log(fn ->
          MCPClient.init(
            config: config,
            port_opener: port_opener,
            supervisor: sup
          )
        end)

      assert log =~ "overridden by database"

      entries = :ets.lookup(:familiar_mcp_servers, "shared-srv")
      assert length(entries) == 1
      assert [{_, :db, _}] = entries

      # Remove DB server and re-init — config entry should appear
      {:ok, _} = Servers.delete("shared-srv")
      :ets.delete_all_objects(:familiar_mcp_servers)

      MCPClient.init(
        config: config,
        port_opener: port_opener,
        supervisor: sup
      )

      entries_after = :ets.lookup(:familiar_mcp_servers, "shared-srv")
      assert length(entries_after) == 1
      assert [{_, :config, _}] = entries_after
    end
  end

  # == AC5: Handshake Failure ==

  describe "handshake failure and recovery" do
    test "error response causes handshake_failed, reload recovers", %{supervisor: sup} do
      port_opener = make_port_opener()

      MCPClient.init(config: %{mcp_servers: []}, supervisor: sup)

      {:ok, _} =
        Servers.create(%{
          name: "fail-srv",
          command: "echo",
          args_json: "[]",
          env_json: "{}"
        })

      {:ok, client1} =
        MCPClient.reload_server("fail-srv",
          port_opener: port_opener,
          supervisor: sup
        )

      fake_port1 = receive_fake_port()

      # Send error response to initialize request
      error_response = Protocol.encode_error(1, -32_600, "Invalid request")
      send_line(client1, fake_port1, error_response)
      Process.sleep(100)

      {status, _reason} = Client.status(client1)
      assert status == :handshake_failed

      # Reload to retry — this time complete handshake
      {:ok, client2} =
        MCPClient.reload_server("fail-srv",
          port_opener: port_opener,
          supervisor: sup
        )

      fake_port2 = receive_fake_port()
      complete_handshake(client2, fake_port2)
      wait_for_status(client2, :connected)
      assert length(mcp_tools_for("fail-srv")) == 2
    end
  end

  # == AC6: Read-Only Filtering ==

  describe "read-only filtering" do
    test "only read-prefixed tools registered for read_only server", %{supervisor: sup} do
      port_opener = make_port_opener()

      MCPClient.init(config: %{mcp_servers: []}, supervisor: sup)

      {:ok, _} =
        Servers.create(%{
          name: "ro-srv",
          command: "echo",
          args_json: "[]",
          env_json: "{}",
          read_only: true
        })

      {:ok, client} =
        MCPClient.reload_server("ro-srv",
          port_opener: port_opener,
          supervisor: sup
        )

      fake_port = receive_fake_port()
      complete_handshake_with_tools(client, fake_port, mixed_tools())
      wait_for_status(client, :connected)

      tools = mcp_tools_for("ro-srv")
      tool_names = Enum.map(tools, & &1.name) |> Enum.sort()

      assert :"ro-srv__list_repos" in tool_names
      assert :"ro-srv__get_issue" in tool_names
      assert :"ro-srv__search_code" in tool_names

      refute :"ro-srv__create_issue" in tool_names
      refute :"ro-srv__delete_repo" in tool_names

      assert length(tools) == 3
    end
  end

  # == AC7: Literal-Secret Warning ==

  describe "literal-secret warning" do
    test "warns when env value is a literal (no $ reference)" do
      output =
        capture_io(:stderr, fn ->
          cli_run(["mcp", "add", "secret-srv", "echo", "--env", "TOKEN=ghp_abc123"])
        end)

      assert output =~ "TOKEN"
      assert output =~ "literal value"

      assert {:ok, _} = Servers.get("secret-srv")
    end
  end

  # == AC8: CLI Flag Coverage ==

  describe "CLI flag coverage" do
    test "add with --disabled creates disabled server" do
      assert {:ok, %{server: _}} =
               cli_run(["mcp", "add", "dis-srv", "echo", "--disabled"])

      assert {:ok, server} = Servers.get("dis-srv")
      assert server.disabled == true
    end

    test "add with --read-only creates read_only server" do
      assert {:ok, %{server: _}} =
               cli_run(["mcp", "add", "ro-flag-srv", "echo", "--read-only"])

      assert {:ok, server} = Servers.get("ro-flag-srv")
      assert server.read_only == true
    end

    test "get with --show-env includes env values" do
      cli_run(["mcp", "add", "env-srv", "echo", "--env", "KEY=value"])

      result = cli_run(["mcp", "get", "env-srv", "--show-env"])

      assert {:ok, %{server: detail}} = result
      assert detail.env["KEY"] == "value"
    end
  end
end
