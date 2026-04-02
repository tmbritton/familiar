defmodule Familiar.Repo.Migrations.CreatePlanningSessions do
  use Ecto.Migration

  def change do
    create table(:planning_sessions) do
      add :description, :text, null: false
      add :context, :text
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:planning_sessions, [:status])
  end
end
