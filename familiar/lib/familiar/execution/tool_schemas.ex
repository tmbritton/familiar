defmodule Familiar.Execution.ToolSchemas do
  @moduledoc """
  OpenAI-compatible tool schemas for LLM function calling.

  Converts registered tool names into the structured format expected by
  the `/v1/chat/completions` API with `tools` parameter.
  """

  @schemas %{
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
            "description" => "Workflow name (feature-planning, feature-implementation, task-fix)"
          },
          "task" => %{"type" => "string", "description" => "Task description for the workflow"}
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
            "description" => "Entry type (convention, fact, decision, gotcha)"
          }
        },
        "required" => ["text", "type"]
      }
    }
  }

  @doc "Convert a list of tool name strings to OpenAI-format tool schemas."
  @spec for_tools([String.t()]) :: [map()]
  def for_tools(tool_names) do
    tool_names
    |> Enum.map(&to_schema/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Convert all registered tool names to schemas."
  @spec all :: [map()]
  def all do
    @schemas
    |> Map.keys()
    |> Enum.map(&to_schema(to_string(&1)))
  end

  defp to_schema(name) when is_binary(name) do
    case safe_to_atom(name) do
      {:ok, atom_name} ->
        case Map.get(@schemas, atom_name) do
          nil -> nil
          schema -> build_openai_schema(name, schema)
        end

      :error ->
        nil
    end
  end

  defp build_openai_schema(name, schema) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => schema.description,
        "parameters" => schema.parameters
      }
    }
  end

  defp safe_to_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end
end
