defmodule Familiar.Factory do
  @moduledoc """
  Test factories for building test data.

  Factories return plain maps since Ecto schemas don't exist yet.
  They will be updated to return proper structs as schemas are created
  in their respective epics.
  """

  @doc "Build a knowledge entry map with defaults."
  def build_knowledge_entry(attrs \\ %{}) do
    Map.merge(
      %{
        id: System.unique_integer([:positive]),
        text: "Handler files follow the pattern handler/{resource}.go",
        type: :convention,
        source: :init_scan,
        source_file: "handler/song.go",
        metadata: %{evidence_count: 3},
        inserted_at: ~U[2026-04-01 00:00:00Z],
        updated_at: ~U[2026-04-01 00:00:00Z]
      },
      attrs
    )
  end

  @doc "Build a task map with defaults."
  def build_task(attrs \\ %{}) do
    Map.merge(
      %{
        id: System.unique_integer([:positive]),
        title: "Add user authentication handler",
        status: :ready,
        priority: 1,
        epic_id: 1,
        group_id: nil,
        dependencies: [],
        inserted_at: ~U[2026-04-01 00:00:00Z],
        updated_at: ~U[2026-04-01 00:00:00Z]
      },
      attrs
    )
  end

  @doc "Build a spec map with defaults."
  def build_spec(attrs \\ %{}) do
    Map.merge(
      %{
        id: System.unique_integer([:positive]),
        title: "Add user accounts",
        content: "## Feature: User Accounts\n\nAdd registration and login.",
        status: :draft,
        verified_count: 0,
        unverified_count: 0,
        inserted_at: ~U[2026-04-01 00:00:00Z],
        updated_at: ~U[2026-04-01 00:00:00Z]
      },
      attrs
    )
  end
end
