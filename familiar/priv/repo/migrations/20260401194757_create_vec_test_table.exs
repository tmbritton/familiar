defmodule Familiar.Repo.Migrations.CreateVecTestTable do
  use Ecto.Migration

  def up do
    # Create a sqlite-vec virtual table for vector similarity search.
    # This validates that sqlite-vec is loaded and functional.
    # Uses Float32 vectors with 3 dimensions for testing.
    execute("CREATE VIRTUAL TABLE IF NOT EXISTS vec_test USING vec0(embedding float[3])")
  end

  def down do
    execute("DROP TABLE IF EXISTS vec_test")
  end
end
