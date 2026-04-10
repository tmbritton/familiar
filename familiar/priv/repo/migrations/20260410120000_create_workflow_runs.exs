defmodule Familiar.Repo.Migrations.CreateWorkflowRuns do
  use Ecto.Migration

  def change do
    create table(:workflow_runs) do
      add :name, :string, null: false
      add :workflow_path, :string
      add :scope, :string, null: false, default: "workflow"
      add :status, :string, null: false, default: "running"
      add :current_step_index, :integer, null: false, default: 0
      add :step_results, :text, null: false, default: "[]"
      add :initial_context, :text
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_runs, [:status])
    create index(:workflow_runs, [:inserted_at])
  end
end
