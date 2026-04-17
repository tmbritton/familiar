defmodule Familiar.Config do
  @moduledoc """
  Project-local configuration loaded from `.familiar/config.toml`.

  Provides defaults for all settings. Missing or invalid config files
  fall back to defaults gracefully — the system never crashes from bad config.
  """

  require Logger

  defstruct provider: %{
              base_url: "http://localhost:11434",
              chat_model: "llama3.2",
              embedding_model: "nomic-embed-text",
              timeout: 120
            },
            providers: %{},
            scan: %{max_files: 200, large_project_threshold: 500},
            notifications: %{provider: "auto", enabled: true},
            mcp_servers: [],
            indexing: %{
              skip_dirs: ~w(.git/ vendor/ node_modules/ _build/ deps/ .elixir_ls/ .familiar/
                    __pycache__/ .tox/ .mypy_cache/ target/ dist/ build/),
              skip_extensions: ~w(.beam .pyc .pyo .class .o .so .dylib .min.js .min.css .map),
              skip_files:
                ~w(go.sum mix.lock package-lock.json yarn.lock Cargo.lock poetry.lock Gemfile.lock),
              source_extensions:
                ~w(.ex .exs .go .py .ts .tsx .js .jsx .rb .rs .java .c .cpp .h .hpp .cs .swift .kt),
              config_files:
                ~w(mix.exs package.json Cargo.toml pyproject.toml Gemfile Makefile CMakeLists.txt),
              config_extensions: ~w(.toml .yaml .yml .json .xml .ini .cfg),
              doc_extensions: ~w(.md .txt .rst .adoc),
              test_patterns: ["test/", "spec/", "_test\\.", "_spec\\."]
            }

  @doc "Returns the default configuration."
  @spec defaults() :: %__MODULE__{
          provider: %{
            base_url: String.t(),
            chat_model: String.t(),
            embedding_model: String.t(),
            timeout: pos_integer()
          },
          scan: %{max_files: pos_integer(), large_project_threshold: pos_integer()},
          notifications: %{provider: String.t(), enabled: boolean()},
          mcp_servers: [map()]
        }
  def defaults, do: %__MODULE__{}

  @doc """
  Load configuration from a TOML file path.

  Returns `{:ok, config}` with defaults merged for missing values.
  Returns `{:ok, defaults}` if the file does not exist.
  Returns `{:error, {:invalid_config, %{field: ..., reason: ...}}}` on validation failure.
  """
  @spec load(String.t()) :: {:ok, %__MODULE__{}} | {:error, {:invalid_config, map()}}
  def load(path) do
    case read_toml(path) do
      {:ok, parsed} -> validate_and_build(parsed)
      {:error, :not_found} -> {:ok, defaults()}
      {:error, reason} -> {:error, {:invalid_config, %{field: "file", reason: reason}}}
    end
  end

  # -- Private --

  defp read_toml(path) do
    if File.exists?(path) do
      case Toml.decode_file(path) do
        {:ok, parsed} -> {:ok, parsed}
        {:error, error} -> {:error, format_toml_error(error)}
      end
    else
      {:error, :not_found}
    end
  end

  defp format_toml_error(error) when is_binary(error), do: error
  defp format_toml_error({:invalid_toml, msg}), do: msg

  defp validate_and_build(parsed) do
    {providers, default_provider} = parse_providers(parsed["providers"])

    with {:ok, provider} <- resolve_provider(default_provider, parsed["provider"]),
         {:ok, scan} <- validate_scan(parsed["scan"]),
         {:ok, notifications} <- validate_notifications(parsed["notifications"]),
         {:ok, mcp_servers} <- parse_mcp_servers(parsed["mcp"]),
         {:ok, indexing} <- validate_indexing(parsed["indexing"]) do
      {:ok,
       %__MODULE__{
         provider: provider,
         providers: providers,
         scan: scan,
         notifications: notifications,
         mcp_servers: mcp_servers,
         indexing: indexing
       }}
    end
  end

  @doc "Look up a named provider from the parsed config."
  @spec get_provider(%__MODULE__{}, String.t()) ::
          {:ok, map()} | {:error, {:unknown_provider, map()}}
  def get_provider(%__MODULE__{providers: providers}, name) do
    case Map.get(providers, name) do
      nil -> {:error, {:unknown_provider, %{name: name}}}
      provider -> {:ok, provider}
    end
  end

  defp parse_providers(nil), do: {%{}, nil}

  defp parse_providers(sections) when is_map(sections) do
    providers =
      Map.new(sections, fn {name, settings} ->
        {name,
         %{
           type: settings["type"] || "ollama",
           base_url: expand_env(settings["base_url"]),
           api_key: expand_env(settings["api_key"]),
           chat_model: expand_env(settings["chat_model"]),
           embedding_model: expand_env(settings["embedding_model"]),
           timeout: settings["timeout"] || 120
         }}
      end)

    default_name =
      Enum.find_value(sections, fn {name, settings} ->
        if settings["default"] == true, do: name
      end)

    default_provider =
      if default_name, do: Map.get(providers, default_name)

    {providers, default_provider}
  end

  defp resolve_provider(nil, legacy_section), do: validate_provider(legacy_section)

  defp resolve_provider(provider, _legacy) do
    {:ok,
     %{
       base_url: provider.base_url || defaults().provider.base_url,
       chat_model: provider.chat_model || defaults().provider.chat_model,
       embedding_model: provider.embedding_model || defaults().provider.embedding_model,
       timeout: provider.timeout || defaults().provider.timeout,
       type: provider.type,
       api_key: provider.api_key
     }}
  end

  defp validate_provider(nil), do: {:ok, defaults().provider}

  defp validate_provider(section) do
    defaults = defaults().provider

    with :ok <- validate_string("provider.base_url", section["base_url"]),
         :ok <- validate_string("provider.chat_model", section["chat_model"]),
         :ok <- validate_string("provider.embedding_model", section["embedding_model"]),
         :ok <- validate_positive_int("provider.timeout", section["timeout"]) do
      {:ok,
       %{
         base_url: section["base_url"] || defaults.base_url,
         chat_model: section["chat_model"] || defaults.chat_model,
         embedding_model: section["embedding_model"] || defaults.embedding_model,
         timeout: section["timeout"] || defaults.timeout
       }}
    end
  end

  defp validate_scan(nil), do: {:ok, defaults().scan}

  defp validate_scan(section) do
    defaults = defaults().scan

    with :ok <- validate_positive_int("scan.max_files", section["max_files"]),
         :ok <-
           validate_positive_int(
             "scan.large_project_threshold",
             section["large_project_threshold"]
           ) do
      {:ok,
       %{
         max_files: section["max_files"] || defaults.max_files,
         large_project_threshold:
           section["large_project_threshold"] || defaults.large_project_threshold
       }}
    end
  end

  defp validate_notifications(nil), do: {:ok, defaults().notifications}

  defp validate_notifications(section) do
    defaults = defaults().notifications

    with :ok <- validate_string("notifications.provider", section["provider"]),
         :ok <- validate_boolean("notifications.enabled", section["enabled"]) do
      {:ok,
       %{
         provider: section["provider"] || defaults.provider,
         enabled: if(is_nil(section["enabled"]), do: defaults.enabled, else: section["enabled"])
       }}
    end
  end

  @indexing_list_keys ~w(skip_dirs skip_extensions skip_files source_extensions
                         config_files config_extensions doc_extensions)a

  defp validate_indexing(nil), do: {:ok, defaults().indexing}

  defp validate_indexing(section) when is_map(section) do
    with :ok <- validate_indexing_lists(section),
         :ok <- validate_test_patterns(section["test_patterns"]) do
      {:ok, merge_indexing_defaults(section)}
    end
  end

  defp validate_indexing(_) do
    {:error, {:invalid_config, %{field: "indexing", reason: "expected a TOML table"}}}
  end

  defp merge_indexing_defaults(section) do
    defaults = defaults().indexing

    indexing =
      Enum.reduce(@indexing_list_keys, defaults, fn key, acc ->
        case section[Atom.to_string(key)] do
          nil -> acc
          val -> Map.put(acc, key, val)
        end
      end)

    test_patterns =
      case section["test_patterns"] do
        nil -> defaults.test_patterns
        patterns when is_list(patterns) -> patterns
      end

    Map.put(indexing, :test_patterns, test_patterns)
  end

  defp validate_indexing_lists(section) do
    Enum.reduce_while(@indexing_list_keys, :ok, fn key, :ok ->
      str_key = Atom.to_string(key)
      validate_string_list("indexing.#{str_key}", section[str_key])
    end)
  end

  defp validate_string_list(_field, nil), do: {:cont, :ok}

  defp validate_string_list(field, val) when is_list(val) do
    if Enum.all?(val, &is_binary/1),
      do: {:cont, :ok},
      else:
        {:halt, {:error, {:invalid_config, %{field: field, reason: "expected list of strings"}}}}
  end

  defp validate_string_list(field, val) do
    {:halt,
     {:error,
      {:invalid_config, %{field: field, reason: "expected list of strings, got #{inspect(val)}"}}}}
  end

  defp validate_test_patterns(nil), do: :ok

  defp validate_test_patterns(patterns) when is_list(patterns) do
    Enum.reduce_while(patterns, :ok, fn
      s, :ok when is_binary(s) ->
        case Regex.compile(s) do
          {:ok, _} ->
            {:cont, :ok}

          {:error, _} ->
            {:halt,
             {:error,
              {:invalid_config,
               %{field: "indexing.test_patterns", reason: "invalid regex: #{inspect(s)}"}}}}
        end

      val, :ok ->
        {:halt,
         {:error,
          {:invalid_config,
           %{
             field: "indexing.test_patterns",
             reason: "expected list of strings, got element #{inspect(val)}"
           }}}}
    end)
  end

  defp validate_test_patterns(val) do
    {:error,
     {:invalid_config,
      %{field: "indexing.test_patterns", reason: "expected list of strings, got #{inspect(val)}"}}}
  end

  defp validate_string(_field, nil), do: :ok
  defp validate_string(_field, value) when is_binary(value), do: :ok

  defp validate_string(field, value) do
    {:error, {:invalid_config, %{field: field, reason: "expected string, got #{inspect(value)}"}}}
  end

  defp validate_positive_int(_field, nil), do: :ok
  defp validate_positive_int(_field, value) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_int(field, value) do
    {:error,
     {:invalid_config,
      %{field: field, reason: "expected positive integer, got #{inspect(value)}"}}}
  end

  defp validate_boolean(_field, nil), do: :ok
  defp validate_boolean(_field, value) when is_boolean(value), do: :ok

  defp validate_boolean(field, value) do
    {:error,
     {:invalid_config, %{field: field, reason: "expected boolean, got #{inspect(value)}"}}}
  end

  defp parse_mcp_servers(nil), do: {:ok, []}

  defp parse_mcp_servers(%{"servers" => servers}) when is_list(servers) do
    valid =
      Enum.reduce(servers, [], fn entry, acc ->
        case validate_mcp_server_entry(entry) do
          {:ok, server} ->
            [server | acc]

          {:error, {:invalid_config, details}} ->
            Logger.warning(
              "[Config] Skipping invalid MCP server entry: #{details.field} — #{details.reason}"
            )

            acc
        end
      end)

    {:ok, Enum.reverse(valid)}
  end

  defp parse_mcp_servers(%{}), do: {:ok, []}

  defp parse_mcp_servers(_) do
    {:error, {:invalid_config, %{field: "mcp", reason: "expected a TOML table"}}}
  end

  defp validate_mcp_server_entry(entry) when is_map(entry) do
    name = entry["name"]
    command = entry["command"]

    cond do
      not is_binary(name) or name == "" ->
        {:error,
         {:invalid_config, %{field: "mcp.servers.name", reason: "required, must be a string"}}}

      not is_binary(command) or command == "" ->
        {:error,
         {:invalid_config, %{field: "mcp.servers.command", reason: "required, must be a string"}}}

      true ->
        {:ok,
         %{
           name: name,
           command: command,
           args: entry["args"] || [],
           env: entry["env"] || %{}
         }}
    end
  end

  defp validate_mcp_server_entry(_) do
    {:error,
     {:invalid_config, %{field: "mcp.servers", reason: "each entry must be a TOML table"}}}
  end

  @doc """
  Expand `${ENV_VAR}` references in string values.

  Returns the input unchanged for non-string values and `nil`.
  Used for provider config and MCP server env expansion.

  ## Examples

      iex> Familiar.Config.expand_env("hello")
      "hello"

      iex> Familiar.Config.expand_env(nil)
      nil

      iex> Familiar.Config.expand_env(42)
      42
  """
  @spec expand_env(String.t() | nil | term()) :: String.t() | nil | term()
  def expand_env(nil), do: nil

  def expand_env(value) when is_binary(value) do
    Regex.replace(~r/\$\{([^}]+)\}/, value, fn _, var_name ->
      System.get_env(var_name) || ""
    end)
  end

  def expand_env(value), do: value
end
