defmodule Familiar.Execution.ToolSchemasTest do
  use ExUnit.Case, async: true

  alias Familiar.Execution.ToolSchemas
  alias Familiar.Knowledge.DefaultFiles

  @expected_tools ~w(
    read_file write_file delete_file list_files search_files
    run_command spawn_agent run_workflow
    monitor_agents broadcast_status signal_ready
    search_context store_context
  )

  # Access the compile-time @schemas map for round-trip comparison.
  # ToolSchemas.all/0 returns OpenAI-wrapped schemas; we need the raw map.
  # We reconstruct expectations from the known TOML files instead.

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

  describe "TOML round-trip equivalence" do
    # The canonical @schemas map, reconstructed here for comparison.
    # This must match tool_schemas.ex @schemas exactly.
    @canonical_schemas %{
      read_file: %{
        description: "Read the contents of a file at the given path",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Absolute or relative file path to read"
            }
          },
          "required" => ["path"]
        }
      },
      write_file: %{
        description: "Write content to a file at the given path",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "File path to write to"},
            "content" => %{"type" => "string", "description" => "Content to write"}
          },
          "required" => ["path", "content"]
        }
      },
      delete_file: %{
        description: "Delete a file at the given path",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "File path to delete"}
          },
          "required" => ["path"]
        }
      },
      list_files: %{
        description: "List files in a directory",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" => "Directory path to list (defaults to project root)"
            }
          }
        }
      },
      search_files: %{
        description: "Search file contents for a pattern using grep",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{"type" => "string", "description" => "Search pattern (regex)"},
            "path" => %{
              "type" => "string",
              "description" => "Directory to search in (defaults to project root)"
            }
          },
          "required" => ["pattern"]
        }
      },
      run_command: %{
        description: "Run a shell command",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "command" => %{"type" => "string", "description" => "Shell command to execute"}
          },
          "required" => ["command"]
        }
      },
      spawn_agent: %{
        description: "Spawn a child agent process with a given role and task",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "role" => %{
              "type" => "string",
              "description" =>
                "Agent role name (analyst, coder, reviewer, project-manager, librarian)"
            },
            "task" => %{"type" => "string", "description" => "Task description for the agent"}
          },
          "required" => ["role", "task"]
        }
      },
      run_workflow: %{
        description: "Run a workflow defined in a markdown file",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "workflow" => %{
              "type" => "string",
              "description" =>
                "Workflow name (feature-planning, feature-implementation, task-fix)"
            },
            "task" => %{
              "type" => "string",
              "description" => "Task description for the workflow"
            }
          },
          "required" => ["workflow", "task"]
        }
      },
      monitor_agents: %{
        description: "List running agent processes and their status",
        parameters: %{
          "type" => "object",
          "properties" => %{}
        }
      },
      broadcast_status: %{
        description: "Broadcast a status message to subscribers",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "message" => %{"type" => "string", "description" => "Status message to broadcast"}
          },
          "required" => ["message"]
        }
      },
      signal_ready: %{
        description: "Signal that the current workflow step is complete",
        parameters: %{
          "type" => "object",
          "properties" => %{}
        }
      },
      search_context: %{
        description: "Search the knowledge store for relevant entries",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "query" => %{"type" => "string", "description" => "Search query"}
          },
          "required" => ["query"]
        }
      },
      store_context: %{
        description: "Store a new entry in the knowledge store",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "text" => %{"type" => "string", "description" => "Knowledge entry text"},
            "type" => %{
              "type" => "string",
              "description" =>
                "Entry type — any lowercase snake_case slug (e.g. convention, fact, decision, gotcha, file_summary, architecture)"
            }
          },
          "required" => ["text", "type"]
        }
      }
    }

    for tool_name <- ~w(
          read_file write_file delete_file list_files search_files
          run_command spawn_agent run_workflow
          monitor_agents broadcast_status signal_ready
          search_context store_context
        )a do
      test "#{tool_name}.toml round-trips to match @schemas" do
        tool_atom = unquote(tool_name)
        filename = "#{tool_atom}.toml"
        expected = Map.fetch!(@canonical_schemas, tool_atom)

        assert {:ok, toml_content} = DefaultFiles.default_content("tools", filename),
               "Missing compiled default for tools/#{filename}"

        assert {:ok, parsed} = ToolSchemas.parse_toml(toml_content),
               "Failed to parse tools/#{filename}"

        assert parsed.description == expected.description,
               "Description mismatch for #{tool_atom}: #{inspect(parsed.description)} != #{inspect(expected.description)}"

        assert parsed.parameters == expected.parameters,
               "Parameters mismatch for #{tool_atom}:\n  got:      #{inspect(parsed.parameters)}\n  expected: #{inspect(expected.parameters)}"
      end
    end
  end

  describe "for_tools/1" do
    test "returns OpenAI-format schemas for known tools" do
      schemas = ToolSchemas.for_tools(["read_file", "write_file"])
      assert length(schemas) == 2

      [schema | _] = schemas
      assert schema["type"] == "function"
      assert schema["function"]["name"] == "read_file"
      assert is_binary(schema["function"]["description"])
      assert is_map(schema["function"]["parameters"])
    end

    test "skips unknown tools" do
      schemas = ToolSchemas.for_tools(["read_file", "nonexistent_tool"])
      assert length(schemas) == 1
    end
  end

  describe "all/0" do
    test "returns schemas for all 13 tools" do
      schemas = ToolSchemas.all()
      assert length(schemas) == 13

      names = Enum.map(schemas, & &1["function"]["name"]) |> Enum.sort()
      assert names == Enum.sort(@expected_tools)
    end
  end
end
