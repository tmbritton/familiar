defmodule Familiar.Knowledge.Freshness do
  @moduledoc """
  Freshness validation for knowledge entries.

  Stat-checks referenced source files against the filesystem to detect
  stale or deleted entries. Fails open with warnings rather than blocking.
  """

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Extractor
  alias Familiar.Repo

  @type result :: %{
          fresh: [Entry.t()],
          stale: [Entry.t()],
          deleted: [Entry.t()],
          warnings: [String.t()]
        }

  @doc """
  Validate freshness of knowledge entries by stat-checking their source files.

  Returns `{:ok, %{fresh: [...], stale: [...], deleted: [...], warnings: [...]}}`.

  Entries without a `source_file` are always treated as fresh.
  File stat errors (other than `:enoent`) are fail-open: entry treated as fresh with a warning.
  """
  @spec validate_entries([Entry.t()], keyword()) :: {:ok, result()}
  def validate_entries(entries, opts \\ []) do
    {with_file, without_file} = Enum.split_with(entries, &has_source_file?/1)

    fs = file_system(opts)

    entries_with_index = Enum.with_index(with_file)

    {classified, warnings} =
      entries_with_index
      |> Task.async_stream(fn {entry, _idx} -> classify_entry(entry, fs) end,
        timeout: 1_500,
        on_timeout: :kill_task
      )
      |> Enum.zip(with_file)
      |> Enum.map(fn
        {{:ok, result}, _entry} -> result
        {{:exit, :timeout}, entry} -> {:warn, entry, "Freshness stat timed out for #{entry.source_file} — treated as fresh"}
      end)
      |> Enum.reduce({%{fresh: [], stale: [], deleted: []}, []}, &accumulate/2)

    checked = classified.fresh ++ classified.stale ++ classified.deleted
    now = clock(opts).now()
    update_checked_at(checked, now)

    result = %{
      fresh: Enum.reverse(classified.fresh) ++ without_file,
      stale: Enum.reverse(classified.stale),
      deleted: Enum.reverse(classified.deleted),
      warnings: Enum.reverse(warnings)
    }

    {:ok, result}
  end

  defp has_source_file?(%{source_file: nil}), do: false
  defp has_source_file?(%{source_file: ""}), do: false
  defp has_source_file?(_), do: true

  defp classify_entry(entry, fs) do
    case fs.stat(entry.source_file) do
      {:ok, %{mtime: mtime}} ->
        if DateTime.compare(mtime, entry.updated_at) == :gt do
          {:stale, entry}
        else
          {:fresh, entry}
        end

      {:error, {:file_error, %{reason: :enoent}}} ->
        {:deleted, entry}

      {:error, _reason} ->
        {:warn, entry, "Freshness check failed for #{entry.source_file} — treated as fresh"}
    end
  end

  defp accumulate({:fresh, entry}, {classified, warnings}) do
    {%{classified | fresh: [entry | classified.fresh]}, warnings}
  end

  defp accumulate({:stale, entry}, {classified, warnings}) do
    {%{classified | stale: [entry | classified.stale]}, warnings}
  end

  defp accumulate({:deleted, entry}, {classified, warnings}) do
    {%{classified | deleted: [entry | classified.deleted]}, warnings}
  end

  defp accumulate({:warn, entry, warning}, {classified, warnings}) do
    {%{classified | fresh: [entry | classified.fresh]}, [warning | warnings]}
  end

  @doc """
  Refresh stale entries by re-reading source files, re-extracting knowledge,
  and re-embedding.

  For each stale entry:
  1. Read file content via FileSystem
  2. Re-extract knowledge via LLM (Extractor)
  3. Update entry text and re-embed

  Fails open: if refresh fails for any entry, the original entry is preserved.
  Returns `{:ok, %{refreshed: count, failed: count, warnings: [String.t()]}}`.
  """
  @spec refresh_stale([Entry.t()], keyword()) ::
          {:ok, %{refreshed: non_neg_integer(), failed: non_neg_integer(), warnings: [String.t()]}}
  def refresh_stale(entries, opts \\ []) do
    fs = file_system(opts)

    results = Enum.map(entries, &refresh_entry(&1, fs))

    refreshed = Enum.count(results, &match?(:ok, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    warnings =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, msg} -> msg end)

    {:ok, %{refreshed: refreshed, failed: failed, warnings: warnings}}
  end

  defp refresh_entry(entry, fs) do
    with {:ok, content} <- fs.read(entry.source_file),
         new_entries when new_entries != [] <-
           Extractor.extract_from_file(%{
             relative_path: entry.source_file,
             content: content
           }),
         new_text = hd(new_entries).text,
         {:ok, vector} <- Familiar.Providers.embed(new_text),
         changeset = Entry.changeset(entry, %{text: new_text}),
         {:ok, _updated} <- Repo.update(changeset),
         :ok <- Knowledge.replace_embedding(entry.id, vector) do
      :ok
    else
      [] ->
        {:error, "Refresh of #{entry.source_file} produced no entries — original preserved"}

      {:error, reason} ->
        {:error,
         "Refresh failed for #{entry.source_file}: #{inspect(reason)} — original preserved"}
    end
  end

  @doc """
  Remove entries whose source files have been deleted.

  Deletes the entry and its embedding from the database.
  Returns `{:ok, %{removed: count}}`.
  """
  @spec remove_deleted([Entry.t()]) :: {:ok, %{removed: non_neg_integer()}}
  def remove_deleted(entries) do
    results = Enum.map(entries, &Knowledge.delete_entry/1)
    removed = Enum.count(results, &match?(:ok, &1))
    {:ok, %{removed: removed}}
  end

  defp update_checked_at(entries, now) do
    ids = Enum.map(entries, & &1.id)

    if ids != [] do
      import Ecto.Query
      from(e in Entry, where: e.id in ^ids) |> Repo.update_all(set: [checked_at: now])
    end
  end

  defp file_system(opts) do
    Keyword.get_lazy(opts, :file_system, fn ->
      Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
    end)
  end

  defp clock(opts) do
    Keyword.get_lazy(opts, :clock, fn ->
      Application.get_env(:familiar, Familiar.System.Clock, Familiar.System.RealClock)
    end)
  end
end
