defmodule Familiar.Providers do
  @moduledoc """
  Public API for the Providers context.

  Abstracts LLM provider communication behind a common interface.
  Resolves the configured provider implementation at runtime via
  application config.
  """

  use Boundary, deps: [], exports: [Familiar.Providers]

  @doc "Send a chat request to the configured LLM provider."
  @spec chat([map()], keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def chat(messages, opts \\ []) do
    impl(Familiar.Providers.LLM).chat(messages, opts)
  end

  @doc "Stream a chat response from the configured LLM provider."
  @spec stream_chat([map()], keyword()) :: {:ok, Enumerable.t()} | {:error, {atom(), map()}}
  def stream_chat(messages, opts \\ []) do
    impl(Familiar.Providers.LLM).stream_chat(messages, opts)
  end

  @doc "Generate a vector embedding for text."
  @spec embed(String.t()) :: {:ok, [float()]} | {:error, {atom(), map()}}
  def embed(text) do
    impl(Familiar.Knowledge.Embedder).embed(text)
  end

  @doc "Detect whether Ollama is running."
  @spec detect() :: {:ok, String.t()} | {:error, {atom(), map()}}
  defdelegate detect, to: Familiar.Providers.Detector

  @doc "List available models from the provider."
  @spec list_models() :: {:ok, [map()]} | {:error, {atom(), map()}}
  defdelegate list_models, to: Familiar.Providers.Detector

  @doc "Verify all prerequisites (provider running, required models available)."
  @spec check_prerequisites() :: {:ok, map()} | {:error, {atom(), map()}}
  defdelegate check_prerequisites, to: Familiar.Providers.Detector

  defp impl(behaviour) do
    case Application.get_env(:familiar, behaviour) do
      nil ->
        raise "No implementation configured for #{inspect(behaviour)}. " <>
                "Add `config :familiar, #{inspect(behaviour)}, MyAdapter` to your config."

      module ->
        module
    end
  end
end
