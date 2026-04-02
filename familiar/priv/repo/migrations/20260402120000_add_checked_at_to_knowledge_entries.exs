defmodule Familiar.Repo.Migrations.AddCheckedAtToKnowledgeEntries do
  use Ecto.Migration

  def change do
    alter table(:knowledge_entries) do
      add :checked_at, :utc_datetime
    end
  end
end
