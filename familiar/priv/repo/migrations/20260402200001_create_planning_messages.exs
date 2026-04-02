defmodule Familiar.Repo.Migrations.CreatePlanningMessages do
  use Ecto.Migration

  def change do
    create table(:planning_messages) do
      add :session_id, references(:planning_sessions, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, :text, default: "[]"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:planning_messages, [:session_id])
  end
end
