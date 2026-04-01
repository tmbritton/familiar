defmodule Familiar.Providers.OllamaEmbedder do
  @moduledoc """
  Ollama embedding provider adapter.

  Implements `Familiar.Knowledge.Embedder` behaviour by communicating with
  the Ollama HTTP API's `/api/embed` endpoint.
  """

  @behaviour Familiar.Knowledge.Embedder

  @default_base_url "http://localhost:11434"
  @default_receive_timeout 30_000

  @impl true
  def embed(text) do
    body = %{
      model: embedding_model(),
      input: text
    }

    (base_url() <> "/api/embed")
    |> Req.post(json: body, receive_timeout: receive_timeout())
    |> parse_response()
  end

  @doc false
  def parse_response({:ok, %Req.Response{status: 200, body: %{"embeddings" => [vector | _]}}}) do
    {:ok, vector}
  end

  def parse_response({:ok, %Req.Response{status: 200, body: %{"embeddings" => []}}}) do
    {:error, {:provider_unavailable, %{provider: :ollama, reason: :empty_embedding}}}
  end

  def parse_response({:ok, %Req.Response{status: 404}}) do
    {:error, {:provider_unavailable, %{provider: :ollama, reason: :model_not_found}}}
  end

  def parse_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error,
     {:provider_unavailable, %{provider: :ollama, reason: :api_error, status: status, body: body}}}
  end

  def parse_response({:error, %Req.TransportError{reason: :econnrefused}}) do
    {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}
  end

  def parse_response({:error, %Req.TransportError{reason: :timeout}}) do
    {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}
  end

  def parse_response({:error, reason}) do
    {:error, {:provider_unavailable, %{provider: :ollama, reason: reason}}}
  end

  # -- Private: Config --

  defp base_url do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :base_url, @default_base_url)
  end

  defp embedding_model do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :embedding_model, "nomic-embed-text")
  end

  defp receive_timeout do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :receive_timeout, @default_receive_timeout)
  end
end
