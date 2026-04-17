defmodule Familiar.Execution.ToolSchemas do
  @moduledoc """
  OpenAI-compatible tool schemas for LLM function calling.

  Schemas are loaded from `.familiar/tools/*.toml` at startup, with
  compiled-in defaults from `priv/defaults/tools/` as fallback. Loaded
  schemas are stored in `:persistent_term` for zero-cost reads on the
  agent prompt assembly hot path.
  """

  require Logger

  alias Familiar.Knowledge.DefaultFiles

  @persistent_key {__MODULE__, :schemas}
  @source_priority %{default: 0, extension: 1, mcp: 2, file: 3}

  # -- Public API --

  @doc """
  Load tool schemas from disk and store in `:persistent_term`.

  Scans `familiar_dir/tools/*.toml` for custom schemas, falls back to
  compiled-in defaults for any tools not overridden. Malformed files
  log a warning and fall back to the default.
  """
  @spec load(String.t()) :: :ok
  def load(familiar_dir) do
    tools_dir = Path.join(familiar_dir, "tools")
    defaults = load_compiled_defaults()
    customs = load_custom_files(tools_dir)
    merged = Map.merge(defaults, customs)
    :persistent_term.put(@persistent_key, merged)
    :ok
  end

  @doc """
  Load only compiled-in defaults (no disk reads).

  Useful for tests that don't need custom overrides.
  """
  @spec load_defaults() :: :ok
  def load_defaults do
    :persistent_term.put(@persistent_key, load_compiled_defaults())
    :ok
  end

  @doc """
  Register a tool schema at runtime with source-based precedence.

  Only overwrites if `source` has higher priority than the existing entry.
  Priority: `:default` < `:extension` < `:mcp` < `:file`.
  """
  @spec register(String.t(), map(), :default | :extension | :mcp | :file) :: :ok
  def register(tool_name, schema, source) when is_binary(tool_name) and is_map(schema) do
    schemas = :persistent_term.get(@persistent_key, %{})
    existing = Map.get(schemas, tool_name)
    existing_priority = @source_priority[get_source(existing)]
    new_priority = @source_priority[source]

    if new_priority > existing_priority do
      entry = Map.put(schema, :source, source)
      :persistent_term.put(@persistent_key, Map.put(schemas, tool_name, entry))
    end

    :ok
  end

  @doc "Convert a list of tool name strings to OpenAI-format tool schemas."
  @spec for_tools([String.t()]) :: [map()]
  def for_tools(tool_names) do
    schemas = :persistent_term.get(@persistent_key, %{})

    tool_names
    |> Enum.map(fn name ->
      case Map.get(schemas, name) do
        nil -> nil
        schema -> build_openai_schema(name, schema)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Convert all loaded tool schemas to OpenAI format."
  @spec all :: [map()]
  def all do
    schemas = :persistent_term.get(@persistent_key, %{})

    schemas
    |> Enum.map(fn {name, schema} -> build_openai_schema(name, schema) end)
  end

  @doc """
  Parse a TOML string into a tool schema map.

  Returns `{:ok, %{description: String.t(), parameters: map()}}` or
  `{:error, reason}`. The returned map uses atom keys at the top level
  (`:description`, `:parameters`) and string keys within the parameters
  sub-tree, matching the shape expected by `build_openai_schema/2`.
  """
  @spec parse_toml(String.t()) ::
          {:ok, %{description: String.t(), parameters: map()}} | {:error, term()}
  def parse_toml(toml_string) do
    case Toml.decode(toml_string) do
      {:ok, decoded} ->
        with {:ok, description} <- fetch_string(decoded, "description"),
             {:ok, parameters} <- fetch_parameters(decoded) do
          {:ok, %{description: description, parameters: parameters}}
        end

      {:error, reason} ->
        {:error, {:toml_parse_error, reason}}
    end
  end

  # -- Private --

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

  defp get_source(nil), do: :default
  defp get_source(%{source: source}), do: source
  defp get_source(_), do: :default

  defp load_compiled_defaults do
    for filename <- DefaultFiles.list_files("tools"),
        {:ok, content} <- [DefaultFiles.default_content("tools", filename)],
        {:ok, schema} <- [parse_toml(content)],
        into: %{} do
      tool_name = Path.rootname(filename)
      {tool_name, Map.put(schema, :source, :default)}
    end
  end

  defp load_custom_files(tools_dir) do
    case File.ls(tools_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".toml"))
        |> Enum.flat_map(&load_custom_entry(tools_dir, &1))
        |> Map.new()

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.warning("[ToolSchemas] Cannot list tools dir: #{inspect(reason)}")
        %{}
    end
  end

  defp load_custom_entry(tools_dir, filename) do
    case load_custom_file(tools_dir, filename) do
      {:ok, tool_name, schema} -> [{tool_name, schema}]
      :skip -> []
    end
  end

  defp load_custom_file(tools_dir, filename) do
    path = Path.join(tools_dir, filename)
    tool_name = Path.rootname(filename)

    with {:ok, content} <- read_or_warn(path, filename),
         {:ok, schema} <- parse_or_warn(content, filename) do
      {:ok, tool_name, Map.put(schema, :source, :file)}
    end
  end

  defp read_or_warn(path, filename) do
    case File.read(path) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.warning(
          "[ToolSchemas] Cannot read #{filename}: #{inspect(reason)} — using default"
        )

        :skip
    end
  end

  defp parse_or_warn(content, filename) do
    case parse_toml(content) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.warning("[ToolSchemas] Malformed #{filename}: #{inspect(reason)} — using default")

        :skip
    end
  end

  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:ok, _} -> {:error, {:invalid_type, key, "expected string"}}
      :error -> {:error, {:missing_key, key}}
    end
  end

  defp fetch_parameters(map) do
    case Map.fetch(map, "parameters") do
      {:ok, params} when is_map(params) ->
        {:ok, normalize_parameters(params)}

      {:ok, _} ->
        {:error, {:invalid_type, "parameters", "expected table"}}

      :error ->
        {:error, {:missing_key, "parameters"}}
    end
  end

  defp normalize_parameters(params) do
    Map.put_new(params, "properties", %{})
  end
end
