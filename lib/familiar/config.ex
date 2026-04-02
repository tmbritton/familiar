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
            language: %{},
            scan: %{max_files: 200, large_project_threshold: 500},
            notifications: %{provider: "auto", enabled: true}

  @language_defaults %{
    "elixir" => %{
      name: "elixir",
      test_command: "mix test",
      build_command: "mix compile",
      lint_command: "mix credo --strict",
      dep_file: "mix.exs",
      skip_patterns: ["_build/", "deps/", "cover/"],
      source_extensions: [".ex", ".exs"]
    },
    "go" => %{
      name: "go",
      test_command: "go test ./...",
      build_command: "go build ./...",
      lint_command: "golangci-lint run",
      dep_file: "go.mod",
      skip_patterns: ["vendor/"],
      source_extensions: [".go"]
    }
  }

  @doc "Returns the default configuration."
  @spec defaults() :: %__MODULE__{}
  def defaults, do: %__MODULE__{}

  @doc "Returns default language config for the given language name, or empty map."
  @spec language_defaults(String.t()) :: map()
  def language_defaults(name) do
    Map.get(@language_defaults, name, %{})
  end

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

  defp format_toml_error(%{message: msg}), do: msg
  defp format_toml_error(error), do: inspect(error)

  defp validate_and_build(parsed) do
    with {:ok, provider} <- validate_provider(parsed["provider"]),
         {:ok, language} <- validate_language(parsed["language"]),
         {:ok, scan} <- validate_scan(parsed["scan"]),
         {:ok, notifications} <- validate_notifications(parsed["notifications"]) do
      {:ok,
       %__MODULE__{
         provider: provider,
         language: language,
         scan: scan,
         notifications: notifications
       }}
    end
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

  defp validate_language(nil), do: {:ok, %{}}

  defp validate_language(section) when is_map(section) do
    {:ok, section}
  end

  defp validate_language(_section) do
    {:error, {:invalid_config, %{field: "language", reason: "expected a TOML table"}}}
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

  defp validate_string(_field, nil), do: :ok
  defp validate_string(_field, value) when is_binary(value), do: :ok

  defp validate_string(field, value) do
    {:error,
     {:invalid_config, %{field: field, reason: "expected string, got #{inspect(value)}"}}}
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
end
