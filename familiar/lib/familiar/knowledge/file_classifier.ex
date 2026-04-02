defmodule Familiar.Knowledge.FileClassifier do
  @moduledoc """
  File classification and significance scoring for the init scanner.

  Classifies project files as `:index` or `:skip` based on built-in
  skip patterns for directories and file extensions. Provides significance
  scoring for large-project prioritization.
  """

  @skip_dirs ~w(
    .git/ vendor/ node_modules/ _build/ deps/ .elixir_ls/ .familiar/
    __pycache__/ .tox/ .mypy_cache/ target/ dist/ build/
  )

  @skip_extensions ~w(.beam .pyc .pyo .class .o .so .dylib .min.js .min.css .map)

  @skip_files ~w(
    go.sum mix.lock package-lock.json yarn.lock
    Cargo.lock poetry.lock Gemfile.lock
  )

  @source_extensions ~w(.ex .exs .go .py .ts .tsx .js .jsx .rb .rs .java .c .cpp .h .hpp .cs .swift .kt)
  @config_files ~w(mix.exs package.json Cargo.toml pyproject.toml Gemfile Makefile CMakeLists.txt)
  @config_extensions ~w(.toml .yaml .yml .json .xml .ini .cfg)
  @doc_extensions ~w(.md .txt .rst .adoc)
  @test_patterns [~r{test/}, ~r{spec/}, ~r{_test\.}, ~r{_spec\.}]

  @doc """
  Classify a file path as `:index` or `:skip`.

  Accepts optional `skip_dirs` in opts for additional directory patterns.
  """
  @spec classify(String.t(), keyword()) :: :index | :skip
  def classify(path, opts \\ []) do
    extra_skip_dirs = Keyword.get(opts, :skip_dirs, [])
    all_skip_dirs = @skip_dirs ++ extra_skip_dirs

    cond do
      skip_dir?(path, all_skip_dirs) -> :skip
      skip_file?(path) -> :skip
      skip_extension?(path) -> :skip
      true -> :index
    end
  end

  @doc """
  Score a file's significance for prioritization (higher = more important).

  - Source code: 100
  - Config files: 80
  - Documentation: 50
  - Test files: 50
  - Other: 10
  """
  @spec significance(String.t()) :: pos_integer()
  def significance(path) do
    basename = Path.basename(path)
    ext = Path.extname(path)

    cond do
      ext in @source_extensions and not test_file?(path) -> 100
      basename in @config_files -> 80
      ext in @config_extensions -> 80
      test_file?(path) -> 50
      ext in @doc_extensions -> 50
      true -> 10
    end
  end

  @doc """
  Prioritize files by significance, returning at most `budget` files.

  Returns the list unchanged if under budget.
  """
  @spec prioritize([String.t()], pos_integer()) :: [String.t()]
  def prioritize(files, budget) when length(files) <= budget, do: files

  def prioritize(files, budget) do
    files
    |> Enum.sort_by(&significance/1, :desc)
    |> Enum.take(budget)
  end

  @doc """
  Prioritize files and return count of deferred files.

  Returns `{kept_files, deferred_count}`.
  """
  @spec prioritize_with_info([String.t()], pos_integer()) :: {[String.t()], non_neg_integer()}
  def prioritize_with_info(files, budget) do
    kept = prioritize(files, budget)
    {kept, length(files) - length(kept)}
  end

  # -- Private --

  defp skip_dir?(path, skip_dirs) do
    Enum.any?(skip_dirs, fn dir ->
      dir_prefix = String.trim_trailing(dir, "/")
      String.starts_with?(path, dir_prefix <> "/") or path == dir_prefix or path == dir
    end)
  end

  defp skip_file?(path) do
    Path.basename(path) in @skip_files
  end

  defp skip_extension?(path) do
    ext = Path.extname(path)

    if ext == "" do
      false
    else
      ext in @skip_extensions or double_ext_skip?(path)
    end
  end

  defp double_ext_skip?(path) do
    # Handle .min.js, .min.css, .js.map patterns
    basename = Path.basename(path)

    String.ends_with?(basename, ".min.js") or
      String.ends_with?(basename, ".min.css") or
      String.ends_with?(basename, ".js.map")
  end

  defp test_file?(path) do
    Enum.any?(@test_patterns, &Regex.match?(&1, path))
  end
end
