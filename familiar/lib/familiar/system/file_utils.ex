defmodule Familiar.System.FileUtils do
  @moduledoc """
  Generic file utilities: stat-check for external modifications,
  editor integration, and file body reload.

  These work with any struct/map that has `file_path` and `updated_at`
  fields. Used by spec review, and available to any process that needs
  to detect external file edits or open files in `$EDITOR`.
  """

  require Logger

  @doc """
  Check if a file was modified externally since a reference timestamp.

  Takes a file path and a reference `DateTime` (e.g., a record's `updated_at`).
  Returns `{:ok, %{modified: boolean, file_mtime: DateTime | nil}}`.
  Returns `{:error, {:file_missing, ...}}` if the file does not exist.

  Options:
  - `:file_system` — FileSystem behaviour module (DI)
  """
  @spec stat_check(String.t(), DateTime.t() | nil, keyword()) ::
          {:ok, map()} | {:error, {atom(), map()}}
  def stat_check(file_path, reference_time, opts \\ [])

  def stat_check(nil, _reference_time, _opts) do
    {:error, {:no_file_path, %{}}}
  end

  def stat_check(file_path, reference_time, opts) do
    fs = file_system(opts)

    case fs.stat(file_path) do
      {:ok, %{mtime: mtime}} ->
        modified = compare_mtime(mtime, reference_time)
        {:ok, %{modified: modified, file_mtime: mtime}}

      {:error, reason} ->
        {:error, {:file_missing, %{path: file_path, reason: reason}}}
    end
  end

  @doc """
  Open a file in `$EDITOR` via Shell behaviour.

  Resolves editor from `$EDITOR` environment variable with fallback to "vi".
  After the editor closes, stat-checks the file to detect modifications.

  Options:
  - `:shell_mod` — Shell behaviour module (DI)
  - `:file_system` — FileSystem behaviour module (DI)
  - `:editor_env` — override editor command (DI, for testing)
  """
  @spec open_in_editor(String.t(), DateTime.t() | nil, keyword()) ::
          {:ok, map()} | {:error, {atom(), map()}}
  def open_in_editor(file_path, reference_time, opts \\ [])

  def open_in_editor(nil, _reference_time, _opts) do
    {:error, {:no_file_path, %{}}}
  end

  def open_in_editor(file_path, reference_time, opts) do
    shell = shell_mod(opts)
    editor = Keyword.get(opts, :editor_env, System.get_env("EDITOR") || "vi")

    case shell.cmd(editor, [file_path], []) do
      {:ok, %{exit_code: 0}} ->
        stat_check(file_path, reference_time, opts)

      {:ok, %{exit_code: code}} ->
        {:error, {:editor_failed, %{exit_code: code, editor: editor}}}

      {:error, reason} ->
        {:error, {:editor_failed, %{reason: reason, editor: editor}}}
    end
  end

  @doc """
  Read a file and return the body content below YAML frontmatter.

  Splits on `---` delimiters and returns the content after the
  closing delimiter, trimmed.
  """
  @spec read_body(String.t(), keyword()) :: {:ok, String.t()} | {:error, {atom(), map()}}
  def read_body(file_path, opts \\ []) do
    fs = file_system(opts)

    case fs.read(file_path) do
      {:ok, content} -> {:ok, extract_body(content)}
      {:error, reason} -> {:error, {:file_read_failed, %{reason: reason}}}
    end
  end

  @doc """
  Extract the body content from a markdown string with YAML frontmatter.

  Returns content after the closing `---` delimiter, trimmed.
  If no frontmatter is found, returns the full content.
  """
  @spec extract_body(String.t()) :: String.t()
  def extract_body(content) do
    case Regex.split(~r/^---\s*$/m, content, parts: 3) do
      [_, _frontmatter, body] -> String.trim(body)
      _ -> content
    end
  end

  @doc """
  Validate that a file path is relative and does not escape the project directory.

  Returns `:ok` for valid paths or `{:error, reason}` for invalid ones.
  """
  @spec validate_path(String.t()) :: :ok | {:error, String.t()}
  def validate_path(path) when is_binary(path) and byte_size(path) > 0 do
    if String.starts_with?(path, "/") or String.contains?(path, "..") do
      {:error, "path must be relative and within the project (got: #{path})"}
    else
      :ok
    end
  end

  def validate_path(_), do: {:error, "path must be a non-empty string"}

  # -- Private --

  defp compare_mtime(_mtime, nil), do: true
  defp compare_mtime(mtime, updated_at), do: DateTime.compare(mtime, updated_at) == :gt

  defp file_system(opts) do
    Keyword.get_lazy(opts, :file_system, fn ->
      Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
    end)
  end

  defp shell_mod(opts) do
    Keyword.get_lazy(opts, :shell_mod, fn ->
      Application.get_env(:familiar, Familiar.System.Shell, Familiar.System.RealShell)
    end)
  end
end
