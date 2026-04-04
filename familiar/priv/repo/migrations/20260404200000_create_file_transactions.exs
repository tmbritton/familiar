defmodule Familiar.Repo.Migrations.CreateFileTransactions do
  use Ecto.Migration

  def change do
    create table(:file_transactions) do
      add :task_id, :string, null: false
      add :file_path, :string, null: false
      add :content_hash, :string, null: false
      add :original_content_hash, :string
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:file_transactions, [:task_id])
    create index(:file_transactions, [:status])
    create unique_index(:file_transactions, [:task_id, :file_path])
  end
end
