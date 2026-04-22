defmodule Familiar.Knowledge.Extractor do
  @moduledoc """
  LLM-based knowledge extraction from source files.

  Given a file path and content, prompts the LLM to produce structured
  knowledge entries (file summaries, conventions, patterns, relationships,
  decisions) following the knowledge-not-code rule.
  """

  require Logger

  alias Familiar.Daemon.Paths
  alias Familiar.Knowledge.DefaultFiles
  alias Familiar.Knowledge.Entry
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
    if String.valid?(content) do
      messages = [%{role: "user", content: build_prompt(path, content)}]

      case llm_impl().chat(messages, []) do
        {:ok, %{content: response_text}} ->
          {parse_extraction_response(response_text, path), true}

        {:error, reason} ->
          Logger.warning("Extraction LLM call failed for #{path}: #{inspect(reason)}")
          {[], false}
      end
    else
      Logger.debug("Skipping binary file #{path}")
      {[], true}
    end
  end

  @doc """
  Extract knowledge entries from a single file.

  Calls the configured LLM with an extraction prompt and parses
  the response into entry attribute maps.
  """
  @spec extract_from_file(%{relative_path: String.t(), content: String.t()}) :: [map()]
  def extract_from_file(%{relative_path: path, content: content}) do
    if String.valid?(content) do
      messages = [%{role: "user", content: build_prompt(path, content)}]

      case llm_impl().chat(messages, []) do
        {:ok, %{content: response_text}} ->
          parse_extraction_response(response_text, path)

        {:error, reason} ->
          Logger.warning("Extraction LLM call failed for #{path}: #{inspect(reason)}")
          []
      end
    else
      Logger.debug("Skipping binary file #{path}")
      []
    end
  end

  @doc false
  @spec build_prompt(String.t(), String.t()) :: String.t()
  def build_prompt(file_path, content) do
    load_template()
    |> interpolate_template(file_path, content)
  end

  defp load_template do
    custom_path = Path.join([Paths.familiar_dir(), "system", "extractor.md"])

    case File.read(custom_path) do
      {:ok, template} -> template
      {:error, _} -> default_template()
    end
  end

  defp default_template do
    case DefaultFiles.default_content("system", "extractor.md") do
      {:ok, content} -> content
      :error -> raise "Missing default extractor template in priv/defaults/system/extractor.md"
    end
  end

  defp interpolate_template(template, file_path, content) do
    valid_types = Entry.default_types() |> Enum.map_join(", ", &inspect/1)

    # Replace {{valid_types}} first (fixed, no user content), then {{file_path}},
    # then {{content}} last — avoids cross-contamination if file_path or content
    # happen to contain template variable patterns.
    template
    |> String.replace("{{valid_types}}", valid_types)
    |> String.replace("{{file_path}}", file_path)
    |> String.replace("{{content}}", String.slice(content, 0, 4000))
  end

  @doc false
  @spec parse_extraction_response(String.t(), String.t()) :: [map()]
  def parse_extraction_response(response_text, default_source_file) do
    cleaned = strip_markdown_fences(response_text)

    case Jason.decode(cleaned) do
      {:ok, entries} when is_list(entries) ->
        valid =
          entries
          |> Enum.filter(&valid_entry?/1)

        rejected = length(entries) - length(valid)

        if rejected > 0,
          do:
            Logger.debug(
              "Extraction for #{default_source_file}: #{rejected}/#{length(entries)} entries rejected by validation"
            )

        Enum.map(valid, fn entry ->
          text = SecretFilter.filter(entry["text"])

          %{
            text: text,
            type: entry["type"],
            source: "init_scan",
            source_file: entry["source_file"] || default_source_file,
            metadata: Jason.encode!(%{})
          }
        end)

      {:error, decode_error} ->
        Logger.warning(
          "Extraction JSON decode failed for #{default_source_file}: #{inspect(decode_error)}, response prefix: #{String.slice(cleaned, 0, 200)}"
        )

        []

      {:ok, non_list} ->
        Logger.warning(
          "Extraction returned non-list for #{default_source_file}: #{inspect(non_list) |> String.slice(0, 200)}"
        )

        []
    end
  end

  defp strip_markdown_fences(text) do
    trimmed = String.trim(text)

    case Regex.run(~r/\A```(?:json)?\s*\n([\s\S]*?)\n\s*```\z/, trimmed) do
      [_, inner] -> inner
      nil -> trimmed
    end
  end

  # -- Private --

  defp valid_entry?(%{"type" => type, "text" => text})
       when is_binary(type) and is_binary(text) do
    Regex.match?(Entry.slug_format(), type) and String.length(type) <= 50 and
      String.trim(text) != ""
  end

  defp valid_entry?(_), do: false

  defp llm_impl do
    Application.get_env(:familiar, Familiar.Providers.LLM)
  end
end
