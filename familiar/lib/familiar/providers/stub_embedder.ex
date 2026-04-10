defmodule Familiar.Providers.StubEmbedder do
  @moduledoc """
  Stub embedder that returns zero vectors.

  Use when no embedding provider is available. Knowledge store CRUD works
  but semantic search returns no meaningful results. Suitable for manual
  testing of agent chat and workflow commands.
  """

  @behaviour Familiar.Knowledge.Embedder

  require Logger

  @dimension 768
  @zero_vector List.duplicate(0.0, @dimension)

  @impl true
  def embed(_text) do
    log_stub_warning()
    {:ok, @zero_vector}
  end

  defp log_stub_warning do
    unless Process.get(:stub_embedder_warned) do
      Logger.info(
        "[StubEmbedder] Using zero-vector embeddings — semantic search will not work. " <>
          "Configure a real embedding provider for full knowledge store functionality."
      )

      Process.put(:stub_embedder_warned, true)
    end
  end
end
