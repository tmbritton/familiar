defmodule Familiar.Knowledge.EmbeddingMetadata do
  @moduledoc """
  Tracks the embedding model + dimension that produced the vectors
  currently stored in `knowledge_entry_embeddings`.

  A single-row table backs this module. The migration seeds one empty
  row with `id: 1`; all reads and writes target that row. When no row
  exists (e.g., a test that rolled the migration back then re-migrated
  without seeding), `get/0` lazy-creates it so callers never see
  `:not_found`.

  Used by:
    * `Familiar.Application.start/2` — drift warning at boot
    * `Familiar.Knowledge.reindex_embeddings/1` — updates the row on
      successful reindex
    * `fam context --reindex` CLI command — via the reindex function
  """

  alias Familiar.Knowledge.EmbeddingMetadataRow
  alias Familiar.Repo

  @singleton_id 1

  @type drift_result ::
          :ok
          | {:warning, :model_changed, %{stored: String.t(), configured: String.t()}}
          | {:warning, :model_unset, %{stored: nil, configured: String.t()}}

  @doc """
  Fetch the singleton metadata row, creating an empty one if missing.
  """
  @spec get() :: {:ok, %{model_name: String.t() | nil, dimensions: integer() | nil}}
  def get do
    case get_row() do
      %EmbeddingMetadataRow{} = row ->
        {:ok, %{model_name: row.model_name, dimensions: row.dimensions}}
    end
  end

  # Fetch-or-lazily-create the singleton row. Uses `on_conflict: :nothing`
  # + `conflict_target: :id` so two concurrent callers racing the initial
  # insert cannot crash with a PK violation — both end up reading the same
  # row on the re-fetch. Returns the row struct (never a plain map) so
  # `set/2` can hand it straight to the changeset without another query.
  defp get_row do
    case Repo.get(EmbeddingMetadataRow, @singleton_id) do
      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        case %EmbeddingMetadataRow{id: @singleton_id, inserted_at: now, updated_at: now}
             |> Repo.insert(on_conflict: :nothing, conflict_target: :id) do
          {:ok, row} when row.model_name != nil or row.dimensions != nil ->
            row

          _ ->
            # Either the insert was a no-op (row pre-existed via a racing
            # caller) or succeeded with all-nil fields. In both cases the
            # authoritative row is whatever is now in the DB.
            Repo.get!(EmbeddingMetadataRow, @singleton_id)
        end

      row ->
        row
    end
  end

  @doc """
  Upsert the singleton row with the given model name and dimension.
  """
  @spec set(String.t(), pos_integer()) ::
          {:ok, %{model_name: String.t(), dimensions: integer()}}
          | {:error, {:embedding_metadata_update_failed, map()}}
  def set(model_name, dimensions)
      when is_binary(model_name) and is_integer(dimensions) do
    # Pipe the row returned from get_row/0 straight into the changeset —
    # avoids a second query that could race with concurrent deletion.
    get_row()
    |> EmbeddingMetadataRow.changeset(%{model_name: model_name, dimensions: dimensions})
    |> Repo.update()
    |> case do
      {:ok, row} ->
        {:ok, %{model_name: row.model_name, dimensions: row.dimensions}}

      {:error, cs} ->
        {:error, {:embedding_metadata_update_failed, %{changeset: cs}}}
    end
  end

  @doc "Convenience accessor for the stored model name, or nil."
  @spec current_model() :: String.t() | nil
  def current_model do
    case get() do
      {:ok, %{model_name: name}} -> name
    end
  end

  @doc """
  Compare the stored model to the given configured model and return a
  drift result suitable for logging.

    * `:ok` — stored matches configured, or nothing is stored AND the
      knowledge store is empty (clean install)
    * `{:warning, :model_changed, ...}` — stored differs from configured
    * `{:warning, :model_unset, ...}` — stored is nil but entries exist
  """
  @spec check_drift(String.t() | nil) :: drift_result()
  def check_drift(nil), do: :ok

  def check_drift(configured_model) when is_binary(configured_model) do
    {:ok, %{model_name: stored}} = get()

    cond do
      stored == configured_model ->
        :ok

      stored == nil ->
        if knowledge_store_empty?() do
          :ok
        else
          {:warning, :model_unset, %{stored: nil, configured: configured_model}}
        end

      true ->
        {:warning, :model_changed, %{stored: stored, configured: configured_model}}
    end
  end

  defp knowledge_store_empty? do
    Repo.aggregate(Familiar.Knowledge.Entry, :count, :id) == 0
  end
end
