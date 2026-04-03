defmodule Familiar.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :description, :text, null: false
      add :context, :text
      add :status, :string, null: false, default: "active"
      add :scope, :string, null: false, default: "default"

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:status])
    create index(:conversations, [:scope])

    create table(:conversation_messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, :text, null: false, default: "[]"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:conversation_messages, [:conversation_id])
  end
end
