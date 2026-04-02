defmodule Familiar.Config.Generator do
  @moduledoc """
  Generates default `.familiar/config.toml` during project initialization.

  The generated file includes commented defaults and populates the language
  section based on the detected project language.
  """

  alias Familiar.Config

  @doc """
  Generate a default config.toml in the given `.familiar/` directory.

  Does not overwrite an existing config file. When `detected_language` is
  provided and has known defaults, the language section is populated with
  those values; otherwise, it is commented out.
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

  # -- Private --

  defp build_config_content(detected_language) do
    [
      "# Familiar project configuration",
      "# Edit this file to customize Familiar's behavior for this project.",
      "",
      provider_section(),
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

  defp provider_section do
    defaults = Config.defaults().provider

    [
      "[provider]",
      ~s(base_url = "#{defaults.base_url}"),
      ~s(chat_model = "#{defaults.chat_model}"),
      ~s(embedding_model = "#{defaults.embedding_model}"),
      "timeout = #{defaults.timeout}"
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
      "# name = \"elixir\"",
      "# test_command = \"mix test\"",
      "# build_command = \"mix compile\"",
      "# lint_command = \"mix credo --strict\"",
      "# dep_file = \"mix.exs\"",
      "# skip_patterns = [\"_build/\", \"deps/\"]",
      "# source_extensions = [\".ex\", \".exs\"]"
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
      "# provider = \"auto\"",
      "# enabled = true"
    ]
    |> Enum.join("\n")
  end
end
