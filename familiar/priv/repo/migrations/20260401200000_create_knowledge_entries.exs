defmodule Familiar.Repo.Migrations.CreateKnowledgeEntries do
  use Ecto.Migration

  def up do
    create table(:knowledge_entries) do
      add :text, :text, null: false
      add :type, :string, null: false
      add :source, :string, null: false
      add :source_file, :string
      add :metadata, :text, default: "{}"

      timestamps(type: :utc_datetime)
    end

    create index(:knowledge_entries, [:type])
    create index(:knowledge_entries, [:source])
    create index(:knowledge_entries, [:source_file])

    # sqlite-vec virtual table for embeddings (768 dimensions for nomic-embed-text)
    execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_entry_embeddings
    USING vec0(entry_id integer primary key, embedding float[768])
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS knowledge_entry_embeddings")
    drop table(:knowledge_entries)
  end
end
