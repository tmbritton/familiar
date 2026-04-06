defmodule Familiar.Knowledge.Extractor do
  @moduledoc """
  LLM-based knowledge extraction from source files.

  Given a file path and content, prompts the LLM to produce structured
  knowledge entries (file summaries, conventions, patterns, relationships,
  decisions) following the knowledge-not-code rule.
  """

  alias Familiar.Knowledge.SecretFilter

  @doc """
  Extract knowledge entries from a list of file info maps.

  Each file info must have `:relative_path` and `:content` keys.
  Returns a list of entry attribute maps ready for `Knowledge.store_with_embedding/1`.
  """
  @spec extract_from_files([map()]) :: [map()]
  def extract_from_files(files) do
    files
    |> Enum.flat_map(&extract_from_file/1)
  end

  @doc """
  Extract entries and return stats on failures.

  Returns `{entries, failure_count}`.
  """
  @spec extract_from_files_with_stats([map()]) :: {[map()], non_neg_integer()}
  def extract_from_files_with_stats(files) do
    results = Enum.map(files, &extract_from_file_with_status/1)
    entries = Enum.flat_map(results, fn {entries, _ok?} -> entries end)
    failures = Enum.count(results, fn {_entries, ok?} -> not ok? end)
    {entries, failures}
  end

  @doc false
  def extract_from_file_with_status(%{relative_path: path, content: content}) do
    messages = [%{role: "user", content: build_prompt(path, content)}]

    case llm_impl().chat(messages, []) do
      {:ok, %{content: response_text}} ->
        {parse_extraction_response(response_text, path), true}

      {:error, _} ->
        {[], false}
    end
  end

  @doc """
  Extract knowledge entries from a single file.

  Calls the configured LLM with an extraction prompt and parses
  the response into entry attribute maps.
  """
  @spec extract_from_file(%{relative_path: String.t(), content: String.t()}) :: [map()]
  def extract_from_file(%{relative_path: path, content: content}) do
    messages = [%{role: "user", content: build_prompt(path, content)}]

    case llm_impl().chat(messages, []) do
      {:ok, %{content: response_text}} ->
        parse_extraction_response(response_text, path)

      {:error, _} ->
        []
    end
  end

  @doc false
  @spec build_prompt(String.t(), String.t()) :: String.t()
  def build_prompt(file_path, content) do
    """
    Analyze this source file and produce knowledge entries as a JSON array.
    Each entry must have "type", "text", and "source_file" fields.

    Valid types: "file_summary", "convention", "architecture", "relationship", "decision"

    Rules:
    - Describe what the code DOES in natural language prose
    - Do NOT include raw code snippets
    - Do NOT include secret values (API keys, tokens, passwords)
    - Focus on purpose, patterns, dependencies, and architectural decisions
    - Keep each entry concise (1-3 sentences)

    File: #{file_path}
    Content:
    ```
    #{String.slice(content, 0, 4000)}
    ```

    Respond with ONLY a JSON array of entry objects, no other text.
    """
  end

  @doc false
  @spec parse_extraction_response(String.t(), String.t()) :: [map()]
  def parse_extraction_response(response_text, default_source_file) do
    case Jason.decode(response_text) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.filter(&valid_entry?/1)
        |> Enum.map(fn entry ->
          text = SecretFilter.filter(entry["text"])

          %{
            text: text,
            type: entry["type"],
            source: "init_scan",
            source_file: entry["source_file"] || default_source_file,
            metadata: Jason.encode!(%{})
          }
        end)

      _ ->
        []
    end
  end

  # -- Private --

  defp valid_entry?(%{"type" => type, "text" => text})
       when is_binary(type) and is_binary(text) do
    type in ~w(file_summary convention architecture relationship decision) and
      String.length(text) > 0
  end

  defp valid_entry?(_), do: false

  defp llm_impl do
    Application.get_env(:familiar, Familiar.Providers.LLM)
  end
end
