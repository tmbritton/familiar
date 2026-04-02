defmodule Familiar.Knowledge.ContentValidator do
  @moduledoc """
  Validates knowledge entry content against the knowledge-not-code rule (FR19).

  Entries should be navigational prose descriptions, not raw code copies.
  Code is always read fresh from the filesystem at execution time.
  """

  @code_patterns [
    # Elixir
    ~r/^\s*(defmodule|defp?|defmacrop?|defimpl|defprotocol|defguardp?|defdelegate)\b/,
    ~r/^\s*end\s*$/,
    ~r/^\s*\{:(ok|error)/,
    ~r/^\s*\|>\s/,
    ~r/^\s*alias\s+\w/,
    # JavaScript/TypeScript
    ~r/^\s*(function\s+\w+|const\s+\w+\s*=\s*(?:async\s*)?\(|export\s+(?:default\s+)?(?:function|class|const))\b/,
    # Go
    ~r/^\s*func\s+[\(\w]/,
    ~r/^\s*var\s+\w+\s/,
    # Python
    ~r/^\s*def\s+\w+\s*\(/,
    ~r/^\s*class\s+\w+[\s\(:]/,
    ~r/^\s*(raise\s+\w|except\s|try\s*:)/,
    # Rust
    ~r/^\s*(pub\s+)?fn\s+\w+/,
    ~r/^\s*impl\s+\w+/,
    ~r/^\s*(pub\s+)?(struct|enum|trait)\s+\w+/,
    # Import/require blocks
    ~r/^\s*(import\s+[\w{]|from\s+['"]|require\s*\(|use\s+\w+[.\w]*$)/,
    # Braces/brackets blocks
    ~r/^\s*[\}\)\]]\s*;?\s*$/,
    ~r/^\s*[\{\(\[]\s*$/,
    # Common code patterns across languages
    ~r/^\s*(if\s+\w|if\s*[\(\!]|else\s*\{|elsif?\s|unless\s|case\s|switch\s*\()/,
    ~r/^\s*return\b/,
    ~r/^\s*(let|var|const)\s+\w+\s*=/
  ]

  @code_threshold 0.6

  @doc """
  Validate that text content is prose knowledge, not raw code.

  Returns `{:ok, text}` if content passes validation,
  or `{:error, {:knowledge_not_code, %{reason: reason}}}` if rejected.
  """
  @spec validate_not_code(String.t()) ::
          {:ok, String.t()} | {:error, {:knowledge_not_code, map()}}
  def validate_not_code(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, {:knowledge_not_code, %{reason: "content is empty"}}}

      code_ratio(trimmed) >= @code_threshold ->
        {:error,
         {:knowledge_not_code,
          %{reason: "content appears to be code rather than prose knowledge"}}}

      true ->
        {:ok, text}
    end
  end

  defp code_ratio(text) do
    lines =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))

    case lines do
      [] -> 1.0
      _ -> Enum.count(lines, &code_line?/1) / length(lines)
    end
  end

  defp code_line?(line) do
    Enum.any?(@code_patterns, &Regex.match?(&1, line))
  end
end
