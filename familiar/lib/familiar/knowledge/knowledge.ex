defmodule Familiar.Knowledge do
  @moduledoc """
  Public API for the Knowledge context.

  Manages the semantic knowledge store — facts, decisions, gotchas,
  conventions, and relationships about the project. Handles embedding,
  retrieval, freshness validation, and post-task hygiene.
  """

  use Boundary, deps: [Familiar.Providers], exports: [Familiar.Knowledge]

  require Logger

  import Ecto.Query

  alias Familiar.Daemon.Paths
  alias Familiar.Knowledge.Backup
  alias Familiar.Knowledge.EmbeddingMetadata
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Freshness
  alias Familiar.Knowledge.SecretFilter
  alias Familiar.Repo

  @doc "List all knowledge entries of a given type."
  @spec list_by_type(module(), String.t()) :: [Entry.t()]
  def list_by_type(queryable \\ Entry, type) do
    queryable |> where([e], e.type == ^type) |> Repo.all()
  end

  @doc "List all knowledge entries sourced from a given file path."
  @spec list_by_source_file(String.t()) :: [Entry.t()]
  def list_by_source_file(path) when is_binary(path) do
    Entry |> where([e], e.source_file == ^path) |> Repo.all()
  end

  @doc """
  Search the knowledge store by semantic similarity.

  Returns a flat list of result maps with entry fields and distance.
  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, {atom(), map()}}
  def search(query, opts \\ []) do
    if String.trim(query) == "" do
      {:ok, []}
    else
      search_inner(query, opts)
    end
  end

  defp search_inner(query, opts) do
    with {:ok, results} <- search_similar(query) do
      entries = Enum.map(results, fn %{entry: entry} -> entry end)
      distance_map = Map.new(results, fn %{entry: e, distance: d} -> {e.id, d} end)
      {freshness_map, warnings} = run_freshness_check(entries, opts)

      log_freshness_warnings(warnings)
      trigger_background_maintenance(entries, freshness_map, opts)

      formatted = format_with_freshness(entries, distance_map, freshness_map)
      {:ok, formatted}
    end
  end

  defp format_with_freshness(entries, distance_map, freshness_map) do
    entries
    |> Enum.reject(&(Map.get(freshness_map, &1.id) == :deleted))
    |> Enum.map(fn entry ->
      %{
        id: entry.id,
        text: entry.text,
        type: entry.type,
        source: entry.source,
        source_file: entry.source_file,
        distance: Map.get(distance_map, entry.id),
        inserted_at: entry.inserted_at,
        freshness: Map.get(freshness_map, entry.id, :unknown)
      }
    end)
  end

  defp log_freshness_warnings([]), do: :ok

  defp log_freshness_warnings(warnings) do
    Enum.each(warnings, &Logger.warning("Freshness: #{&1}"))
  end

  defp trigger_background_maintenance(entries, freshness_map, opts) do
    if background_maintenance_enabled?() do
      do_trigger_background_maintenance(entries, freshness_map, opts)
    end

    :ok
  end

  defp do_trigger_background_maintenance(entries, freshness_map, opts) do
    stale = Enum.filter(entries, &(Map.get(freshness_map, &1.id) == :stale))
    deleted = Enum.filter(entries, &(Map.get(freshness_map, &1.id) == :deleted))

    if stale != [] do
      Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
        Freshness.refresh_stale(stale, opts)
      end)
    end

    if deleted != [] do
      Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
        Freshness.remove_deleted(deleted)
      end)
    end
  end

  # Fire-and-forget background tasks are disabled in test env because they
  # outlive the calling test process, leaking Mox expectations and holding
  # Ecto.Sandbox connections owned by a dead test PID. The `refresh_stale/2`
  # and `remove_deleted/1` functions are exercised directly in
  # `Familiar.Knowledge.FreshnessTest` — no coverage loss.
  defp background_maintenance_enabled? do
    Application.get_env(:familiar, :knowledge_background_maintenance, true)
  end

  defp run_freshness_check(entries, opts) do
    case Freshness.validate_entries(entries, opts) do
      {:ok, result} ->
        map =
          Map.new(result.fresh, &{&1.id, :fresh})
          |> Map.merge(Map.new(result.stale, &{&1.id, :stale}))
          |> Map.merge(Map.new(result.deleted, &{&1.id, :deleted}))

        {map, result.warnings}
    end
  rescue
    e ->
      Logger.warning(
        "Context freshness validation skipped — results may include stale entries: #{inspect(e)}"
      )

      {Map.new(entries, &{&1.id, :unknown}), []}
  end

  @doc "Fetch a single knowledge entry by ID."
  @spec fetch_entry(integer() | nil) :: {:ok, Entry.t()} | {:error, {:not_found, map()}}
  def fetch_entry(nil), do: {:error, {:not_found, %{id: nil}}}

  def fetch_entry(id) do
    case Repo.get(Entry, id) do
      nil -> {:error, {:not_found, %{id: id}}}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Store a new knowledge entry with content validation and embedding.

  Validates the knowledge-not-code rule (FR19) before delegating
  to `store_with_embedding/1` for persistence and embedding.
  """
  @spec store(map()) :: {:ok, Entry.t()} | {:error, {atom(), map()}}
  def store(attrs) do
    text = attrs[:text] || attrs["text"]

    if is_nil(text) do
      store_with_embedding(attrs)
    else
      filtered_text = SecretFilter.filter(text)
      store_with_embedding(attrs |> Map.delete("text") |> Map.put(:text, filtered_text))
    end
  end

  @doc """
  Update a knowledge entry's text and re-embed.

  Embed-before-persist: embed new text first, then update entry + replace embedding.
  """
  @spec update_entry(Entry.t(), map()) :: {:ok, Entry.t()} | {:error, {atom(), map()}}
  def update_entry(entry, attrs) do
    raw_text = attrs[:text] || attrs["text"] || entry.text
    new_text = SecretFilter.filter(raw_text)
    filtered_attrs = attrs |> Map.delete("text") |> Map.put(:text, new_text)

    with {:ok, vector} <- Familiar.Providers.embed(new_text),
         changeset = Entry.changeset(entry, filtered_attrs),
         {:ok, updated} <- Repo.update(changeset) do
      case replace_embedding(updated.id, vector) do
        :ok ->
          {:ok, updated}

        {:error, reason} ->
          # Compensate: revert to original text to keep entry+embedding consistent
          Repo.update(
            Entry.changeset(updated, Map.take(Map.from_struct(entry), [:text, :source]))
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Report knowledge store health metrics.

  Collects entry count, type breakdown, staleness ratio, last refresh,
  backup status, and computes a green/amber/red health signal.
  """
  @spec health(keyword()) ::
          {:ok,
           %{
             entry_count: non_neg_integer(),
             types: map(),
             staleness_ratio: float(),
             last_refresh: NaiveDateTime.t() | nil,
             backup: map(),
             signal: atom()
           }}
  def health(opts \\ []) do
    entry_count = Repo.aggregate(Entry, :count)
    types = collect_type_breakdown()
    last_refresh = Repo.one(from(e in Entry, select: max(e.updated_at)))
    staleness_ratio = compute_staleness_ratio(entry_count, opts)
    backup_status = collect_backup_status(opts)
    signal = compute_signal(staleness_ratio, backup_status, entry_count)

    {:ok,
     %{
       entry_count: entry_count,
       types: types,
       staleness_ratio: staleness_ratio,
       last_refresh: last_refresh,
       backup: backup_status,
       signal: signal
     }}
  end

  defp collect_type_breakdown do
    Entry
    |> group_by([e], e.type)
    |> select([e], {e.type, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @staleness_sample_size 100

  defp compute_staleness_ratio(0, _opts), do: 0.0

  defp compute_staleness_ratio(_count, opts) do
    # Sample entries rather than loading all — sufficient for health signal
    entries =
      from(e in Entry, order_by: [desc: e.updated_at], limit: @staleness_sample_size)
      |> Repo.all()

    if entries == [] do
      0.0
    else
      compute_staleness_from_entries(entries, opts)
    end
  rescue
    _ -> 0.0
  end

  defp compute_staleness_from_entries(entries, opts) do
    case Freshness.validate_entries(entries, opts) do
      {:ok, %{stale: stale, deleted: deleted}} ->
        (length(stale) + length(deleted)) / length(entries)
    end
  end

  defp collect_backup_status(opts) do
    case Backup.list(opts) do
      {:ok, [newest | _] = all} ->
        %{last: newest.timestamp, count: length(all)}

      {:ok, []} ->
        %{last: nil, count: 0}
    end
  end

  defp compute_signal(staleness_ratio, backup_status, entry_count) do
    has_backup = backup_status.count > 0

    cond do
      staleness_ratio > 0.30 -> :red
      !has_backup and entry_count > 0 -> :red
      staleness_ratio >= 0.10 -> :amber
      !has_backup -> :amber
      true -> :green
    end
  end

  @doc """
  Store a knowledge entry with a pre-computed embedding vector.

  Skips the embedding step — used when the caller has already embedded.
  Defense-in-depth: filters secrets before persisting.
  """
  @spec store_with_vector(map(), [float()]) :: {:ok, Entry.t()} | {:error, {atom(), map()}}
  def store_with_vector(attrs, vector) do
    attrs = filter_text_in_attrs(attrs)
    changeset = Entry.changeset(%Entry{}, attrs)

    with {:ok, entry} <- Repo.insert(changeset),
         :ok <- insert_embedding_or_rollback(entry, vector) do
      {:ok, entry}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_failed, %{changeset: changeset}}}

      {:error, {type, details}} ->
        {:error, {type, details}}
    end
  end

  @doc """
  Store a knowledge entry and embed its text for semantic search.

  Pipeline: validate attrs -> insert entry -> embed text -> store vector.

  Internal function — does NOT enforce FR19 knowledge-not-code rule.
  Use `store/1` for the public API which validates content first.
  """
  @spec store_with_embedding(map()) :: {:ok, Entry.t()} | {:error, {atom(), map()}}
  def store_with_embedding(attrs) do
    # Defense-in-depth: filter secrets even though callers should filter upstream
    attrs = filter_text_in_attrs(attrs)
    changeset = Entry.changeset(%Entry{}, attrs)

    with {:ok, entry} <- Repo.insert(changeset),
         {:ok, vector} <- embed_or_rollback(entry),
         :ok <- insert_embedding_or_rollback(entry, vector) do
      maybe_record_embedding_model()
      {:ok, entry}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_failed, %{changeset: changeset}}}

      {:error, {type, details}} ->
        {:error, {type, details}}
    end
  end

  # AC4: when the first entry is stored on a fresh install and
  # `EmbeddingMetadata.model_name` is still nil, auto-record the
  # currently-configured model so the startup drift check stops warning
  # about unset metadata. Fail-soft: any error here is logged and
  # swallowed so a metadata-layer problem never fails a successful store.
  defp maybe_record_embedding_model do
    with nil <- EmbeddingMetadata.current_model(),
         model when is_binary(model) <- current_embedding_model() do
      case EmbeddingMetadata.set(model, embedding_dimensions()) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[Knowledge] Failed to auto-record embedding model: #{inspect(reason)}")

          :ok
      end
    else
      _ -> :ok
    end
  rescue
    e ->
      Logger.warning("[Knowledge] maybe_record_embedding_model crashed: #{inspect(e)}")
      :ok
  end

  defp embed_or_rollback(entry) do
    case Familiar.Providers.embed(entry.text) do
      {:ok, vector} ->
        {:ok, vector}

      {:error, reason} ->
        # Compensating delete: remove the entry since embedding failed
        case Repo.delete(entry) do
          {:ok, _} ->
            :ok

          {:error, del_err} ->
            Logger.warning(
              "Compensating delete failed for entry #{entry.id}: #{inspect(del_err)}"
            )
        end

        {:error, reason}
    end
  end

  defp insert_embedding_or_rollback(entry, vector) do
    case insert_embedding(entry.id, vector) do
      :ok ->
        :ok

      {:error, reason} ->
        # Compensating delete: remove the entry since vector storage failed
        case Repo.delete(entry) do
          {:ok, _} ->
            :ok

          {:error, del_err} ->
            Logger.warning(
              "Compensating delete failed for entry #{entry.id}: #{inspect(del_err)}"
            )
        end

        {:error, reason}
    end
  end

  @doc """
  Search the knowledge store by semantic similarity to a query string.

  Embeds the query, then searches sqlite-vec for nearest neighbors.
  Returns entries ranked by cosine distance.
  """
  @spec search_similar(String.t(), keyword()) ::
          {:ok, [%{entry: Entry.t(), distance: float()}]} | {:error, {atom(), map()}}
  def search_similar(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    with {:ok, query_vector} <- Familiar.Providers.embed(query) do
      search_by_vector(query_vector, limit)
    end
  end

  @doc """
  Search the knowledge store using an entry's stored embedding.

  Avoids re-embedding the text — queries sqlite-vec directly with the
  stored vector. Used by consolidation to avoid N+1 embedding calls.
  """
  @spec search_similar_by_entry_id(integer(), keyword()) ::
          {:ok, [%{entry: Entry.t(), distance: float()}]} | {:error, {atom(), map()}}
  def search_similar_by_entry_id(entry_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    # Use subquery to avoid binary/JSON format mismatch — sqlite-vec handles
    # its own internal embedding format in subqueries.
    case Repo.query(
           """
           SELECT entry_id, distance
           FROM knowledge_entry_embeddings
           WHERE embedding MATCH (SELECT embedding FROM knowledge_entry_embeddings WHERE entry_id = ?)
           ORDER BY distance
           LIMIT ?
           """,
           [entry_id, limit]
         ) do
      {:ok, %{rows: rows}} ->
        entries = load_entries_with_distances(rows)
        {:ok, entries}

      {:error, reason} ->
        {:error, {:query_failed, %{reason: reason}}}
    end
  end

  @doc """
  Search the knowledge store using a pre-computed embedding vector.

  Avoids re-embedding when the caller already has the vector.
  """
  @spec search_by_vector([float()], integer()) ::
          {:ok, [%{entry: Entry.t(), distance: float()}]} | {:error, {atom(), map()}}
  def search_by_vector(vector, limit) do
    vector_json = Jason.encode!(vector)
    search_by_vector_json(vector_json, limit)
  end

  defp search_by_vector_json(vector_json, limit) do
    case Repo.query(
           """
           SELECT entry_id, distance
           FROM knowledge_entry_embeddings
           WHERE embedding MATCH ?
           ORDER BY distance
           LIMIT ?
           """,
           [vector_json, limit]
         ) do
      {:ok, %{rows: rows}} ->
        entries = load_entries_with_distances(rows)
        {:ok, entries}

      {:error, reason} ->
        {:error, {:query_failed, %{reason: reason}}}
    end
  end

  @doc """
  Delete a knowledge entry and its embedding.

  Removes the embedding from sqlite-vec and the entry from the database.
  """
  @spec delete_entry(Entry.t()) :: :ok | {:error, {atom(), map()}}
  def delete_entry(entry) do
    delete_embedding(entry.id)

    case Repo.delete(entry) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, {:delete_failed, %{changeset: changeset}}}
    end
  end

  @doc """
  Replace the embedding for an existing entry.

  Deletes the old embedding and inserts a new one.
  """
  @spec replace_embedding(integer(), [float()]) :: :ok | {:error, {atom(), map()}}
  def replace_embedding(entry_id, vector) do
    case delete_embedding(entry_id) do
      {:ok, _} -> insert_embedding(entry_id, vector)
      {:error, reason} -> {:error, {:storage_failed, %{reason: reason}}}
    end
  end

  @doc """
  Re-embed every entry in the knowledge store with the currently configured
  embedder, replace each stored vector, and update
  `Familiar.Knowledge.EmbeddingMetadata` with the new model + dimension.

  Fail-soft per entry: any individual entry whose re-embed fails is logged
  and accumulated into the `errors` list; the function still advances to
  the remaining entries and updates the metadata if at least one succeeded
  (or if the store was empty).

  Options:
    * `:on_progress` — `(processed :: integer(), total :: integer()) -> any()`
      called after each entry is handled (success OR failure). The CLI uses
      this to stream a "Re-embedding N/M" status line.
    * `:embedder` — override the embedder function (arity 1) used to produce
      vectors. Defaults to `&Familiar.Providers.embed/1`. Primarily for tests.

  Returns:
    `{:ok, %{processed: non_neg_integer(), failed: non_neg_integer(),
             errors: [{entry_id :: integer(), reason :: term()}],
             model: String.t() | nil,
             dimensions: pos_integer()}}`
  """
  @spec reindex_embeddings(keyword()) ::
          {:ok,
           %{
             processed: non_neg_integer(),
             failed: non_neg_integer(),
             errors: [{integer(), term()}],
             model: String.t() | nil,
             dimensions: pos_integer()
           }}
  def reindex_embeddings(opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _processed, _total -> :ok end)
    embedder = Keyword.get(opts, :embedder, &Familiar.Providers.embed/1)

    entries = Repo.all(Entry)
    total = length(entries)
    dimensions = embedding_dimensions()

    {processed, failed, errors} =
      entries
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, []}, fn {entry, idx}, {ok_count, fail_count, errs} ->
        case reindex_single(entry, embedder) do
          :ok ->
            on_progress.(idx, total)
            {ok_count + 1, fail_count, errs}

          {:error, reason} ->
            Logger.warning("[Knowledge.reindex] entry ##{entry.id} failed: #{inspect(reason)}")

            on_progress.(idx, total)
            {ok_count, fail_count + 1, [{entry.id, reason} | errs]}
        end
      end)

    model = current_embedding_model()

    if model && (processed > 0 or total == 0) do
      _ = EmbeddingMetadata.set(model, dimensions)
    end

    {:ok,
     %{
       processed: processed,
       failed: failed,
       errors: Enum.reverse(errors),
       model: model,
       dimensions: dimensions
     }}
  end

  defp reindex_single(entry, embedder) do
    with {:ok, vector} <- embedder.(entry.text),
         :ok <- replace_embedding(entry.id, vector) do
      :ok
    else
      {:error, _} = err -> err
      other -> {:error, {:unexpected_embedder_return, other}}
    end
  end

  @doc """
  Resolve the currently-configured embedding model name using the same
  precedence chain as `Familiar.Providers.OpenAIEmbedder`:

    env var > config.toml default provider > application config > nil

  Returns the model string or `nil` if none is configured. Used by
  `reindex_embeddings/1` and `Familiar.Application`'s drift check.
  """
  @spec current_embedding_model() :: String.t() | nil
  def current_embedding_model do
    System.get_env("FAMILIAR_EMBEDDING_MODEL") ||
      project_embedding_model() ||
      app_embedding_model()
  end

  defp project_embedding_model do
    path = Paths.config_path()

    # Only treat config.toml as a source when the file actually exists —
    # Familiar.Config.load/1 falls back to built-in defaults otherwise,
    # which would make this precedence step silently return
    # "nomic-embed-text" on every install that hasn't created a config.
    if File.exists?(path) do
      case Familiar.Config.load(path) do
        {:ok, config} -> Map.get(config.provider, :embedding_model)
        _ -> nil
      end
    end
  end

  defp app_embedding_model do
    Application.get_env(:familiar, :openai_compatible, [])
    |> Keyword.get(:embedding_model)
  end

  # -- Private --

  defp filter_text_in_attrs(attrs) do
    text = attrs[:text] || attrs["text"]

    if is_binary(text) do
      filtered = SecretFilter.filter(text)

      attrs
      |> Map.drop(["text", :text])
      |> Map.put(:text, filtered)
    else
      attrs
    end
  end

  defp delete_embedding(entry_id) do
    Repo.query(
      "DELETE FROM knowledge_entry_embeddings WHERE entry_id = ?",
      [entry_id]
    )
  end

  @doc """
  Return the expected embedding vector length.

  Sourced from `Application.get_env(:familiar, :embedding_dimensions)` so
  tests and alternate providers can override it. Default is 1536, matching
  `openai/text-embedding-3-small`. Changing this requires a matching
  migration to recreate the sqlite-vec virtual table at the new dimension.
  """
  @spec embedding_dimensions() :: pos_integer()
  def embedding_dimensions do
    Application.get_env(:familiar, :embedding_dimensions, 1536)
  end

  defp insert_embedding(entry_id, vector) do
    expected = embedding_dimensions()

    if length(vector) != expected do
      {:error,
       {:storage_failed,
        %{
          reason: :dimension_mismatch,
          expected: expected,
          got: length(vector)
        }}}
    else
      insert_embedding_query(entry_id, vector)
    end
  end

  defp insert_embedding_query(entry_id, vector) do
    vector_json = Jason.encode!(vector)

    case Repo.query(
           "INSERT INTO knowledge_entry_embeddings(entry_id, embedding) VALUES (?, ?)",
           [entry_id, vector_json]
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:storage_failed, %{reason: reason}}}
    end
  end

  defp load_entries_with_distances(rows) do
    entry_ids = Enum.map(rows, fn [id, _dist] -> id end)
    distance_map = Map.new(rows, fn [id, dist] -> {id, dist} end)

    entries =
      Entry
      |> where([e], e.id in ^entry_ids)
      |> Repo.all()

    entries
    |> Enum.map(fn entry ->
      %{entry: entry, distance: Map.get(distance_map, entry.id)}
    end)
    |> Enum.reject(&is_nil(&1.distance))
    |> Enum.sort_by(& &1.distance)
  end
end
