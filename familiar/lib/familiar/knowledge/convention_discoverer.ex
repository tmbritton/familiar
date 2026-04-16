defmodule Familiar.Knowledge.ConventionDiscoverer do
  @moduledoc """
  Discovers project conventions from scanned files.

  Two-phase approach:
  1. Structural analysis — file naming, directory patterns, language detection (no LLM)
  2. LLM-assisted cross-cutting analysis — error handling, architecture patterns
  """

  @doc """
  Discover conventions from scanned file infos (structural + LLM).

  Each file info must have `:relative_path` and `:content` keys.
  Returns a list of convention entry attribute maps.
  """
  @spec discover([map()], keyword()) :: [map()]
  def discover(files, _opts \\ []) do
    structural = discover_structural(files)
    llm = discover_with_llm(files)
    structural ++ llm
  end

  @doc """
  Discover structural conventions without LLM (pure analysis).
  """
  @spec discover_structural([map()]) :: [map()]
  def discover_structural([]), do: []

  def discover_structural(files) do
    paths = Enum.map(files, & &1.relative_path)

    [
      detect_naming_patterns(paths),
      detect_directory_structure(paths),
      detect_extension_distribution(paths)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Discover cross-cutting conventions via LLM analysis.
  """
  @spec discover_with_llm([map()]) :: [map()]
  def discover_with_llm(files) do
    sample_content = build_sample_content(files)
    file_list = Enum.map_join(files, "\n", & &1.relative_path)

    prompt = """
    Analyze this project's file structure and code samples to identify cross-cutting conventions.
    Return a JSON array of convention objects.

    Each convention must have:
    - "type": always "convention"
    - "text": natural language description of the convention (1-2 sentences)
    - "evidence_count": how many files/instances exhibit this convention
    - "evidence_total": total files/instances examined

    Focus on: error handling patterns, module organization, naming conventions, architecture patterns.
    Do NOT include file naming or directory structure (those are detected separately).
    Do NOT include raw code — describe patterns in prose.

    File list:
    #{file_list}

    Sample content from representative files:
    #{sample_content}

    Respond with ONLY a JSON array, no other text.
    """

    messages = [%{role: "user", content: prompt}]

    case llm_impl().chat(messages, []) do
      {:ok, %{content: response}} ->
        parse_llm_conventions(response)

      {:error, _} ->
        []
    end
  end

  # -- Private --

  defp detect_naming_patterns(paths) do
    source_files =
      paths
      |> Enum.map(&Path.basename/1)
      |> Enum.filter(&(Path.extname(&1) != ""))
      |> Enum.reject(&(&1 in ~w(mix.exs package.json Cargo.toml Gemfile Makefile)))

    if source_files == [] do
      nil
    else
      snake_count = Enum.count(source_files, &snake_case?/1)
      total = length(source_files)

      if snake_count > 0 do
        build_convention(
          "Source files use snake_case naming (#{snake_count}/#{total} files)",
          snake_count,
          total
        )
      end
    end
  end

  defp detect_directory_structure(paths) do
    dirs =
      paths
      |> Enum.map(&Path.dirname/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&hd(String.split(&1, "/")))
      |> Enum.uniq()

    conventions = []

    conventions =
      if "test" in dirs or "spec" in dirs do
        test_dir = if "test" in dirs, do: "test/", else: "spec/"
        src_dir = if "lib" in dirs, do: "lib/", else: "src/"

        [
          build_convention(
            "Test files organized in #{test_dir} mirroring #{src_dir} structure",
            1,
            1
          )
          | conventions
        ]
      else
        conventions
      end

    conventions
  end

  defp detect_extension_distribution(paths) do
    ext_counts =
      paths
      |> Enum.map(&Path.extname/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_ext, count} -> count end, :desc)

    case ext_counts do
      [{ext, count} | _] when count >= 2 ->
        total = Enum.reduce(ext_counts, 0, fn {_, c}, acc -> acc + c end)

        [
          build_convention(
            "Primary file type is #{ext} (#{count}/#{total} files with extensions)",
            count,
            total
          )
        ]

      _ ->
        []
    end
  end

  defp build_convention(text, evidence_count, evidence_total) do
    ratio =
      if evidence_total > 0,
        do: Float.round(evidence_count / evidence_total, 2),
        else: 0.0

    %{
      text: text,
      type: "convention",
      source: "init_scan",
      source_file: nil,
      metadata:
        Jason.encode!(%{
          evidence_count: evidence_count,
          evidence_total: evidence_total,
          evidence_ratio: ratio,
          reviewed: false
        })
    }
  end

  defp parse_llm_conventions(response_text) do
    case Jason.decode(response_text) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.filter(&valid_convention?/1)
        |> Enum.map(fn entry ->
          build_convention(
            entry["text"],
            entry["evidence_count"] || 0,
            entry["evidence_total"] || 0
          )
        end)

      _ ->
        []
    end
  end

  defp valid_convention?(%{"type" => "convention", "text" => text})
       when is_binary(text) and byte_size(text) > 0,
       do: true

  defp valid_convention?(_), do: false

  defp build_sample_content(files) do
    files
    |> Enum.filter(&(byte_size(&1.content) > 0 and String.valid?(&1.content)))
    |> Enum.take(5)
    |> Enum.map_join("\n\n", fn file ->
      content = String.slice(file.content, 0, 1000)
      "--- #{file.relative_path} ---\n#{content}"
    end)
  end

  defp snake_case?(filename) do
    name = Path.rootname(filename)
    name == String.downcase(name) and not String.contains?(name, "-")
  end

  defp llm_impl do
    Application.get_env(:familiar, Familiar.Providers.LLM)
  end
end
