defmodule Familiar.Execution.ToolSchemasTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Familiar.Execution.ToolSchemas
  alias Familiar.Knowledge.DefaultFiles

  @expected_tools ~w(
    read_file write_file delete_file list_files search_files
    run_command spawn_agent run_workflow
    monitor_agents broadcast_status signal_ready
    search_context store_context
  )

  setup do
    ToolSchemas.load_defaults()

    on_exit(fn ->
      try do
        :persistent_term.erase({ToolSchemas, :schemas})
      rescue
        ArgumentError -> :ok
      end
    end)

    :ok
  end

  describe "parse_toml/1" do
    test "parses a simple tool with one required param" do
      toml = """
      name = "read_file"
      description = "Read the contents of a file at the given path"

      [parameters]
      type = "object"
      required = ["path"]

      [parameters.properties.path]
      type = "string"
      description = "Absolute or relative file path to read"
      """

      assert {:ok, schema} = ToolSchemas.parse_toml(toml)
      assert schema.description == "Read the contents of a file at the given path"
      assert schema.parameters["type"] == "object"
      assert schema.parameters["required"] == ["path"]
      assert schema.parameters["properties"]["path"]["type"] == "string"
    end

    test "parses a tool with multiple required params" do
      toml = """
      name = "write_file"
      description = "Write content to a file at the given path"

      [parameters]
      type = "object"
      required = ["path", "content"]

      [parameters.properties.path]
      type = "string"
      description = "File path to write to"

      [parameters.properties.content]
      type = "string"
      description = "Content to write"
      """

      assert {:ok, schema} = ToolSchemas.parse_toml(toml)
      assert schema.parameters["required"] == ["path", "content"]
      assert map_size(schema.parameters["properties"]) == 2
    end

    test "parses a tool with optional params (no required key)" do
      toml = """
      name = "list_files"
      description = "List files in a directory"

      [parameters]
      type = "object"

      [parameters.properties.path]
      type = "string"
      description = "Directory path to list (defaults to project root)"
      """

      assert {:ok, schema} = ToolSchemas.parse_toml(toml)
      refute Map.has_key?(schema.parameters, "required")
      assert schema.parameters["properties"]["path"]["type"] == "string"
    end

    test "parses a tool with no parameters (empty properties)" do
      toml = """
      name = "monitor_agents"
      description = "List running agent processes and their status"

      [parameters]
      type = "object"
      """

      assert {:ok, schema} = ToolSchemas.parse_toml(toml)
      assert schema.parameters["properties"] == %{}
      assert schema.parameters["type"] == "object"
    end

    test "returns error for missing description" do
      toml = """
      name = "bad_tool"

      [parameters]
      type = "object"
      """

      assert {:error, {:missing_key, "description"}} = ToolSchemas.parse_toml(toml)
    end

    test "returns error for missing parameters" do
      toml = """
      name = "bad_tool"
      description = "A tool without params section"
      """

      assert {:error, {:missing_key, "parameters"}} = ToolSchemas.parse_toml(toml)
    end

    test "returns error for invalid TOML" do
      assert {:error, {:toml_parse_error, _}} = ToolSchemas.parse_toml("not [valid toml")
    end
  end

  describe "load_defaults/0" do
    test "loads all 13 compiled-in tool schemas" do
      ToolSchemas.load_defaults()
      schemas = ToolSchemas.all()
      assert length(schemas) == 13

      names = Enum.map(schemas, & &1["function"]["name"]) |> Enum.sort()
      assert names == Enum.sort(@expected_tools)
    end

    test "each default schema has description and parameters" do
      ToolSchemas.load_defaults()

      for tool <- @expected_tools do
        [schema] = ToolSchemas.for_tools([tool])
        assert is_binary(schema["function"]["description"]), "#{tool} missing description"
        assert is_map(schema["function"]["parameters"]), "#{tool} missing parameters"
      end
    end
  end

  describe "load/1" do
    @tag :tmp_dir
    test "loads custom schema that overrides default", %{tmp_dir: tmp_dir} do
      tools_dir = Path.join(tmp_dir, "tools")
      File.mkdir_p!(tools_dir)

      custom_toml = """
      name = "read_file"
      description = "Read a research document from the archive"

      [parameters]
      type = "object"
      required = ["path"]

      [parameters.properties.path]
      type = "string"
      description = "Path to research document"
      """

      File.write!(Path.join(tools_dir, "read_file.toml"), custom_toml)

      ToolSchemas.load(tmp_dir)

      [schema] = ToolSchemas.for_tools(["read_file"])
      assert schema["function"]["description"] == "Read a research document from the archive"

      assert schema["function"]["parameters"]["properties"]["path"]["description"] ==
               "Path to research document"
    end

    @tag :tmp_dir
    test "falls back to compiled default when no custom file exists", %{tmp_dir: tmp_dir} do
      tools_dir = Path.join(tmp_dir, "tools")
      File.mkdir_p!(tools_dir)

      # No custom files — should load all defaults
      ToolSchemas.load(tmp_dir)

      schemas = ToolSchemas.all()
      assert length(schemas) == 13
    end

    @tag :tmp_dir
    test "malformed TOML file logs warning and falls back to default", %{tmp_dir: tmp_dir} do
      tools_dir = Path.join(tmp_dir, "tools")
      File.mkdir_p!(tools_dir)

      # Write a malformed file
      File.write!(Path.join(tools_dir, "read_file.toml"), "not valid toml [[[")

      log =
        capture_log(fn ->
          ToolSchemas.load(tmp_dir)
        end)

      assert log =~ "Malformed read_file.toml"
      assert log =~ "using default"

      # Should still have read_file from defaults
      [schema] = ToolSchemas.for_tools(["read_file"])
      assert schema["function"]["description"] == "Read the contents of a file at the given path"
    end

    @tag :tmp_dir
    test "handles missing tools directory gracefully", %{tmp_dir: tmp_dir} do
      # No tools/ dir at all — should load all defaults
      ToolSchemas.load(tmp_dir)

      schemas = ToolSchemas.all()
      assert length(schemas) == 13
    end

    @tag :tmp_dir
    test "custom file for non-default tool adds new schema", %{tmp_dir: tmp_dir} do
      tools_dir = Path.join(tmp_dir, "tools")
      File.mkdir_p!(tools_dir)

      custom_toml = """
      name = "custom_tool"
      description = "A custom domain tool"

      [parameters]
      type = "object"
      required = ["input"]

      [parameters.properties.input]
      type = "string"
      description = "Input data"
      """

      File.write!(Path.join(tools_dir, "custom_tool.toml"), custom_toml)

      ToolSchemas.load(tmp_dir)

      # Should have 13 defaults + 1 custom
      schemas = ToolSchemas.all()
      assert length(schemas) == 14

      [custom] = ToolSchemas.for_tools(["custom_tool"])
      assert custom["function"]["description"] == "A custom domain tool"
    end
  end

  describe "TOML round-trip — defaults parse correctly" do
    for tool_name <- ~w(
          read_file write_file delete_file list_files search_files
          run_command spawn_agent run_workflow
          monitor_agents broadcast_status signal_ready
          search_context store_context
        ) do
      test "#{tool_name}.toml parses and loads successfully" do
        tool = unquote(tool_name)
        filename = "#{tool}.toml"

        assert {:ok, toml_content} = DefaultFiles.default_content("tools", filename)
        assert {:ok, schema} = ToolSchemas.parse_toml(toml_content)
        assert is_binary(schema.description)
        assert is_map(schema.parameters)
        assert schema.parameters["type"] == "object"
      end
    end
  end

  describe "for_tools/1" do
    test "returns OpenAI-format schemas for known tools" do
      schemas = ToolSchemas.for_tools(["read_file", "write_file"])
      assert length(schemas) == 2

      [schema | _] = schemas
      assert schema["type"] == "function"
      assert is_binary(schema["function"]["name"])
      assert is_binary(schema["function"]["description"])
      assert is_map(schema["function"]["parameters"])
    end

    test "skips unknown tools" do
      schemas = ToolSchemas.for_tools(["read_file", "nonexistent_tool"])
      assert length(schemas) == 1
    end

    test "returns empty list when no schemas loaded" do
      :persistent_term.erase({ToolSchemas, :schemas})
      assert [] == ToolSchemas.for_tools(["read_file"])
    end
  end

  describe "all/0" do
    test "returns schemas for all 13 default tools" do
      schemas = ToolSchemas.all()
      assert length(schemas) == 13

      names = Enum.map(schemas, & &1["function"]["name"]) |> Enum.sort()
      assert names == Enum.sort(@expected_tools)
    end
  end

  describe "register/3" do
    test "extension schema overrides default" do
      ToolSchemas.load_defaults()

      schema = %{description: "Extension search", parameters: %{"type" => "object"}}
      ToolSchemas.register("search_context", schema, :extension)

      [result] = ToolSchemas.for_tools(["search_context"])
      assert result["function"]["description"] == "Extension search"
    end

    test "mcp schema overrides extension" do
      ToolSchemas.load_defaults()

      ext_schema = %{description: "Extension version", parameters: %{"type" => "object"}}
      ToolSchemas.register("my_tool", ext_schema, :extension)

      mcp_schema = %{description: "MCP version", parameters: %{"type" => "object"}}
      ToolSchemas.register("my_tool", mcp_schema, :mcp)

      [result] = ToolSchemas.for_tools(["my_tool"])
      assert result["function"]["description"] == "MCP version"
    end

    test "extension does not override mcp" do
      ToolSchemas.load_defaults()

      mcp_schema = %{description: "MCP version", parameters: %{"type" => "object"}}
      ToolSchemas.register("my_tool", mcp_schema, :mcp)

      ext_schema = %{description: "Extension version", parameters: %{"type" => "object"}}
      ToolSchemas.register("my_tool", ext_schema, :extension)

      [result] = ToolSchemas.for_tools(["my_tool"])
      assert result["function"]["description"] == "MCP version"
    end

    @tag :tmp_dir
    test "user file overrides everything", %{tmp_dir: tmp_dir} do
      tools_dir = Path.join(tmp_dir, "tools")
      File.mkdir_p!(tools_dir)

      custom_toml = """
      name = "read_file"
      description = "User custom read"

      [parameters]
      type = "object"
      required = ["path"]

      [parameters.properties.path]
      type = "string"
      description = "Custom path"
      """

      File.write!(Path.join(tools_dir, "read_file.toml"), custom_toml)
      ToolSchemas.load(tmp_dir)

      # Try to override with extension — should be rejected
      ext_schema = %{description: "Extension read", parameters: %{"type" => "object"}}
      ToolSchemas.register("read_file", ext_schema, :extension)

      [result] = ToolSchemas.for_tools(["read_file"])
      assert result["function"]["description"] == "User custom read"

      # Try to override with MCP — should also be rejected
      mcp_schema = %{description: "MCP read", parameters: %{"type" => "object"}}
      ToolSchemas.register("read_file", mcp_schema, :mcp)

      [result] = ToolSchemas.for_tools(["read_file"])
      assert result["function"]["description"] == "User custom read"
    end

    test "extension schema for new tool adds it to registry" do
      ToolSchemas.load_defaults()

      schema = %{description: "Brand new tool", parameters: %{"type" => "object"}}
      ToolSchemas.register("brand_new", schema, :extension)

      [result] = ToolSchemas.for_tools(["brand_new"])
      assert result["function"]["description"] == "Brand new tool"
    end

    test "3-tuple extension (no params) still works via defaults" do
      ToolSchemas.load_defaults()

      # search_context has a default from TOML — 3-tuple extension would not register a schema
      # so the default should still be there
      [result] = ToolSchemas.for_tools(["search_context"])

      assert result["function"]["description"] ==
               "Search the knowledge store for relevant entries"
    end
  end
end
