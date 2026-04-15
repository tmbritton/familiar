defmodule Familiar.MCP.ServersTest do
  use Familiar.DataCase, async: true

  alias Familiar.MCP.Server
  alias Familiar.MCP.Servers

  # Stub registry for changeset validation
  defmodule FakeRegistry do
    def list_tools, do: []
  end

  setup do
    Application.put_env(:familiar, :tool_registry, FakeRegistry)

    on_exit(fn ->
      Application.delete_env(:familiar, :tool_registry)
    end)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{name: "test-server", command: "npx", args_json: ~s(["--flag"]), env_json: ~s({"K":"V"})},
      overrides
    )
  end

  describe "create/1" do
    test "inserts a valid server" do
      assert {:ok, %Server{} = server} = Servers.create(valid_attrs())
      assert server.name == "test-server"
      assert server.command == "npx"
      assert server.args_json == ~s(["--flag"])
      assert server.env_json == ~s({"K":"V"})
      assert server.disabled == false
      assert server.read_only == false
    end

    test "returns error changeset for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Servers.create(%{name: ""})
    end

    test "enforces unique name constraint" do
      assert {:ok, _} = Servers.create(valid_attrs())
      assert {:error, cs} = Servers.create(valid_attrs())
      assert {"has already been taken", _} = cs.errors[:name]
    end
  end

  describe "list/0" do
    test "returns empty list when no servers" do
      assert Servers.list() == []
    end

    test "returns servers ordered by name" do
      {:ok, _} = Servers.create(valid_attrs(%{name: "zeta"}))
      {:ok, _} = Servers.create(valid_attrs(%{name: "alpha"}))
      {:ok, _} = Servers.create(valid_attrs(%{name: "mid"}))

      names = Servers.list() |> Enum.map(& &1.name)
      assert names == ["alpha", "mid", "zeta"]
    end
  end

  describe "get/1" do
    test "returns server by name" do
      {:ok, created} = Servers.create(valid_attrs())
      assert {:ok, server} = Servers.get("test-server")
      assert server.id == created.id
    end

    test "returns not_found for missing server" do
      assert {:error, :not_found} = Servers.get("nonexistent")
    end
  end

  describe "update/2" do
    test "updates server attributes" do
      {:ok, _} = Servers.create(valid_attrs())
      assert {:ok, updated} = Servers.update("test-server", %{command: "/usr/bin/node"})
      assert updated.command == "/usr/bin/node"
    end

    test "returns not_found for missing server" do
      assert {:error, :not_found} = Servers.update("nonexistent", %{command: "foo"})
    end

    test "returns error changeset for invalid update" do
      {:ok, _} = Servers.create(valid_attrs())
      assert {:error, %Ecto.Changeset{}} = Servers.update("test-server", %{args_json: "bad"})
    end
  end

  describe "delete/1" do
    test "deletes existing server" do
      {:ok, _} = Servers.create(valid_attrs())
      assert {:ok, _} = Servers.delete("test-server")
      assert {:error, :not_found} = Servers.get("test-server")
    end

    test "returns not_found for missing server" do
      assert {:error, :not_found} = Servers.delete("nonexistent")
    end
  end

  describe "enable/1 and disable/1" do
    test "disable sets disabled to true" do
      {:ok, _} = Servers.create(valid_attrs())
      assert {:ok, server} = Servers.disable("test-server")
      assert server.disabled == true
    end

    test "enable sets disabled to false" do
      {:ok, _} = Servers.create(valid_attrs(%{disabled: true}))
      assert {:ok, server} = Servers.enable("test-server")
      assert server.disabled == false
    end

    test "enable returns not_found for missing server" do
      assert {:error, :not_found} = Servers.enable("nonexistent")
    end

    test "disable returns not_found for missing server" do
      assert {:error, :not_found} = Servers.disable("nonexistent")
    end
  end
end
