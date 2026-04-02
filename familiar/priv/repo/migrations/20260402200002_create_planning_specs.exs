defmodule Familiar.Repo.Migrations.CreatePlanningSpecs do
  use Ecto.Migration

  def change do
    create table(:planning_specs) do
      add :session_id, references(:planning_sessions, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :metadata, :text, default: "{}"
      add :file_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:planning_specs, [:session_id])
    create index(:planning_specs, [:status])
  end
end
