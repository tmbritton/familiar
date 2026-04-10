defmodule Familiar.Repo.Migrations.ResizeEmbeddingsTo1536 do
  use Ecto.Migration

  def up do
    # Drop the existing 768-dim virtual table and recreate at 1536 dims for
    # `openai/text-embedding-3-small`. No data in production so the drop is
    # safe; tests seed fresh data.
    execute("DROP TABLE IF EXISTS knowledge_entry_embeddings")

    execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_entry_embeddings
    USING vec0(entry_id integer primary key, embedding float[1536])
    """)

    # Singleton table tracking the embedding model that produced the current
    # vectors. `check_drift/1` in EmbeddingMetadata compares this to the
    # configured model and warns at startup when they diverge.
    create table(:knowledge_embedding_metadata) do
      add :model_name, :string
      add :dimensions, :integer

      timestamps(type: :utc_datetime)
    end

    # Insert the empty singleton row — EmbeddingMetadata.get/0 will create it
    # if missing, but seeding it here lets the first `set/2` use a simple
    # update instead of an upsert.
    execute("""
    INSERT INTO knowledge_embedding_metadata (id, inserted_at, updated_at)
    VALUES (1, datetime('now'), datetime('now'))
    """)
  end

  def down do
    drop table(:knowledge_embedding_metadata)
    execute("DROP TABLE IF EXISTS knowledge_entry_embeddings")

    execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_entry_embeddings
    USING vec0(entry_id integer primary key, embedding float[768])
    """)
  end
end
