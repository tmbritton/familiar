defmodule Familiar.Providers.Detector do
  @moduledoc """
  Provider auto-detection.

  Detects whether Ollama is running, discovers available models,
  and validates that prerequisite models (coding + embedding) are installed.
  """

  @default_base_url "http://localhost:11434"

  @doc """
  Check if Ollama is reachable.

  Returns `{:ok, base_url}` if Ollama responds, or
  `{:error, {:provider_unavailable, details}}` if not.
  """
  @spec detect() :: {:ok, String.t()} | {:error, {atom(), map()}}
  def detect do
    url = base_url()

    case Req.get(url, receive_timeout: 2_000, connect_options: [timeout: 2_000]) do
      {:ok, %Req.Response{status: 200}} ->
        {:ok, url}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         {:provider_unavailable, %{provider: :ollama, reason: :unexpected_status, status: status}}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}

      {:error, reason} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: reason}}}
    end
  end

  @doc """
  List all models installed in Ollama.

  Returns `{:ok, [model_map]}` where each model has at least a `"name"` key.
  """
  @spec list_models() ::
          {:ok, [map()]}
          | {:error,
             {:provider_unavailable,
              %{provider: :ollama, reason: :connection_refused | :unexpected_status | map()}}}
  def list_models do
    case Req.get(base_url() <> "/api/tags",
           receive_timeout: 5_000,
           connect_options: [timeout: 2_000]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"models" => models}}} ->
        {:ok, models}

      {:ok, %Req.Response{status: status}} ->
        {:error,
         {:provider_unavailable, %{provider: :ollama, reason: :unexpected_status, status: status}}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}

      {:error, reason} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: reason}}}
    end
  end

  @doc """
  Verify prerequisites: Ollama running, coding model available, embedding model available.

  Returns `{:ok, %{base_url, models, chat_model, embedding_model}}` or
  `{:error, {:provider_unavailable, details}}` with specific reason.
  """
  @spec check_prerequisites() ::
          {:ok,
           %{
             base_url: String.t(),
             models: [map()],
             chat_model: String.t(),
             embedding_model: String.t()
           }}
          | {:error, {:provider_unavailable, map()}}
  def check_prerequisites do
    with {:ok, url} <- detect(),
         {:ok, models} <- list_models() do
      model_names = Enum.map(models, & &1["name"])
      chat = configured_chat_model()
      embed = configured_embedding_model()

      chat_found = has_model?(model_names, chat)
      embed_found = has_model?(model_names, embed)

      cond do
        not chat_found and not embed_found ->
          {:error,
           {:provider_unavailable,
            %{
              provider: :ollama,
              reason: :models_missing,
              missing: [chat, embed],
              available: model_names
            }}}

        not chat_found ->
          {:error,
           {:provider_unavailable,
            %{
              provider: :ollama,
              reason: :model_not_found,
              model: chat,
              available: model_names
            }}}

        not embed_found ->
          {:error,
           {:provider_unavailable,
            %{
              provider: :ollama,
              reason: :model_not_found,
              model: embed,
              available: model_names
            }}}

        true ->
          {:ok,
           %{
             base_url: url,
             models: models,
             chat_model: chat,
             embedding_model: embed
           }}
      end
    end
  end

  # -- Private --

  @doc false
  def has_model?(model_names, target) do
    # Match either exact name or name:tag (e.g., "llama3.2" matches "llama3.2:latest")
    Enum.any?(model_names, fn name ->
      name == target or String.starts_with?(name, target <> ":")
    end)
  end

  defp base_url do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :base_url, @default_base_url)
  end

  defp configured_chat_model do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :chat_model, "llama3.2")
  end

  defp configured_embedding_model do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :embedding_model, "nomic-embed-text")
  end
end
