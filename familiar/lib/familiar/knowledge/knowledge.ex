defmodule Familiar.Knowledge do
  @moduledoc """
  Public API for the Knowledge context.

  Manages the semantic knowledge store — facts, decisions, gotchas,
  conventions, and relationships about the project. Handles embedding,
  retrieval, freshness validation, and post-task hygiene.
  """

  use Boundary, deps: [Familiar.Providers], exports: [Familiar.Knowledge]

  alias Familiar.Knowledge.ContentValidator
  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  @doc "List all knowledge entries of a given type."
  @spec list_by_type(module(), String.t()) :: [Entry.t()]
  def list_by_type(queryable \\ Entry, type) do
    import Ecto.Query
    queryable |> where([e], e.type == ^type) |> Repo.all()
  end

  @doc """
  Search the knowledge store by semantic similarity.

  Returns a flat list of result maps with entry fields and distance.
  """
  @spec search(String.t()) :: {:ok, [map()]} | {:error, {atom(), map()}}
  def search(query) do
    if String.trim(query) == "" do
      {:ok, []}
    else
      search_inner(query)
    end
  end

  defp search_inner(query) do
    with {:ok, results} <- search_similar(query) do
      formatted =
        Enum.map(results, fn %{entry: entry, distance: distance} ->
          %{
            id: entry.id,
            text: entry.text,
            type: entry.type,
            source: entry.source,
            source_file: entry.source_file,
            distance: distance,
            inserted_at: entry.inserted_at
          }
        end)

      {:ok, formatted}
    end
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
      with {:ok, _} <- ContentValidator.validate_not_code(text) do
        store_with_embedding(attrs)
      end
    end
  end

  @doc "Report knowledge store health metrics."
  @spec health() :: {:ok, map()} | {:error, {atom(), map()}}
  def health, do: {:error, {:not_implemented, %{}}}

  @doc """
  Store a knowledge entry and embed its text for semantic search.

  Pipeline: validate attrs -> insert entry -> embed text -> store vector.

  Internal function — does NOT enforce FR19 knowledge-not-code rule.
  Use `store/1` for the public API which validates content first.
  """
  @spec store_with_embedding(map()) :: {:ok, Entry.t()} | {:error, {atom(), map()}}
  def store_with_embedding(attrs) do
    changeset = Entry.changeset(%Entry{}, attrs)

    with {:ok, entry} <- Repo.insert(changeset),
         {:ok, vector} <- embed_or_rollback(entry),
         :ok <- insert_embedding_or_rollback(entry, vector) do
      {:ok, entry}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_failed, %{changeset: changeset}}}

      {:error, {type, details}} ->
        {:error, {type, details}}
    end
  end

  defp embed_or_rollback(entry) do
    case Familiar.Providers.embed(entry.text) do
      {:ok, vector} ->
        {:ok, vector}

      {:error, reason} ->
        # Compensating delete: remove the entry since embedding failed
        Repo.delete(entry)
        {:error, reason}
    end
  end

  defp insert_embedding_or_rollback(entry, vector) do
    case insert_embedding(entry.id, vector) do
      :ok ->
        :ok

      {:error, reason} ->
        # Compensating delete: remove the entry since vector storage failed
        Repo.delete(entry)
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
      vector_json = Jason.encode!(query_vector)

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
  end

  # -- Private --

  @expected_embedding_dimensions 768

  defp insert_embedding(entry_id, vector) do
    if length(vector) != @expected_embedding_dimensions do
      {:error,
       {:storage_failed,
        %{
          reason: :dimension_mismatch,
          expected: @expected_embedding_dimensions,
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

    import Ecto.Query

    entries =
      Entry
      |> where([e], e.id in ^entry_ids)
      |> Repo.all()

    entries
    |> Enum.map(fn entry ->
      %{entry: entry, distance: Map.get(distance_map, entry.id)}
    end)
    |> Enum.sort_by(& &1.distance)
  end
end
