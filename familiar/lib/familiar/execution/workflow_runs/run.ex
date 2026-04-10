defmodule Familiar.Execution.WorkflowRuns.Run do
  @moduledoc """
  Ecto schema for a persistent workflow run.

  Each row captures the progress of a `Familiar.Execution.WorkflowRunner`
  execution: which step is next, which steps have completed, and the
  initial context that was passed in. When a run fails or is interrupted,
  the row is the durable handle a user can resume from.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Familiar.Execution.WorkflowRuns.JSONField

  @type t :: %__MODULE__{}

  @valid_statuses ~w(running completed failed)

  schema "workflow_runs" do
    field :name, :string
    field :workflow_path, :string
    field :scope, :string, default: "workflow"
    field :status, :string, default: "running"
    field :current_step_index, :integer, default: 0
    field :step_results, JSONField, default: []
    field :initial_context, JSONField
    field :last_error, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for inserting a new workflow run row."
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :name,
      :workflow_path,
      :scope,
      :status,
      :current_step_index,
      :step_results,
      :initial_context
    ])
    |> validate_required([:name])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:current_step_index, greater_than_or_equal_to: 0)
  end

  @doc "Changeset for updating an existing workflow run row."
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :current_step_index,
      :step_results,
      :last_error
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:current_step_index, greater_than_or_equal_to: 0)
  end

  @doc "Returns the list of valid statuses."
  def valid_statuses, do: @valid_statuses
end
