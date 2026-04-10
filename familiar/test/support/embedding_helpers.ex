defmodule Familiar.Test.EmbeddingHelpers do
  @moduledoc """
  Shared helpers for building deterministic embedding vectors in tests.

  Reads the configured dimension via `Familiar.Knowledge.embedding_dimensions/0`
  so a single `config :familiar, :embedding_dimensions, N` flip migrates every
  test at once. Added in Story 7.5-7 to consolidate six nearly-identical
  `defp deterministic_vector/2` copies.
  """

  alias Familiar.Knowledge

  @doc """
  Build a deterministic 2-zone vector of length `embedding_dimensions()`.

  The first half of the vector is filled with `primary`, the second half
  with `secondary`. Vectors produced this way are stable across runs and
  suitable for similarity-ordering assertions.
  """
  @spec deterministic_vector(number(), number()) :: [float()]
  def deterministic_vector(primary, secondary) do
    dim = Knowledge.embedding_dimensions()
    half = div(dim, 2)
    List.duplicate(primary / 1, half) ++ List.duplicate(secondary / 1, dim - half)
  end

  @doc "Zero-vector of the configured dimension."
  @spec zero_vector() :: [float()]
  def zero_vector, do: List.duplicate(0.0, Knowledge.embedding_dimensions())
end
