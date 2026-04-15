defmodule Familiar.MCP.ClientTest do
  # async: false — Client registers tools in the global ToolRegistry
  # during handshake, which races with other test modules.
  use ExUnit.Case, async: false

  alias Familiar.MCP.Client
  alias Familiar.MCP.Protocol
  alias Familiar.Test.FakeMCPServer
  alias Familiar.Test.FakeMCPServer.FakePort

  defdelegate send_line(client, fake_port, json), to: FakeMCPServer
  defdelegate send_exit(client, fake_port, code), to: FakeMCPServer
  defdelegate complete_handshake(client, fake_port), to: FakeMCPServer

  defp start_client(opts \\ []) do
    {:ok, fake_port} = FakePort.start_link()

    port_opener = fn _cmd, _args, _env ->
      send_fn = fn data -> send(fake_port, {:port_data, data}) end
      close_fn = fn -> :ok end
      {fake_port, send_fn, close_fn}
    end

    default_opts = [
      server_name: "test_server",
      command: "echo",
      port_opener: port_opener,
      connect_timeout: 5_000,
      call_timeout: 5_000
    ]

    merged_opts = Keyword.merge(default_opts, opts)
    {:ok, client} = Client.start_link(merged_opts)

    # Wait for handle_continue to fire and send initialize
    Process.sleep(50)

    {client, fake_port}
  end

  describe "init/1" do
    test "starts in :connecting state" do
      {client, _fake_port} = start_client()
      assert {:connecting, "initializing"} = Client.status(client)
    end

    test "sends initialize request on startup" do
      {_client, fake_port} = start_client()
      sent = FakePort.get_sent(fake_port)
      assert length(sent) == 1
      {:ok, {:request, 1, "initialize", params}} = Protocol.decode(hd(sent))
      assert params["protocolVersion"] == "2025-11-05"
      assert params["clientInfo"]["name"] == "familiar"
    end
  end

  describe "handshake flow" do
    test "transitions to :connected after successful handshake" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)
      assert {:connected, "ready"} = Client.status(client)
    end

    test "sends initialized notification and tools/list after init response" do
      {client, fake_port} = start_client()

      init_response =
        Protocol.encode_response(1, %{
          "protocolVersion" => "2025-11-05",
          "capabilities" => %{},
          "serverInfo" => %{"name" => "test", "version" => "1.0"}
        })

      send_line(client, fake_port, init_response)

      sent = FakePort.get_sent(fake_port)
      # Should have: initialize request, initialized notification, tools/list request
      assert length(sent) == 3

      {:ok, {:notification, "notifications/initialized", _}} = Protocol.decode(Enum.at(sent, 1))
      {:ok, {:request, 2, "tools/list", _}} = Protocol.decode(Enum.at(sent, 2))
    end

    test "transitions to :handshake_failed on initialize error" do
      {client, fake_port} = start_client()

      error_response = Protocol.encode_error(1, -32_600, "Unsupported protocol version")
      send_line(client, fake_port, error_response)

      assert {:handshake_failed, reason} = Client.status(client)
      assert reason =~ "initialize error"
    end

    test "handles empty tools list" do
      {client, fake_port} = start_client()

      init_response =
        Protocol.encode_response(1, %{
          "protocolVersion" => "2025-11-05",
          "capabilities" => %{},
          "serverInfo" => %{"name" => "empty-server", "version" => "1.0"}
        })

      send_line(client, fake_port, init_response)

      tools_response = Protocol.encode_response(2, %{"tools" => []})
      send_line(client, fake_port, tools_response)

      assert {:connected, "ready"} = Client.status(client)
    end
  end

  describe "tool calls" do
    test "returns error when not connected" do
      {client, _fake_port} = start_client()

      assert {:error, :tool_not_yet_available, msg} = Client.call_tool(client, "read_data", %{})
      assert msg =~ "test_server"
      assert msg =~ "connecting"
    end

    test "sends tools/call request and returns response" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "read_data", %{"query" => "test"})
        send(caller, {:call_result, result})
      end)

      Process.sleep(100)

      call_response =
        Protocol.encode_response(3, %{
          "content" => [%{"type" => "text", "text" => "hello world"}]
        })

      send_line(client, fake_port, call_response)

      assert_receive {:call_result, {:ok, result}}, 5_000
      assert result["content"] == [%{"type" => "text", "text" => "hello world"}]
    end

    test "sends correct tools/call JSON-RPC request" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "read_data", %{"path" => "/tmp/foo"})
        send(caller, {:call_result, result})
      end)

      Process.sleep(100)

      sent = FakePort.get_sent(fake_port)
      last = List.last(sent)
      {:ok, {:request, 3, "tools/call", params}} = Protocol.decode(last)
      assert params["name"] == "read_data"
      assert params["arguments"] == %{"path" => "/tmp/foo"}

      # Clean up
      send_line(client, fake_port, Protocol.encode_response(3, %{}))
      assert_receive {:call_result, _}, 5_000
    end

    test "returns error response from server" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "bad_tool", %{})
        send(caller, {:call_result, result})
      end)

      Process.sleep(100)

      error_response = Protocol.encode_error(3, -32_602, "Invalid parameters")
      send_line(client, fake_port, error_response)

      assert_receive {:call_result, {:error, :mcp_error, "Invalid parameters"}}, 5_000
    end

    test "handles multiple concurrent tool calls" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "tool_a", %{})
        send(caller, {:result_a, result})
      end)

      spawn(fn ->
        result = Client.call_tool(client, "tool_b", %{})
        send(caller, {:result_b, result})
      end)

      Process.sleep(100)

      send_line(client, fake_port, Protocol.encode_response(3, %{"a" => true}))
      send_line(client, fake_port, Protocol.encode_response(4, %{"b" => true}))

      assert_receive {:result_a, {:ok, %{"a" => true}}}, 5_000
      assert_receive {:result_b, {:ok, %{"b" => true}}}, 5_000
    end
  end

  describe "status state machine" do
    test "starts as :connecting" do
      {client, _} = start_client()
      assert {:connecting, _} = Client.status(client)
    end

    test "transitions to :connected on success" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)
      assert {:connected, "ready"} = Client.status(client)
    end

    test "transitions to :handshake_failed on error" do
      {client, fake_port} = start_client()
      error = Protocol.encode_error(1, -32_600, "bad version")
      send_line(client, fake_port, error)
      assert {:handshake_failed, _} = Client.status(client)
    end

    test "transitions to :crashed on port exit" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      send_exit(client, fake_port, 1)

      assert {:crashed, "exit code 1"} = Client.status(client)
    end
  end

  describe "port crash handling" do
    test "cleans up pending calls on crash" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "slow_tool", %{})
        send(caller, {:call_result, result})
      end)

      Process.sleep(100)

      send_exit(client, fake_port, 137)

      assert_receive {:call_result, {:error, :mcp_server_crashed, msg}}, 5_000
      assert msg =~ "137"
      assert {:crashed, _} = Client.status(client)
    end

    test "port exit during handshake" do
      {client, fake_port} = start_client()
      send_exit(client, fake_port, 1)
      assert {:crashed, "exit code 1"} = Client.status(client)
    end
  end

  describe "timeouts" do
    test "handshake timeout transitions to :handshake_failed" do
      {client, _fake_port} = start_client(connect_timeout: 100)

      Process.sleep(200)

      assert {:handshake_failed, reason} = Client.status(client)
      assert reason =~ "timeout"
    end

    test "tool call timeout returns error" do
      {client, fake_port} = start_client(call_timeout: 100)
      complete_handshake(client, fake_port)

      caller = self()

      spawn(fn ->
        result = Client.call_tool(client, "slow_tool", %{}, 100)
        send(caller, {:call_result, result})
      end)

      assert_receive {:call_result, {:error, :timeout, msg}}, 5_000
      assert msg =~ "timed out"
    end
  end

  describe "graceful shutdown" do
    test "does not send any notification on terminate (just closes transport)" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      GenServer.stop(client, :normal)
      Process.sleep(50)

      sent = FakePort.get_sent(fake_port)
      # Last message should be tools/list request (id=2), not a notification
      last = List.last(sent)
      {:ok, {:request, 2, "tools/list", _}} = Protocol.decode(last)
    end

    test "client process stops cleanly" do
      {client, fake_port} = start_client()
      complete_handshake(client, fake_port)

      GenServer.stop(client, :normal)
      Process.sleep(50)

      refute Process.alive?(client)
    end
  end

  describe "line buffering" do
    test "handles partial lines (noeol + eol)" do
      {client, fake_port} = start_client()

      json =
        Protocol.encode_response(1, %{
          "protocolVersion" => "2025-11-05",
          "capabilities" => %{},
          "serverInfo" => %{"name" => "test", "version" => "1.0"}
        })

      half = binary_part(json, 0, div(byte_size(json), 2))
      rest = binary_part(json, div(byte_size(json), 2), byte_size(json) - div(byte_size(json), 2))

      send(client, {fake_port, {:data, {:noeol, half}}})
      Process.sleep(20)
      send(client, {fake_port, {:data, {:eol, rest}}})
      Process.sleep(100)

      # After init response, client sends initialized notification + tools/list
      sent = FakePort.get_sent(fake_port)
      assert length(sent) == 3
    end

    test "ignores empty lines" do
      {client, fake_port} = start_client()
      send(client, {fake_port, {:data, {:eol, ""}}})
      Process.sleep(50)
      assert {:connecting, _} = Client.status(client)
    end
  end

  describe "expand_env" do
    test "expands ${VAR} in env values" do
      System.put_env("TEST_MCP_TOKEN", "secret123")
      on_exit(fn -> System.delete_env("TEST_MCP_TOKEN") end)

      assert Familiar.Config.expand_env("Bearer ${TEST_MCP_TOKEN}") == "Bearer secret123"
    end

    test "returns nil unchanged" do
      assert Familiar.Config.expand_env(nil) == nil
    end

    test "returns non-string unchanged" do
      assert Familiar.Config.expand_env(42) == 42
    end

    test "replaces missing vars with empty string" do
      assert Familiar.Config.expand_env("${NONEXISTENT_VAR_XYZ}") == ""
    end
  end
end
