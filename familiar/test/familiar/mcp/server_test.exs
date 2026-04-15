defmodule Familiar.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Familiar.MCP.Server

  # Stub registry that returns a known list of built-in tools
  defmodule FakeRegistry do
    def list_tools do
      [
        %{name: :read_file, description: "Read a file", extension: "builtin"},
        %{name: :write_file, description: "Write a file", extension: "builtin"}
      ]
    end
  end

  setup do
    Application.put_env(:familiar, :tool_registry, FakeRegistry)

    on_exit(fn ->
      Application.delete_env(:familiar, :tool_registry)
    end)
  end

  describe "changeset/2 valid inputs" do
    test "accepts valid server attributes" do
      cs = Server.changeset(%Server{}, %{name: "github", command: "npx"})
      assert cs.valid?
    end

    test "accepts name with hyphens and underscores" do
      cs = Server.changeset(%Server{}, %{name: "my-mcp-server", command: "/usr/bin/node"})
      assert cs.valid?
    end

    test "accepts name with digits" do
      cs = Server.changeset(%Server{}, %{name: "server2", command: "python3"})
      assert cs.valid?
    end

    test "accepts valid args_json" do
      cs =
        Server.changeset(%Server{}, %{
          name: "test",
          command: "npx",
          args_json: ~s(["--flag", "value"])
        })

      assert cs.valid?
    end

    test "accepts valid env_json" do
      cs =
        Server.changeset(%Server{}, %{
          name: "test",
          command: "npx",
          env_json: ~s({"TOKEN": "${MY_TOKEN}"})
        })

      assert cs.valid?
    end

    test "defaults args_json to empty array" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx"})
      assert Ecto.Changeset.get_field(cs, :args_json) == "[]"
    end

    test "defaults env_json to empty object" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx"})
      assert Ecto.Changeset.get_field(cs, :env_json) == "{}"
    end

    test "defaults disabled to false" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx"})
      assert Ecto.Changeset.get_field(cs, :disabled) == false
    end

    test "defaults read_only to false" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx"})
      assert Ecto.Changeset.get_field(cs, :read_only) == false
    end

    test "accepts read_only flag" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx", read_only: true})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :read_only) == true
    end
  end

  describe "changeset/2 name validation" do
    test "rejects missing name" do
      cs = Server.changeset(%Server{}, %{command: "npx"})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:name]
    end

    test "rejects name starting with digit" do
      cs = Server.changeset(%Server{}, %{name: "1bad", command: "npx"})
      refute cs.valid?
      assert {msg, _} = cs.errors[:name]
      assert msg =~ "must start with a lowercase letter"
    end

    test "rejects name with uppercase" do
      cs = Server.changeset(%Server{}, %{name: "BadName", command: "npx"})
      refute cs.valid?
    end

    test "rejects name with spaces" do
      cs = Server.changeset(%Server{}, %{name: "bad name", command: "npx"})
      refute cs.valid?
    end

    test "rejects fam_ prefix" do
      cs = Server.changeset(%Server{}, %{name: "fam_builtin", command: "npx"})
      refute cs.valid?
      assert {msg, _} = cs.errors[:name]
      assert msg =~ "fam_"
    end

    test "rejects name colliding with built-in tool" do
      cs = Server.changeset(%Server{}, %{name: "read_file", command: "npx"})
      refute cs.valid?
      assert {msg, _} = cs.errors[:name]
      assert msg =~ "collides with built-in tool"
    end

    test "accepts name that doesn't collide" do
      cs = Server.changeset(%Server{}, %{name: "github", command: "npx"})
      assert cs.valid?
    end
  end

  describe "changeset/2 command validation" do
    test "rejects missing command" do
      cs = Server.changeset(%Server{}, %{name: "test"})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:command]
    end
  end

  describe "changeset/2 JSON field validation" do
    test "rejects invalid args_json" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx", args_json: "not json"})
      refute cs.valid?
      assert {msg, _} = cs.errors[:args_json]
      assert msg =~ "valid JSON array"
    end

    test "rejects invalid env_json" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx", env_json: "{bad"})
      refute cs.valid?
      assert {msg, _} = cs.errors[:env_json]
      assert msg =~ "valid JSON object"
    end

    test "rejects args_json that is a JSON object instead of array" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx", args_json: ~s({"k":"v"})})
      refute cs.valid?
      assert {msg, _} = cs.errors[:args_json]
      assert msg =~ "valid JSON array"
    end

    test "rejects env_json that is a JSON array instead of object" do
      cs = Server.changeset(%Server{}, %{name: "test", command: "npx", env_json: ~s(["a","b"])})
      refute cs.valid?
      assert {msg, _} = cs.errors[:env_json]
      assert msg =~ "valid JSON object"
    end
  end
end
