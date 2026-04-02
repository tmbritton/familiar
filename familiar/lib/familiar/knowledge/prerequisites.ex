defmodule Familiar.Knowledge.Prerequisites do
  @moduledoc """
  Prerequisite checker for project initialization.

  Verifies that Ollama is running and required models (chat + embedding)
  are available before starting the init scan.
  """

  alias Familiar.Providers.Detector

  @doc """
  Check all prerequisites for init.

  Returns `{:ok, provider_info}` or `{:error, {:prerequisites_failed, details}}`
  with human-readable instructions.

  Options:
  - `:check_prerequisites_fn` — override for testing (default: `Detector.check_prerequisites/0`)
  """
  @spec check(keyword()) :: {:ok, map()} | {:error, {:prerequisites_failed, map()}}
  def check(opts \\ []) do
    check_fn = Keyword.get(opts, :check_prerequisites_fn, &Detector.check_prerequisites/0)

    case check_fn.() do
      {:ok, info} ->
        {:ok, info}

      {:error, {:provider_unavailable, %{reason: :connection_refused}}} ->
        {:error,
         {:prerequisites_failed,
          %{
            missing: ["ollama"],
            instructions:
              "Ollama is not running. Start it with: ollama serve\n" <>
                "Install from: https://ollama.ai"
          }}}

      {:error, {:provider_unavailable, %{reason: :models_missing, missing: missing}}} ->
        pull_cmds = Enum.map_join(missing, "\n", &"  ollama pull #{&1}")

        {:error,
         {:prerequisites_failed,
          %{
            missing: missing,
            instructions: "Required models not found. Install them:\n#{pull_cmds}"
          }}}

      {:error, {:provider_unavailable, %{reason: :model_not_found, model: model}}} ->
        {:error,
         {:prerequisites_failed,
          %{
            missing: [model],
            instructions: "Required model not found. Install it:\n  ollama pull #{model}"
          }}}

      {:error, {:provider_unavailable, details}} ->
        {:error,
         {:prerequisites_failed,
          %{
            missing: [],
            instructions:
              "Ollama is unavailable: #{inspect(details[:reason])}\n" <>
                "Ensure Ollama is running: ollama serve"
          }}}
    end
  end
end
