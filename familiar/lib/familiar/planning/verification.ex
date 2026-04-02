defmodule Familiar.Planning.Verification do
  @moduledoc """
  Pure function module for spec claim verification against tool call logs.

  Maps spec claims to actual tool calls (file reads, context queries) to
  produce verification marks (✓ verified / ⚠ unverified). The tool call
  log is the single source of truth — the LLM cannot self-report
  verification status.

  This is a critical module with 100% test coverage required.
  """

  @file_path_pattern ~r"""
  (?:                          # Match file paths in various contexts:
    (?:in|from|at|see|verified\s+in|checked)\s+  # preceded by keywords
    [`]?([a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+)[`]?    # capture the file path
  |
    [`]([a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+)[`]      # or backtick-quoted paths
  )
  """x

  @convention_pattern ~r/^Following existing pattern:/

  @type claim :: %{
          text: String.t(),
          file_refs: [String.t()]
        }

  @type tool_call :: %{
          type: String.t(),
          path: String.t(),
          timestamp: DateTime.t() | nil
        }

  @type verification_result :: %{
          claim: String.t(),
          status: :verified | :unverified,
          source: String.t() | nil,
          evidence: tool_call() | nil
        }

  @doc """
  Extract claims from spec markdown text.

  Parses each non-empty, non-heading line for inline file path references.
  Properly handles YAML frontmatter boundaries (--- delimiters).
  Returns a list of `%{text: string, file_refs: [string]}`.
  """
  @spec extract_claims(String.t() | nil) :: [claim()]
  def extract_claims(nil), do: []

  def extract_claims(markdown) do
    markdown
    |> String.split("\n")
    |> skip_frontmatter()
    |> Enum.reject(fn line -> heading_or_empty?(line) or meta_or_convention?(line) end)
    |> Enum.map(&parse_claim/1)
    |> Enum.filter(&has_content?/1)
  end

  @doc """
  Verify claims against a tool call log.

  Claims with file references matching entries in the tool call log are
  marked `:verified`. All others are marked `:unverified`.
  """
  @spec verify_claims([claim()], [tool_call()]) :: [verification_result()]
  def verify_claims(claims, tool_call_log) do
    accessed_paths = MapSet.new(tool_call_log, &normalize_path(&1.path))

    Enum.map(claims, fn claim ->
      case find_verification(claim.file_refs, accessed_paths, tool_call_log) do
        {source, evidence} ->
          %{claim: claim.text, status: :verified, source: source, evidence: evidence}

        nil ->
          %{claim: claim.text, status: :unverified, source: nil, evidence: nil}
      end
    end)
  end

  @doc """
  Annotate spec markdown with verification marks.

  Prepends ✓ or ⚠ to lines that contain file references, with source
  citations for verified claims.
  """
  @spec annotate_spec(String.t() | nil, [verification_result()]) :: String.t()
  def annotate_spec(nil, _verification_results), do: ""

  def annotate_spec(markdown, verification_results) do
    result_map = Map.new(verification_results, &{&1.claim, &1})

    markdown
    |> String.split("\n")
    |> Enum.map_join("\n", &annotate_line(&1, result_map))
  end

  @doc """
  Build metadata summary from verification results and spec markdown.

  Counts verified claims, unverified claims, and convention annotations.
  """
  @spec build_metadata([verification_result()], String.t() | nil) :: map()
  def build_metadata(results, spec_markdown \\ nil) do
    verified = Enum.count(results, &(&1.status == :verified))
    unverified = Enum.count(results, &(&1.status == :unverified))
    conventions = count_conventions(spec_markdown)

    %{
      verified_count: verified,
      unverified_count: unverified,
      conventions_count: conventions,
      total_claims: verified + unverified
    }
  end

  # -- Private --

  defp skip_frontmatter(lines) do
    case lines do
      ["---" | rest] -> skip_until_closing_fence(rest)
      _ -> lines
    end
  end

  defp skip_until_closing_fence([]), do: []
  defp skip_until_closing_fence(["---" | rest]), do: rest
  defp skip_until_closing_fence([_ | rest]), do: skip_until_closing_fence(rest)

  defp heading_or_empty?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end

  defp meta_or_convention?(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, "Generated ") or
      Regex.match?(@convention_pattern, trimmed)
  end

  defp has_content?(%{text: text}), do: String.trim(text) != ""

  defp parse_claim(line) do
    text = String.trim(line)
    text = Regex.replace(~r/^[✓⚠]\s*/, text, "")
    file_refs = extract_file_refs(text)
    %{text: text, file_refs: file_refs}
  end

  defp extract_file_refs(text) do
    @file_path_pattern
    |> Regex.scan(text)
    |> Enum.flat_map(fn captures ->
      captures
      |> Enum.drop(1)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.map(&normalize_path/1)
    |> Enum.uniq()
  end

  defp normalize_path(path) do
    path
    |> String.trim_leading("./")
    |> String.trim()
  end

  defp find_verification([], _accessed_paths, _log), do: nil

  defp find_verification(file_refs, accessed_paths, log) do
    Enum.find_value(file_refs, fn ref ->
      normalized = normalize_path(ref)

      if MapSet.member?(accessed_paths, normalized) do
        evidence = Enum.find(log, &(normalize_path(&1.path) == normalized))
        {ref, evidence}
      end
    end)
  end

  defp annotate_line(line, result_map) do
    trimmed = String.trim(line)

    if heading_or_empty?(trimmed) or meta_or_convention?(trimmed) or frontmatter_delimiter?(trimmed) do
      line
    else
      clean = Regex.replace(~r/^[✓⚠]\s*/, trimmed, "")

      case Map.get(result_map, clean) do
        %{status: :verified, source: source} when not is_nil(source) ->
          "✓ #{clean} — verified in #{source}"

        %{status: :verified} ->
          "✓ #{clean}"

        %{status: :unverified} ->
          "⚠ #{clean}"

        nil ->
          line
      end
    end
  end

  defp frontmatter_delimiter?(line), do: String.trim(line) == "---"

  defp count_conventions(nil), do: 0

  defp count_conventions(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.count(&Regex.match?(@convention_pattern, String.trim(&1)))
  end
end
