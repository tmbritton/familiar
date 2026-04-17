defmodule Familiar.Config.Generator do
  @moduledoc """
  Generates default `.familiar/config.toml` during project initialization.

  The generated file includes multi-provider configuration with commented examples.
  """

  alias Familiar.Config

  @doc """
  Generate a default config.toml in the given `.familiar/` directory.

  Does not overwrite an existing config file.
  """
  @spec generate_default(String.t()) :: :ok
  def generate_default(familiar_dir) do
    config_path = Path.join(familiar_dir, "config.toml")

    unless File.exists?(config_path) do
      content = build_config_content()
      File.write!(config_path, content)
    end

    :ok
  end

  # -- Private --

  defp build_config_content do
    [
      "# Familiar project configuration",
      "# Edit this file to customize Familiar's behavior for this project.",
      "",
      providers_section(),
      "",
      scan_section(),
      "",
      notifications_section(),
      "",
      indexing_section(),
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

  defp indexing_section do
    defaults = Config.defaults().indexing

    [
      "[indexing]",
      "# Customize which files are indexed during project scanning.",
      "# Uncomment and modify any key to override the defaults.",
      "# skip_dirs = #{inspect(defaults.skip_dirs)}",
      "# skip_extensions = #{inspect(defaults.skip_extensions)}",
      "# skip_files = #{inspect(defaults.skip_files)}",
      "# source_extensions = #{inspect(defaults.source_extensions)}",
      "# config_files = #{inspect(defaults.config_files)}",
      "# config_extensions = #{inspect(defaults.config_extensions)}",
      "# doc_extensions = #{inspect(defaults.doc_extensions)}",
      "# test_patterns = #{inspect(defaults.test_patterns)}"
    ]
    |> Enum.join("\n")
  end
end
