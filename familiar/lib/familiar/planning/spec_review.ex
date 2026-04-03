defmodule Familiar.Planning.SpecReview do
  @moduledoc """
  Spec review workflow: approve, reject, stat-check, and editor integration.

  Manages the lifecycle of a generated spec after the planning conversation
  completes. Handles status transitions (draft → approved/rejected),
  frontmatter rewriting, file modification detection, and $EDITOR integration.
  """

  alias Familiar.Planning.Spec
  alias Familiar.Repo

  @doc """
  Approve a spec.

  Stat-checks the file for external modifications. If modified, prompts
  for confirmation and re-reads the file content into DB. Updates status
  to "approved" in both DB and file frontmatter.

  Options:
  - `:file_system` — FileSystem behaviour module (DI)
  - `:confirm_fn` — function called when file was modified externally;
    receives prompt string, returns user response string. Default: `IO.gets/1`
  """
  @spec approve(Spec.t(), keyword()) :: {:ok, Spec.t()} | {:error, {atom(), map()}}
  def approve(%Spec{} = spec, opts \\ []) do
    with :ok <- validate_reviewable(spec),
         {:ok, spec} <- handle_modification_check(spec, opts),
         {:ok, spec} <- update_status(spec, "approved"),
         :ok <- update_frontmatter(spec, "approved", opts) do
      {:ok, spec}
    end
  end

  @doc """
  Reject a spec.

  Updates status to "rejected" in both DB and file frontmatter.

  Options:
  - `:file_system` — FileSystem behaviour module (DI)
  """
  @spec reject(Spec.t(), keyword()) :: {:ok, Spec.t()} | {:error, {atom(), map()}}
  def reject(%Spec{} = spec, opts \\ []) do
    with :ok <- validate_reviewable(spec),
         {:ok, spec} <- update_status(spec, "rejected"),
         :ok <- update_frontmatter(spec, "rejected", opts) do
      {:ok, spec}
    end
  end

  @doc """
  Check if a spec file was modified externally since last DB update.

  Returns `{:ok, %{modified: boolean, file_mtime: DateTime | nil}}`.
  Returns `{:error, {:file_missing, ...}}` if the file does not exist.
  """
  @spec stat_check(Spec.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def stat_check(%Spec{file_path: nil}, _opts) do
    {:error, {:no_file_path, %{}}}
  end

  def stat_check(%Spec{} = spec, opts \\ []) do
    fs = file_system(opts)

    case fs.stat(spec.file_path) do
      {:ok, %{mtime: mtime}} ->
        modified = compare_mtime(mtime, spec.updated_at)
        {:ok, %{modified: modified, file_mtime: mtime}}

      {:error, reason} ->
        {:error, {:file_missing, %{path: spec.file_path, reason: reason}}}
    end
  end

  @doc """
  Re-read the spec file and update the DB body if it was modified.

  Returns `{:ok, updated_spec}` or `{:ok, spec}` if unchanged.
  """
  @spec reload_if_modified(Spec.t(), keyword()) :: {:ok, Spec.t()} | {:error, {atom(), map()}}
  def reload_if_modified(%Spec{} = spec, opts \\ []) do
    case stat_check(spec, opts) do
      {:ok, %{modified: true}} -> do_reload(spec, opts)
      {:ok, %{modified: false}} -> {:ok, spec}
      {:error, _} = error -> error
    end
  end

  @doc """
  Open a spec file in `$EDITOR` via Shell behaviour.

  Resolves editor from `$EDITOR` environment variable with fallback to "vi".
  After the editor closes, stat-checks the file to detect modifications.

  Options:
  - `:shell_mod` — Shell behaviour module (DI)
  - `:file_system` — FileSystem behaviour module (DI)
  - `:editor_env` — override editor command (DI, for testing)
  """
  @spec open_in_editor(Spec.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def open_in_editor(%Spec{file_path: nil}, _opts) do
    {:error, {:no_file_path, %{}}}
  end

  def open_in_editor(%Spec{} = spec, opts \\ []) do
    shell = shell_mod(opts)
    editor = Keyword.get(opts, :editor_env, System.get_env("EDITOR") || "vi")

    case shell.cmd(editor, [spec.file_path], []) do
      {:ok, %{exit_code: 0}} ->
        stat_check(spec, opts)

      {:ok, %{exit_code: code}} ->
        {:error, {:editor_failed, %{exit_code: code, editor: editor}}}

      {:error, reason} ->
        {:error, {:editor_failed, %{reason: reason, editor: editor}}}
    end
  end

  # -- Private --

  defp validate_reviewable(%Spec{status: "draft"}), do: :ok

  defp validate_reviewable(%Spec{status: status}) do
    {:error, {:spec_not_reviewable, %{status: status}}}
  end

  # D3: handle_modification_check now returns {:ok, spec} — reloading if modified
  defp handle_modification_check(spec, opts) do
    case stat_check(spec, opts) do
      {:ok, %{modified: true}} ->
        with :ok <- confirm_modified_approval(opts) do
          reload_if_modified(spec, opts)
        end

      {:ok, %{modified: false}} ->
        {:ok, spec}

      {:error, _} ->
        {:ok, spec}
    end
  end

  defp confirm_modified_approval(opts) do
    confirm_fn = Keyword.get(opts, :confirm_fn, &IO.gets/1)
    prompt = "The spec was modified externally. Approve the edited version? (y/n): "

    case confirm_fn.(prompt) do
      response when is_binary(response) ->
        if String.starts_with?(String.trim(String.downcase(response)), "y"),
          do: :ok,
          else: {:error, {:approval_cancelled, %{}}}

      _ ->
        {:error, {:approval_cancelled, %{}}}
    end
  end

  defp update_status(spec, new_status) do
    spec
    |> Spec.changeset(%{status: new_status})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} -> {:error, {:status_update_failed, %{changeset: cs}}}
    end
  end

  # D4: Scope frontmatter regex to only the block between --- delimiters
  defp update_frontmatter(spec, new_status, opts) do
    fs = file_system(opts)

    case fs.read(spec.file_path) do
      {:ok, content} ->
        updated = replace_frontmatter_status(content, new_status)

        case fs.write(spec.file_path, updated) do
          :ok -> :ok
          {:error, reason} -> {:error, {:frontmatter_write_failed, %{reason: reason}}}
        end

      {:error, reason} ->
        {:error, {:frontmatter_read_failed, %{reason: reason}}}
    end
  end

  defp replace_frontmatter_status(content, new_status) do
    case String.split(content, "\n") do
      ["---" | rest] ->
        {fm_lines, after_fm} = split_frontmatter(rest)
        updated_fm = replace_status_in_lines(fm_lines, new_status)
        Enum.join(["---" | updated_fm] ++ after_fm, "\n")

      _ ->
        content
    end
  end

  defp replace_status_in_lines(lines, new_status) do
    Enum.map(lines, fn line ->
      if Regex.match?(~r/^status:\s*/, line),
        do: "status: #{new_status}",
        else: line
    end)
  end

  defp split_frontmatter(lines), do: split_frontmatter(lines, [])
  defp split_frontmatter([], acc), do: {Enum.reverse(acc), []}
  defp split_frontmatter(["---" | rest], acc), do: {Enum.reverse(acc), ["---" | rest]}
  defp split_frontmatter([line | rest], acc), do: split_frontmatter(rest, [line | acc])

  defp do_reload(spec, opts) do
    fs = file_system(opts)

    case fs.read(spec.file_path) do
      {:ok, content} ->
        body = extract_body(content)
        persist_reload(spec, body)

      {:error, reason} ->
        {:error, {:file_read_failed, %{reason: reason}}}
    end
  end

  defp persist_reload(spec, body) do
    spec
    |> Spec.changeset(%{body: body})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} -> {:error, {:reload_failed, %{changeset: cs}}}
    end
  end

  defp extract_body(content) do
    case Regex.split(~r/^---\s*$/m, content, parts: 3) do
      [_, _frontmatter, body] -> String.trim(body)
      _ -> content
    end
  end

  # P5: Guard against nil updated_at
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
