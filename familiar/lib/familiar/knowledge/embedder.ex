defmodule Familiar.Knowledge.Embedder do
  @moduledoc """
  Behaviour for text embedding providers.

  Implementations convert text into vector embeddings for semantic search
  via sqlite-vec.
  """

  @type embedding :: [float()]

  @doc "Generate a vector embedding for the given text."
  @callback embed(text :: String.t()) ::
              {:ok, embedding()} | {:error, {atom(), map()}}
end
