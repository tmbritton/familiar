defmodule Familiar.Knowledge.FileClassifier do
  @moduledoc """
  File classification and significance scoring for the init scanner.

  Classifies project files as `:index` or `:skip` based on configurable
  patterns for directories and file extensions. Provides significance
  scoring for large-project prioritization.

  Accepts an optional `:indexing` config map (from `Familiar.Config`) to
  override the built-in defaults. When no config is passed, falls back to
  the module attributes.
  """

  @skip_dirs ~w(
    .git/ vendor/ node_modules/ _build/ deps/ .elixir_ls/ .familiar/
    __pycache__/ .tox/ .mypy_cache/ target/ dist/ build/
  )

  @skip_extensions ~w(
    .beam .pyc .pyo .class .o .so .dylib .min.js .min.css .map
    .png .jpg .jpeg .gif .bmp .ico .svg .webp .avif
    .woff .woff2 .ttf .eot .otf
    .pdf .zip .tar .gz .bz2 .xz .7z .rar
    .mp3 .mp4 .wav .ogg .webm .avi .mov
    .exe .dll .bin .dat .db .sqlite .sqlite3
  )

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

  Options:
  - `:indexing` — indexing config map from `Familiar.Config` (overrides defaults)
  - `:skip_dirs` — additional directory patterns to skip (merged with config/defaults)
  """
  @spec classify(String.t(), keyword()) :: :index | :skip
  def classify(path, opts \\ []) do
    indexing = Keyword.get(opts, :indexing)
    extra_skip_dirs = Keyword.get(opts, :skip_dirs, [])
    all_skip_dirs = idx(indexing, :skip_dirs, @skip_dirs) ++ extra_skip_dirs

    cond do
      skip_dir?(path, all_skip_dirs) -> :skip
      skip_file?(path, idx(indexing, :skip_files, @skip_files)) -> :skip
      skip_extension?(path, idx(indexing, :skip_extensions, @skip_extensions)) -> :skip
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
  @spec significance(String.t(), keyword()) :: pos_integer()
  def significance(path, opts \\ []) do
    indexing = Keyword.get(opts, :indexing)
    basename = Path.basename(path)
    ext = Path.extname(path)

    source_exts = idx(indexing, :source_extensions, @source_extensions)
    cfg_files = idx(indexing, :config_files, @config_files)
    cfg_exts = idx(indexing, :config_extensions, @config_extensions)
    doc_exts = idx(indexing, :doc_extensions, @doc_extensions)
    test_pats = idx(indexing, :test_patterns, @test_patterns) |> ensure_regexes()

    cond do
      ext in source_exts and not test_file?(path, test_pats) -> 100
      basename in cfg_files -> 80
      ext in cfg_exts -> 80
      test_file?(path, test_pats) -> 50
      ext in doc_exts -> 50
      true -> 10
    end
  end

  @doc """
  Prioritize files by significance, returning at most `budget` files.

  Returns the list unchanged if under budget.
  """
  @spec prioritize([String.t()], pos_integer(), keyword()) :: [String.t()]
  def prioritize(files, budget, opts \\ [])
  def prioritize(files, budget, _opts) when length(files) <= budget, do: files

  def prioritize(files, budget, opts) do
    files
    |> Enum.sort_by(&significance(&1, opts), :desc)
    |> Enum.take(budget)
  end

  @doc """
  Prioritize files and return count of deferred files.

  Returns `{kept_files, deferred_count}`.
  """
  @spec prioritize_with_info([String.t()], pos_integer(), keyword()) ::
          {[String.t()], non_neg_integer()}
  def prioritize_with_info(files, budget, opts \\ []) do
    kept = prioritize(files, budget, opts)
    {kept, length(files) - length(kept)}
  end

  # -- Private --

  defp idx(nil, _key, default), do: default
  defp idx(indexing, key, default), do: Map.get(indexing, key, default)

  defp ensure_regexes(patterns) do
    Enum.map(patterns, fn
      %Regex{} = r -> r
      s when is_binary(s) -> Regex.compile!(s)
    end)
  end

  defp skip_dir?(path, skip_dirs) do
    Enum.any?(skip_dirs, fn dir ->
      dir_prefix = String.trim_trailing(dir, "/")
      String.starts_with?(path, dir_prefix <> "/") or path == dir_prefix or path == dir
    end)
  end

  defp skip_file?(path, skip_files) do
    Path.basename(path) in skip_files
  end

  defp skip_extension?(path, skip_extensions) do
    ext = Path.extname(path)

    if ext == "" do
      false
    else
      ext in skip_extensions or double_ext_skip?(path)
    end
  end

  defp double_ext_skip?(path) do
    # Handle .min.js, .min.css, .js.map patterns
    basename = Path.basename(path)

    String.ends_with?(basename, ".min.js") or
      String.ends_with?(basename, ".min.css") or
      String.ends_with?(basename, ".js.map")
  end

  defp test_file?(path, test_patterns) do
    Enum.any?(test_patterns, &Regex.match?(&1, path))
  end
end
