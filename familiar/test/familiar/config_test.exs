defmodule Familiar.ConfigTest do
  use ExUnit.Case, async: true

  alias Familiar.Config

  @moduletag :tmp_dir

  describe "defaults/0" do
    test "returns default config with all sections" do
      config = Config.defaults()

      assert config.provider.base_url == "http://localhost:11434"
      assert config.provider.chat_model == "llama3.2"
      assert config.provider.embedding_model == "nomic-embed-text"
      assert config.provider.timeout == 120

      assert config.scan.max_files == 200
      assert config.scan.large_project_threshold == 500

      assert config.notifications.provider == "auto"
      assert config.notifications.enabled == true
    end
  end

  describe "load/1" do
    test "returns defaults when file does not exist", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nonexistent.toml")
      assert {:ok, config} = Config.load(path)
      assert config == Config.defaults()
    end

    test "parses valid TOML with all sections", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [provider]
      base_url = "http://custom:8080"
      chat_model = "mistral"
      embedding_model = "custom-embed"
      timeout = 60

      [scan]
      max_files = 100
      large_project_threshold = 300

      [notifications]
      provider = "notify-send"
      enabled = false
      """)

      assert {:ok, config} = Config.load(path)
      assert config.provider.base_url == "http://custom:8080"
      assert config.provider.chat_model == "mistral"
      assert config.provider.timeout == 60
      assert config.scan.max_files == 100
      assert config.notifications.provider == "notify-send"
      assert config.notifications.enabled == false
    end

    test "merges partial config with defaults", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [provider]
      chat_model = "codellama"
      """)

      assert {:ok, config} = Config.load(path)
      # Overridden value
      assert config.provider.chat_model == "codellama"
      # Defaults preserved
      assert config.provider.base_url == "http://localhost:11434"
      assert config.provider.timeout == 120
      assert config.scan.max_files == 200
      assert config.notifications.enabled == true
    end

    test "returns error for invalid TOML syntax", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")
      File.write!(path, "this is [not valid toml ===")

      assert {:error, {:invalid_config, details}} = Config.load(path)
      assert details.field == "file"
      assert is_binary(details.reason)
    end

    test "validates timeout must be positive integer", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [provider]
      timeout = -5
      """)

      assert {:error, {:invalid_config, details}} = Config.load(path)
      assert details.field == "provider.timeout"
    end

    test "validates max_files must be positive integer", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [scan]
      max_files = 0
      """)

      assert {:error, {:invalid_config, details}} = Config.load(path)
      assert details.field == "scan.max_files"
    end

    test "validates notifications.enabled must be boolean", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [notifications]
      enabled = "yes"
      """)

      assert {:error, {:invalid_config, details}} = Config.load(path)
      assert details.field == "notifications.enabled"
    end

    test "validates provider.base_url must be a string", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [provider]
      base_url = 123
      """)

      assert {:error, {:invalid_config, details}} = Config.load(path)
      assert details.field == "provider.base_url"
    end

    test "handles empty config file as defaults", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")
      File.write!(path, "")

      assert {:ok, config} = Config.load(path)
      assert config == Config.defaults()
    end
  end

  describe "MCP server config parsing" do
    test "parses [[mcp.servers]] entries", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [[mcp.servers]]
      name = "github"
      command = "npx"
      args = ["-y", "@modelcontextprotocol/server-github"]

      [mcp.servers.env]
      GITHUB_TOKEN = "${GITHUB_TOKEN}"

      [[mcp.servers]]
      name = "postgres"
      command = "pg-server"
      """)

      assert {:ok, config} = Config.load(path)
      assert length(config.mcp_servers) == 2

      [github, postgres] = config.mcp_servers
      assert github.name == "github"
      assert github.command == "npx"
      assert github.args == ["-y", "@modelcontextprotocol/server-github"]
      assert github.env["GITHUB_TOKEN"] == "${GITHUB_TOKEN}"

      assert postgres.name == "postgres"
      assert postgres.command == "pg-server"
      assert postgres.args == []
      assert postgres.env == %{}
    end

    test "defaults mcp_servers to empty list when no mcp section", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")
      File.write!(path, "[provider]\nbase_url = \"http://localhost:11434\"\n")

      assert {:ok, config} = Config.load(path)
      assert config.mcp_servers == []
    end

    test "skips mcp server entry without name and keeps valid entries", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [[mcp.servers]]
      command = "npx"

      [[mcp.servers]]
      name = "valid"
      command = "echo"
      """)

      assert {:ok, config} = Config.load(path)
      assert length(config.mcp_servers) == 1
      assert hd(config.mcp_servers).name == "valid"
    end

    test "skips mcp server entry without command and keeps valid entries", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")

      File.write!(path, """
      [[mcp.servers]]
      name = "bad"

      [[mcp.servers]]
      name = "good"
      command = "echo"
      """)

      assert {:ok, config} = Config.load(path)
      assert length(config.mcp_servers) == 1
      assert hd(config.mcp_servers).name == "good"
    end

    test "handles mcp section with no servers key", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.toml")
      File.write!(path, "[mcp]\nsome_key = \"value\"\n")

      assert {:ok, config} = Config.load(path)
      assert config.mcp_servers == []
    end
  end
end
