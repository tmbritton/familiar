defmodule Familiar.CLI.MCPCommandTest do
  use Familiar.DataCase, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths
  alias Familiar.MCP.Servers

  # Stub registry for changeset validation
  defmodule FakeRegistry do
    def list_tools, do: []
  end

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :tool_registry, FakeRegistry)
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()

    on_exit(fn ->
      Application.delete_env(:familiar, :tool_registry)
      Application.delete_env(:familiar, :project_dir)
    end)
  end

  defp deps(overrides \\ %{}) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, overrides)
  end

  defp create_server(name, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: name, command: "echo", args_json: "[]", env_json: "{}"},
        overrides
      )

    {:ok, server} = Servers.create(attrs)
    server
  end

  # == fam mcp list ==

  describe "fam mcp list" do
    test "returns empty list when no servers" do
      d = deps(%{list_mcp_servers_fn: fn -> {:ok, %{servers: []}} end})
      assert {:ok, %{servers: []}} = Main.run({"mcp", [], %{}}, d)
    end

    test "returns servers when present" do
      servers = [%{name: "github", source: :db, status: :connected, tool_count: 3}]
      d = deps(%{list_mcp_servers_fn: fn -> {:ok, %{servers: servers}} end})
      assert {:ok, %{servers: ^servers}} = Main.run({"mcp", [], %{}}, d)
    end

    test "list subcommand also works" do
      d = deps(%{list_mcp_servers_fn: fn -> {:ok, %{servers: []}} end})
      assert {:ok, %{servers: []}} = Main.run({"mcp", ["list"], %{}}, d)
    end
  end

  # == fam mcp get ==

  describe "fam mcp get" do
    test "returns server details" do
      detail = %{name: "github", command: "npx", source: :db, status: :connected}
      d = deps(%{get_mcp_server_fn: fn _name, _opts -> {:ok, %{server: detail}} end})
      assert {:ok, %{server: ^detail}} = Main.run({"mcp", ["get", "github"], %{}}, d)
    end

    test "returns not_found error" do
      d =
        deps(%{
          get_mcp_server_fn: fn name, _opts ->
            {:error, {:mcp_server_not_found, %{name: name}}}
          end
        })

      assert {:error, {:mcp_server_not_found, %{name: "nope"}}} =
               Main.run({"mcp", ["get", "nope"], %{}}, d)
    end
  end

  # == fam mcp add ==

  describe "fam mcp add" do
    test "creates server with valid attrs" do
      d =
        deps(%{
          add_mcp_server_fn: fn attrs, _flags ->
            {:ok, %{server: %{name: attrs.name, command: attrs.command}}}
          end
        })

      assert {:ok, %{server: %{name: "test", command: "echo"}}} =
               Main.run({"mcp", ["add", "test", "echo"], %{}}, d)
    end

    test "returns error for invalid name" do
      d =
        deps(%{
          add_mcp_server_fn: fn _attrs, _flags ->
            {:error, {:mcp_server_invalid_name, %{reason: "bad format"}}}
          end
        })

      assert {:error, {:mcp_server_invalid_name, _}} =
               Main.run({"mcp", ["add", "BAD", "echo"], %{}}, d)
    end

    test "returns usage error when command is missing" do
      assert {:error, {:usage_error, _}} =
               Main.run({"mcp", ["add", "test"], %{}}, deps())
    end

    test "creates server via default path with DB" do
      result = Main.run({"mcp", ["add", "myserver", "echo", "hello"], %{}}, deps())
      assert {:ok, %{server: %{name: "myserver", command: "echo"}}} = result
      assert {:ok, _} = Servers.get("myserver")
    end

    test "returns name_taken for duplicate" do
      create_server("dupe")
      result = Main.run({"mcp", ["add", "dupe", "echo"], %{}}, deps())
      assert {:error, {:mcp_server_name_taken, %{name: "dupe"}}} = result
    end

    test "returns reserved_prefix for fam_ name" do
      result = Main.run({"mcp", ["add", "fam_bad", "echo"], %{}}, deps())
      assert {:error, {:mcp_server_reserved_prefix, %{name: "fam_bad"}}} = result
    end
  end

  # == fam mcp add-json ==

  describe "fam mcp add-json" do
    test "creates server from valid JSON" do
      json = Jason.encode!(%{command: "npx", args: ["-y", "server"], env: %{"K" => "V"}})

      d =
        deps(%{
          add_mcp_json_fn: fn _name, _json ->
            {:ok, %{server: %{name: "from-json", command: "npx"}}}
          end
        })

      assert {:ok, %{server: _}} = Main.run({"mcp", ["add-json", "from-json", json], %{}}, d)
    end

    test "returns error for invalid JSON" do
      d =
        deps(%{
          add_mcp_json_fn: fn _name, _json ->
            {:error, {:mcp_server_invalid_json, %{reason: "parse error"}}}
          end
        })

      assert {:error, {:mcp_server_invalid_json, _}} =
               Main.run({"mcp", ["add-json", "test", "not-json"], %{}}, d)
    end

    test "default path rejects bad JSON" do
      result = Main.run({"mcp", ["add-json", "test", "{bad"], %{}}, deps())
      assert {:error, {:mcp_server_invalid_json, _}} = result
    end

    test "default path rejects JSON without command" do
      result = Main.run({"mcp", ["add-json", "test", ~s({"args": []})], %{}}, deps())

      assert {:error, {:mcp_server_invalid_json, %{reason: "missing required field: command"}}} =
               result
    end

    test "default path creates server" do
      json = Jason.encode!(%{command: "echo", args: ["hi"], env: %{}})
      result = Main.run({"mcp", ["add-json", "jsonserver", json], %{}}, deps())
      assert {:ok, %{server: %{name: "jsonserver"}}} = result
      assert {:ok, _} = Servers.get("jsonserver")
    end
  end

  # == fam mcp remove ==

  describe "fam mcp remove" do
    test "removes existing DB server" do
      d = deps(%{remove_mcp_server_fn: fn name -> {:ok, %{removed: name}} end})
      assert {:ok, %{removed: "github"}} = Main.run({"mcp", ["remove", "github"], %{}}, d)
    end

    test "returns not_found for missing server" do
      d =
        deps(%{
          remove_mcp_server_fn: fn name ->
            {:error, {:mcp_server_not_found, %{name: name}}}
          end
        })

      assert {:error, {:mcp_server_not_found, _}} =
               Main.run({"mcp", ["remove", "nope"], %{}}, d)
    end

    test "default path removes DB server" do
      create_server("removeme")
      result = Main.run({"mcp", ["remove", "removeme"], %{}}, deps())
      assert {:ok, %{removed: "removeme"}} = result
      assert {:error, :not_found} = Servers.get("removeme")
    end

    test "default path returns not_found for missing" do
      result = Main.run({"mcp", ["remove", "ghost"], %{}}, deps())
      assert {:error, {:mcp_server_not_found, %{name: "ghost"}}} = result
    end
  end

  # == fam mcp enable/disable ==

  describe "fam mcp enable/disable" do
    test "enables existing DB server" do
      d = deps(%{toggle_mcp_server_fn: fn name, _action -> {:ok, %{enabled: name}} end})
      assert {:ok, %{enabled: "test"}} = Main.run({"mcp", ["enable", "test"], %{}}, d)
    end

    test "disables existing DB server" do
      d = deps(%{toggle_mcp_server_fn: fn name, _action -> {:ok, %{disabled: name}} end})
      assert {:ok, %{disabled: "test"}} = Main.run({"mcp", ["disable", "test"], %{}}, d)
    end

    test "returns not_found for missing server" do
      d =
        deps(%{
          toggle_mcp_server_fn: fn name, _action ->
            {:error, {:mcp_server_not_found, %{name: name}}}
          end
        })

      assert {:error, {:mcp_server_not_found, _}} =
               Main.run({"mcp", ["enable", "nope"], %{}}, d)
    end

    test "default path disables DB server" do
      create_server("toggle-test")
      result = Main.run({"mcp", ["disable", "toggle-test"], %{}}, deps())
      assert {:ok, %{disabled: "toggle-test"}} = result
      assert {:ok, server} = Servers.get("toggle-test")
      assert server.disabled == true
    end

    test "default path enables DB server" do
      create_server("toggle-test2", %{disabled: true})
      result = Main.run({"mcp", ["enable", "toggle-test2"], %{}}, deps())
      assert {:ok, %{enabled: "toggle-test2"}} = result
      assert {:ok, server} = Servers.get("toggle-test2")
      assert server.disabled == false
    end

    test "default path returns not_found for missing" do
      result = Main.run({"mcp", ["enable", "ghost"], %{}}, deps())
      assert {:error, {:mcp_server_not_found, %{name: "ghost"}}} = result
    end
  end

  # == missing name argument ==

  describe "missing name argument" do
    test "get without name returns usage error" do
      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"mcp", ["get"], %{}}, deps())

      assert msg =~ "get <name>"
    end

    test "remove without name returns usage error" do
      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"mcp", ["remove"], %{}}, deps())

      assert msg =~ "remove <name>"
    end

    test "enable without name returns usage error" do
      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"mcp", ["enable"], %{}}, deps())

      assert msg =~ "enable <name>"
    end

    test "disable without name returns usage error" do
      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"mcp", ["disable"], %{}}, deps())

      assert msg =~ "disable <name>"
    end
  end

  # == unknown subcommand ==

  describe "unknown mcp subcommand" do
    test "returns usage error" do
      assert {:error, {:usage_error, _}} =
               Main.run({"mcp", ["bogus"], %{}}, deps())
    end
  end
end
