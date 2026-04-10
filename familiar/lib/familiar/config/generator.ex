defmodule Familiar.Config.Generator do
  @moduledoc """
  Generates default `.familiar/config.toml` during project initialization.

  The generated file includes multi-provider configuration with commented
  examples, and populates the language section based on detected project language.
  """

  alias Familiar.Config

  @doc """
  Generate a default config.toml in the given `.familiar/` directory.

  Does not overwrite an existing config file. When `detected_language` is
  provided and has known defaults, the language section is populated.
  """
  @spec generate_default(String.t(), String.t() | nil) :: :ok
  def generate_default(familiar_dir, detected_language) do
    config_path = Path.join(familiar_dir, "config.toml")

    unless File.exists?(config_path) do
      content = build_config_content(detected_language)
      File.write!(config_path, content)
    end

    :ok
  end

  @doc """
  Detect project language from files in the given directory.
  Returns the language name string or nil.
  """
  @spec detect_project_language(String.t()) :: String.t() | nil
  def detect_project_language(project_dir) do
    indicators = %{
      "mix.exs" => "elixir",
      "go.mod" => "go",
      "package.json" => "javascript",
      "Cargo.toml" => "rust",
      "pyproject.toml" => "python",
      "requirements.txt" => "python",
      "Gemfile" => "ruby",
      "pom.xml" => "java",
      "build.gradle" => "java"
    }

    Enum.find_value(indicators, fn {file, lang} ->
      if File.exists?(Path.join(project_dir, file)), do: lang
    end)
  end

  # -- Private --

  defp build_config_content(detected_language) do
    [
      "# Familiar project configuration",
      "# Edit this file to customize Familiar's behavior for this project.",
      "",
      providers_section(),
      "",
      language_section(detected_language),
      "",
      scan_section(),
      "",
      notifications_section(),
      ""
    ]
    |> Enum.join("\n")
  end

  defp providers_section do
    [
      "# === LLM Providers ===",
      "# Configure one or more providers. Set default = true on the one to use.",
      "# Override per-command with: fam chat --provider <name>",
      "# Use ${ENV_VAR} to reference environment variables (e.g., api_key = \"${OPENROUTER_API_KEY}\")",
      "#",
      "# Changing embedding_model later requires running `fam context --reindex`",
      "# to re-embed every stored knowledge entry with the new model.",
      "",
      "# OpenRouter (multi-model gateway)",
      "[providers.openrouter]",
      ~s(type = "openai_compatible"),
      ~s(base_url = "https://openrouter.ai/api/v1"),
      ~s(api_key = "${OPENROUTER_API_KEY}"),
      ~s(chat_model = "deepseek/deepseek-chat-v3-0324"),
      ~s(embedding_model = "openai/text-embedding-3-small"),
      "default = true",
      "",
      "# DeepSeek (direct)",
      "# [providers.deepseek]",
      ~s(# type = "openai_compatible"),
      ~s(# base_url = "https://api.deepseek.com/v1"),
      ~s(# api_key = "${DEEPSEEK_API_KEY}"),
      ~s(# chat_model = "deepseek-chat"),
      "",
      "# Qwen / DashScope (OpenAI-compatible)",
      "# [providers.qwen]",
      ~s(# type = "openai_compatible"),
      ~s(# base_url = "https://dashscope.aliyuncs.com/compatible-mode"),
      ~s(# api_key = "${DASHSCOPE_API_KEY}"),
      ~s(# chat_model = "qwen-plus"),
      "",
      "# Ollama (local)",
      "# [providers.ollama]",
      ~s(# type = "ollama"),
      ~s(# base_url = "http://localhost:11434"),
      ~s(# chat_model = "llama3.2"),
      ~s(# embedding_model = "nomic-embed-text")
    ]
    |> Enum.join("\n")
  end

  defp language_section(nil), do: language_section_commented()
  defp language_section(""), do: language_section_commented()

  defp language_section(lang_name) do
    case Config.language_defaults(lang_name) do
      empty when empty == %{} -> language_section_commented()
      lang -> language_section_populated(lang)
    end
  end

  defp language_section_commented do
    [
      "[language]",
      ~s(# name = "elixir"),
      ~s(# test_command = "mix test"),
      ~s(# build_command = "mix compile"),
      ~s(# lint_command = "mix credo --strict"),
      ~s(# dep_file = "mix.exs"),
      ~s(# skip_patterns = ["_build/", "deps/"]),
      ~s(# source_extensions = [".ex", ".exs"])
    ]
    |> Enum.join("\n")
  end

  defp language_section_populated(lang) do
    skip = Enum.map_join(lang.skip_patterns, ", ", &~s("#{&1}"))
    exts = Enum.map_join(lang.source_extensions, ", ", &~s("#{&1}"))

    [
      "[language]",
      ~s(name = "#{lang.name}"),
      ~s(test_command = "#{lang.test_command}"),
      ~s(build_command = "#{lang.build_command}"),
      ~s(lint_command = "#{lang.lint_command}"),
      ~s(dep_file = "#{lang.dep_file}"),
      "skip_patterns = [#{skip}]",
      "source_extensions = [#{exts}]"
    ]
    |> Enum.join("\n")
  end

  defp scan_section do
    defaults = Config.defaults().scan

    [
      "[scan]",
      "# max_files = #{defaults.max_files}",
      "# large_project_threshold = #{defaults.large_project_threshold}"
    ]
    |> Enum.join("\n")
  end

  defp notifications_section do
    [
      "[notifications]",
      ~s(# provider = "auto"),
      "# enabled = true"
    ]
    |> Enum.join("\n")
  end
end
