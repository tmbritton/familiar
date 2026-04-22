defmodule Familiar.Knowledge.Management do
  @moduledoc """
  Administrative operations for the knowledge store.

  Handles project re-scan (refresh) and entry consolidation (compact).
  Separated from the main Knowledge module which handles CRUD/search.
  """

  require Logger

  import Ecto.Query

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Extractor
  alias Familiar.Knowledge.InitScanner
  alias Familiar.Knowledge.SecretFilter
  alias Familiar.Providers
  alias Familiar.Repo

  @max_entries_load 5000

  @doc """
  Delete all knowledge entries and their embeddings.

  Used by `--force` refresh to start from a clean slate.
  """
  @spec clear_all_entries() :: {:ok, non_neg_integer()}
  def clear_all_entries do
    Repo.query!("DELETE FROM knowledge_entry_embeddings", [])
    {count, _} = from(e in Entry) |> Repo.delete_all()
    {:ok, count}
  end

  @doc """
  Refresh the knowledge store by re-scanning files.

  Re-extracts and re-embeds auto-generated entries. User-source entries
  are preserved. New files are indexed, deleted files' entries removed.

  Options:
  - `:path` — optional path filter (only scan files under this path)
  - `:file_system` — FileSystem implementation (DI)
  - `:llm` — LLM implementation (DI)
  - `:scan_fn` — override file scanning (DI, for testing)
  """
  @spec refresh(String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def refresh(project_dir, opts \\ []) do
    path_filter = Keyword.get(opts, :path)
    fs = file_system(opts)
    scan_fn = Keyword.get(opts, :scan_fn, &InitScanner.scan_files/2)
    progress_fn = Keyword.get(opts, :progress_fn, fn _msg -> :ok end)

    with {:ok, files, _deferred} <- scan_fn.(project_dir, opts) do
      files = filter_by_path(files, path_filter)
      progress_fn.("Scanning #{length(files)} files...")
      existing_entries = load_existing_entries(path_filter)

      {updated, created, preserved} =
        process_files(files, existing_entries, fs, project_dir, progress_fn, opts)

      removed = remove_orphaned_entries(files, existing_entries, fs)

      {:ok,
       %{
         scanned: length(files),
         updated: updated,
         created: created,
         removed: removed,
         preserved: preserved
       }}
    end
  end

  @doc """
  Find consolidation candidates — entry pairs with high semantic similarity.

  Returns pairs with cosine distance < 0.3 and same type.
  """
  @spec find_consolidation_candidates(keyword()) :: {:ok, %{candidates: [map()]}}
  def find_consolidation_candidates(_opts \\ []) do
    entries = from(e in Entry, limit: @max_entries_load) |> Repo.all()

    candidates =
      entries
      |> find_similar_pairs()
      |> Enum.sort_by(& &1.distance)

    {:ok, %{candidates: candidates}}
  end

  @doc """
  Compact entries by merging the given pairs.

  For each pair, keeps the longer entry, appends unique info from the shorter,
  re-embeds the merged text, and deletes the shorter entry.
  """
  @spec compact([{integer(), integer()}], keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def compact(pairs, _opts \\ []) do
    results =
      Enum.map(pairs, fn {id_a, id_b} ->
        merge_pair(id_a, id_b)
      end)

    merged = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    if merged == 0 and failed > 0 do
      {:error, {:compact_failed, %{merged: 0, failed: failed}}}
    else
      {:ok, %{merged: merged, failed: failed}}
    end
  end

  # -- Refresh internals --

  defp filter_by_path(files, nil), do: files

  defp filter_by_path(files, path_prefix) do
    Enum.filter(files, fn file ->
      relative = file_relative_path(file)
      String.starts_with?(relative, path_prefix)
    end)
  end

  defp file_relative_path(%{relative_path: path}), do: path
  defp file_relative_path(path) when is_binary(path), do: path

  defp load_existing_entries(nil) do
    entries = from(e in Entry, limit: @max_entries_load) |> Repo.all()

    if length(entries) >= @max_entries_load,
      do: Logger.warning("Entry load capped at #{@max_entries_load} — results may be incomplete")

    entries
  end

  defp load_existing_entries(path_prefix) do
    escaped = escape_like(path_prefix)

    entries =
      from(e in Entry, where: like(e.source_file, ^"#{escaped}%"), limit: @max_entries_load)
      |> Repo.all()

    if length(entries) >= @max_entries_load,
      do: Logger.warning("Entry load capped at #{@max_entries_load} — results may be incomplete")

    entries
  end

  defp escape_like(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @default_concurrency 10

  defp process_files(files, existing_entries, fs, project_dir, progress_fn, opts) do
    entries_by_file = Enum.group_by(existing_entries, & &1.source_file)
    total = length(files)
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    counter = :counters.new(1, [:atomics])

    # Prepare work items: read files and classify as new/existing/unreadable
    work_items =
      Enum.map(files, fn file ->
        relative = file_relative_path(file)
        file_entries = Map.get(entries_by_file, relative, [])

        {user_entries, auto_entries} =
          Enum.split_with(file_entries, &(&1.source == "user"))

        abs_path = Path.join(project_dir, relative)

        %{
          relative: relative,
          abs_path: abs_path,
          user_count: length(user_entries),
          auto_entries: auto_entries,
          file_content: read_file(fs, abs_path)
        }
      end)

    results =
      work_items
      |> Task.async_stream(
        fn item ->
          :counters.add(counter, 1, 1)
          idx = :counters.get(counter, 1)
          process_single_file(item, idx, total, progress_fn, opts)
        end,
        max_concurrency: concurrency,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, counts} -> counts
        {:exit, _} -> {0, 0, 0}
      end)

    Enum.reduce(results, {0, 0, 0}, fn {u, c, p}, {au, ac, ap} ->
      {au + u, ac + c, ap + p}
    end)
  end

  defp process_single_file(item, idx, total, progress_fn, opts) do
    case {item.auto_entries, item.file_content} do
      {_, {:error, _}} ->
        {0, 0, item.user_count}

      {[], {:ok, content}} ->
        progress_fn.("[#{idx}/#{total}] Extracting knowledge from #{item.relative}...")
        new_count = create_entries_for_file(item.relative, content, progress_fn, opts)

        if new_count > 0,
          do: progress_fn.("[#{idx}/#{total}] Saved #{new_count} entries for #{item.relative}"),
          else: progress_fn.("[#{idx}/#{total}] No entries extracted for #{item.relative}")

        {0, new_count, item.user_count}

      {auto, {:ok, content}} ->
        progress_fn.("[#{idx}/#{total}] Refreshing #{item.relative}...")
        re_count = refresh_entries(auto, item.relative, content, opts)
        {re_count, 0, item.user_count}
    end
  end

  defp read_file(fs, path) do
    fs.read(path)
  end

  defp create_entries_for_file(relative_path, content, progress_fn, _opts) do
    entries =
      Extractor.extract_from_file(%{
        relative_path: relative_path,
        content: content
      })

    if entries != [] do
      progress_fn.("  Embedding #{length(entries)} entries for #{relative_path}...")
    end

    Enum.count(entries, fn entry_attrs ->
      attrs = %{
        text: SecretFilter.filter(entry_attrs.text),
        type: entry_attrs.type,
        source: "init_scan",
        source_file: relative_path
      }

      match?({:ok, _}, Knowledge.store_with_embedding(attrs))
    end)
  end

  defp refresh_entries(existing_entries, relative_path, content, _opts) do
    new_entries =
      Extractor.extract_from_file(%{
        relative_path: relative_path,
        content: content
      })

    case new_entries do
      [] ->
        0

      _ ->
        existing_by_type = Enum.group_by(existing_entries, & &1.type)

        {updated, created} =
          Enum.reduce(new_entries, {0, 0}, fn extracted, acc ->
            refresh_single_entry(extracted, existing_by_type, relative_path, acc)
          end)

        updated + created
    end
  end

  defp refresh_single_entry(extracted, existing_by_type, relative_path, {upd, cre}) do
    new_text = SecretFilter.filter(extracted.text)
    type = extracted[:type] || "file_summary"

    case Map.get(existing_by_type, type) do
      [target | _] ->
        if update_entry_succeeded?(target, new_text), do: {upd + 1, cre}, else: {upd, cre}

      _ ->
        attrs = %{text: new_text, type: type, source: "init_scan", source_file: relative_path}

        if match?({:ok, _}, Knowledge.store_with_embedding(attrs)),
          do: {upd, cre + 1},
          else: {upd, cre}
    end
  end

  defp update_entry_succeeded?(entry, new_text) do
    match?(:ok, update_entry_text(entry, new_text))
  end

  defp update_entry_text(entry, new_text) do
    with {:ok, vector} <- Providers.embed(new_text),
         changeset = Entry.changeset(entry, %{text: new_text}),
         {:ok, _updated} <- Repo.update(changeset) do
      Knowledge.replace_embedding(entry.id, vector)
    end
  end

  defp remove_orphaned_entries(files, existing_entries, fs) do
    scanned_paths = MapSet.new(files, &file_relative_path/1)

    existing_entries
    |> Enum.reject(
      &(is_nil(&1.source_file) or &1.source == "user" or
          MapSet.member?(scanned_paths, &1.source_file))
    )
    |> Enum.filter(&file_deleted?(&1, fs))
    |> Enum.count(&match?(:ok, Knowledge.delete_entry(&1)))
  end

  defp file_deleted?(entry, fs) do
    case fs.stat(entry.source_file) do
      {:error, {:file_error, %{reason: :enoent}}} -> true
      {:error, :enoent} -> true
      _ -> false
    end
  end

  # -- Compact internals --

  @duplicate_threshold 0.3

  defp find_similar_pairs(entries) do
    entries
    |> Enum.flat_map(&find_matches_for_entry/1)
    |> Enum.uniq_by(fn {a, b, _, _, _} -> {a, b} end)
    |> Enum.map(&format_candidate/1)
  end

  defp find_matches_for_entry(entry) do
    case Knowledge.search_similar_by_entry_id(entry.id, limit: 5) do
      {:ok, results} -> filter_and_pair(entry, results)
      {:error, _} -> []
    end
  end

  defp filter_and_pair(entry, results) do
    results
    |> Enum.filter(fn %{entry: other, distance: d} ->
      other.id != entry.id and d < @duplicate_threshold and other.type == entry.type
    end)
    |> Enum.map(fn %{entry: other, distance: d} ->
      {min(entry.id, other.id), max(entry.id, other.id), entry, other, d}
    end)
  end

  defp format_candidate({id_a, id_b, entry_a, entry_b, distance}) do
    %{
      id_a: id_a,
      id_b: id_b,
      text_a: entry_a.text,
      text_b: entry_b.text,
      type: entry_a.type,
      distance: distance
    }
  end

  defp merge_pair(id_a, id_b) do
    with {:ok, entry_a} <- Knowledge.fetch_entry(id_a),
         {:ok, entry_b} <- Knowledge.fetch_entry(id_b) do
      {keeper, to_delete} =
        if String.length(entry_a.text) >= String.length(entry_b.text),
          do: {entry_a, entry_b},
          else: {entry_b, entry_a}

      merged_text = merge_texts(keeper.text, to_delete.text)

      with {:ok, vector} <- Providers.embed(merged_text),
           changeset = Entry.changeset(keeper, %{text: merged_text}),
           {:ok, updated} <- Repo.update(changeset),
           :ok <- Knowledge.replace_embedding(updated.id, vector),
           :ok <- Knowledge.delete_entry(to_delete) do
        {:ok, updated}
      end
    end
  end

  defp merge_texts(keeper_text, shorter_text) do
    # Split into sentences and only append sentences not already in keeper
    keeper_sentences = MapSet.new(split_sentences(keeper_text))

    new_sentences =
      shorter_text
      |> split_sentences()
      |> Enum.reject(&MapSet.member?(keeper_sentences, &1))

    merged =
      case new_sentences do
        [] -> keeper_text
        additions -> keeper_text <> " " <> Enum.join(additions, " ")
      end

    SecretFilter.filter(merged)
  end

  defp split_sentences(text) do
    text
    |> String.split(~r/[.!?]\s+|\n+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # -- DI --

  defp file_system(opts) do
    Keyword.get_lazy(opts, :file_system, fn ->
      Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
    end)
  end
end
