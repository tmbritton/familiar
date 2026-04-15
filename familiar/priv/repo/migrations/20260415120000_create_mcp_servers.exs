defmodule Familiar.Repo.Migrations.CreateMcpServers do
  use Ecto.Migration

  def change do
    create table(:mcp_servers) do
      add :name, :string, null: false
      add :command, :string, null: false
      add :args_json, :text, null: false, default: "[]"
      add :env_json, :text, null: false, default: "{}"
      add :disabled, :boolean, null: false, default: false
      add :read_only, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_servers, [:name])
    create index(:mcp_servers, [:disabled])
  end
end
