defmodule Familiar.Knowledge.SecretFilter do
  @moduledoc """
  Structural secret detection and filtering for knowledge entries.

  Scans text for common secret patterns (API keys, tokens, credentials)
  and replaces them with safe reference descriptions. Uses regex patterns,
  not ML-based detection.
  """

  @secret_patterns [
    # AWS access keys
    {~r/AKIA[0-9A-Z]{16}/, "[AWS_ACCESS_KEY]"},
    # Stripe keys
    {~r/sk_live_[a-zA-Z0-9]{24,}/, "[STRIPE_SECRET_KEY]"},
    {~r/pk_live_[a-zA-Z0-9]{24,}/, "[STRIPE_PUBLISHABLE_KEY]"},
    # GitHub tokens
    {~r/ghp_[a-zA-Z0-9]{36,}/, "[GITHUB_TOKEN]"},
    {~r/gho_[a-zA-Z0-9]{36,}/, "[GITHUB_OAUTH_TOKEN]"},
    # Generic long base64 tokens (40+ chars, with trailing = padding)
    {~r/[A-Za-z0-9+\/]{40,}={1,2}/, "[REDACTED_TOKEN]"},
    # URLs with embedded credentials
    {~r{://[^:]+:[^@]+@}, "://[CREDENTIALS]@"},
    # Common env var values after =
    {~r/(DATABASE_URL|SECRET_KEY_BASE|API_KEY|SECRET_KEY|PRIVATE_KEY|ACCESS_TOKEN|AUTH_TOKEN)=\S+/,
     "\\1=[REDACTED]"}
  ]

  @doc """
  Filter secret values from text, replacing with safe references.
  """
  @spec filter(String.t()) :: String.t()
  def filter(text) when is_binary(text) do
    Enum.reduce(@secret_patterns, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  def filter(text), do: text

  @doc """
  Check whether text contains any secret patterns.
  """
  @spec contains_secrets?(String.t()) :: boolean()
  def contains_secrets?(text) when is_binary(text) do
    Enum.any?(@secret_patterns, fn {pattern, _} -> Regex.match?(pattern, text) end)
  end

  def contains_secrets?(_), do: false

  @doc """
  Detect secret patterns in text, returning matched pattern names and values.
  """
  @spec detect(String.t()) :: [{String.t(), String.t()}]
  def detect(text) when is_binary(text) do
    Enum.flat_map(@secret_patterns, &detect_pattern(&1, text))
  end

  def detect(_), do: []

  defp detect_pattern({pattern, replacement}, text) do
    pattern
    |> Regex.scan(text)
    |> Enum.map(fn [match | _] -> {replacement, match} end)
  end
end
