defmodule Familiar.Knowledge.LanguageIndicators do
  @moduledoc """
  Canonical language indicator file mappings.

  Shared between ConventionDiscoverer (display names) and
  CommandValidator (short names) to avoid duplication.
  """

  @indicators [
    {"mix.exs", "elixir", "Elixir"},
    {"package.json", "nodejs", "Node.js/JavaScript"},
    {"go.mod", "go", "Go"},
    {"Cargo.toml", "rust", "Rust"},
    {"pyproject.toml", "python", "Python"},
    {"Gemfile", "ruby", "Ruby"},
    {"pom.xml", "java", "Java"},
    {"build.gradle", "java", "Java/Kotlin"}
  ]

  @doc "List of {file, short_name} tuples for command validation."
  def short_list do
    Enum.map(@indicators, fn {file, short, _display} -> {file, short} end)
  end

  @doc "Map of %{file => display_name} for convention discovery."
  def display_map do
    Map.new(@indicators, fn {file, _short, display} -> {file, display} end)
  end
end
