defmodule Familiar.Providers.OpenAIEmbedder do
  @moduledoc """
  OpenAI-compatible embedding adapter.

  Works with any provider that implements the `/embeddings` endpoint:
  OpenAI, OpenRouter, DeepInfra, Together AI, Groq, etc. Recommended
  default model is `openai/text-embedding-3-small` via OpenRouter —
  1536 dimensions, $0.02/M tokens, excellent quality for code + prose.

  ## Configuration

  Resolution precedence (first match wins):

    1. Env vars: `FAMILIAR_API_KEY`, `FAMILIAR_BASE_URL`, `FAMILIAR_EMBEDDING_MODEL`
    2. `[providers.xxx]` default section in `.familiar/config.toml`
    3. Application config: `config :familiar, :openai_compatible, ...`
    4. Built-in defaults (`https://api.openai.com/v1`, `text-embedding-3-small`)

  **Important:** the base URL stored in config.toml already includes `/v1`
  (e.g. `https://openrouter.ai/api/v1`), so this adapter appends
  `/embeddings` — NOT `/v1/embeddings`. Matches the pattern the chat
  adapter uses (see commit `cfa622b`).
  """

  @behaviour Familiar.Knowledge.Embedder

  require Logger

  alias Familiar.Daemon.Paths

  @default_base_url "https://api.openai.com/v1"
  @default_receive_timeout 30_000

  @impl true
  def embed(text) when is_binary(text) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, model} <- fetch_embedding_model() do
      body = %{model: model, input: text}

      embeddings_url()
      |> Req.post(
        json: body,
        headers: [{"authorization", "Bearer #{api_key}"}],
        receive_timeout: @default_receive_timeout
      )
      |> parse_response()
    end
  end

  # Strip any trailing slash on the configured base URL before appending
  # `/embeddings`. A user writing `base_url = "https://openrouter.ai/api/v1/"`
  # would otherwise hit `https://openrouter.ai/api/v1//embeddings`, which
  # many providers respond to with 404.
  defp embeddings_url do
    String.trim_trailing(base_url(), "/") <> "/embeddings"
  end

  @doc false
  def parse_response(
        {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => vec} | _]}}}
      )
      when is_list(vec) do
    {:ok, vec}
  end

  def parse_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:error,
     {:provider_unavailable,
      %{provider: :openai_compatible, reason: :unexpected_body, body: body}}}
  end

  def parse_response({:ok, %Req.Response{status: 401}}) do
    {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :unauthorized}}}
  end

  def parse_response({:ok, %Req.Response{status: 404}}) do
    {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :model_not_found}}}
  end

  def parse_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error,
     {:provider_unavailable,
      %{provider: :openai_compatible, reason: :api_error, status: status, body: body}}}
  end

  def parse_response({:error, %Req.TransportError{reason: :econnrefused}}) do
    {:error,
     {:provider_unavailable, %{provider: :openai_compatible, reason: :connection_refused}}}
  end

  def parse_response({:error, %Req.TransportError{reason: :timeout}}) do
    {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :timeout}}}
  end

  def parse_response({:error, reason}) do
    {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: reason}}}
  end

  # -- Private: Config --
  # Priority: env vars > config.toml provider > application config > defaults

  defp fetch_api_key do
    case System.get_env("FAMILIAR_API_KEY") || project_config(:api_key) || app_config(:api_key) do
      nil ->
        {:error,
         {:provider_unavailable, %{provider: :openai_compatible, reason: :missing_api_key}}}

      "" ->
        {:error,
         {:provider_unavailable, %{provider: :openai_compatible, reason: :missing_api_key}}}

      key ->
        {:ok, key}
    end
  end

  defp fetch_embedding_model do
    case System.get_env("FAMILIAR_EMBEDDING_MODEL") ||
           project_config(:embedding_model) ||
           app_config(:embedding_model) do
      nil ->
        {:error,
         {:provider_unavailable,
          %{provider: :openai_compatible, reason: :missing_embedding_model}}}

      "" ->
        {:error,
         {:provider_unavailable,
          %{provider: :openai_compatible, reason: :missing_embedding_model}}}

      model ->
        {:ok, model}
    end
  end

  defp base_url do
    System.get_env("FAMILIAR_BASE_URL") ||
      project_config(:base_url) ||
      app_config(:base_url) ||
      @default_base_url
  end

  defp project_config(key) do
    load_project_config() |> Map.get(key)
  end

  defp load_project_config do
    path = Paths.config_path()

    # Only treat config.toml as a source when the file physically exists.
    # `Familiar.Config.load/1` returns `{:ok, defaults()}` for a missing
    # file, and those defaults carry Ollama's base_url and embedding_model,
    # which would silently override the user's real openai_compatible
    # config. Mirror the same guard in `Knowledge.project_embedding_model/0`.
    if File.exists?(path) do
      case Familiar.Config.load(path) do
        {:ok, config} -> config.provider
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp app_config(key) do
    Application.get_env(:familiar, :openai_compatible, [])
    |> Keyword.get(key)
  end
end
