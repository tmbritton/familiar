defmodule Familiar.Knowledge.Hygiene do
  @moduledoc """
  Post-task hygiene loop for automatic knowledge capture.

  After a task completes, extracts new knowledge (facts, decisions, gotchas,
  relationships, conventions) from the execution context and stores it in
  the knowledge store. Detects duplicates via semantic similarity and
  supersedes stale entries rather than creating duplicates.

  Two extraction passes:
  - Success context: facts, decisions, gotchas, relationships, conventions
  - Failure log: gotchas only (what confused the agent, not the failed code)
  """

  require Logger

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.SecretFilter
  alias Familiar.Providers
  alias Familiar.Repo

  @valid_hygiene_types ~w(fact decision gotcha relationship convention)
  @duplicate_threshold 0.3

  @doc """
  Run the post-task hygiene loop for the given execution context.

  Accepts DI overrides via opts: `:llm` key (same pattern as freshness.ex).

  Returns `{:ok, %{extracted: count, updated: count, skipped: count}}`
  or `{:error, {atom, map}}`.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def run(context, opts \\ []) do
    success_entries = extract_from_success(context, opts)
    failure_entries = extract_from_failure(context, opts)
    all_entries = success_entries ++ failure_entries

    store_with_dedup(all_entries, opts)
  rescue
    e ->
      Logger.warning("Hygiene loop failed: #{inspect(e)} — continuing without knowledge capture")
      {:ok, %{extracted: 0, updated: 0, skipped: 0}}
  end

  @doc """
  Extract knowledge entries from a successful task execution context.

  Produces entries of types: fact, decision, gotcha, relationship, convention.
  Returns a list of entry attribute maps (not yet stored).
  """
  @spec extract_from_success(map(), keyword()) :: [map()]
  def extract_from_success(context, opts \\ []) do
    success = Map.get(context, :success_context) || Map.get(context, "success_context")

    if is_nil(success) or success == %{} do
      []
    else
      prompt = build_success_prompt(success)
      extract_via_llm(prompt, context, opts)
    end
  end

  @doc """
  Extract gotcha entries from a task failure log.

  Only produces entries of type "gotcha". Returns a list of entry attribute maps.
  """
  @spec extract_from_failure(map(), keyword()) :: [map()]
  def extract_from_failure(context, opts \\ []) do
    failure_log = Map.get(context, :failure_log) || Map.get(context, "failure_log")

    if is_nil(failure_log) or failure_log == "" do
      []
    else
      prompt = build_failure_prompt(failure_log)

      prompt
      |> extract_via_llm(context, opts)
      |> Enum.filter(fn entry -> entry.type == "gotcha" end)
    end
  end

  @doc """
  Detect duplicates and store or update entries.

  For each entry, searches existing entries by source_file and semantic
  similarity. If a match is found (cosine distance < 0.3 AND same source_file),
  updates the existing entry. Otherwise stores as new.
  """
  @spec store_with_dedup([map()], keyword()) :: {:ok, map()}
  def store_with_dedup(entries, _opts \\ []) do
    results = Enum.map(entries, &embed_and_dedup/1)
    counts = count_results(results)
    {:ok, counts}
  end

  defp embed_and_dedup(entry) do
    case Providers.embed(entry.text) do
      {:ok, vector} ->
        dedup_and_store(entry, vector)

      {:error, reason} ->
        Logger.warning("Hygiene embed failed: #{inspect(reason)}")
        {:skipped, entry}
    end
  end

  defp dedup_and_store(entry, vector) do
    case find_duplicate(entry, vector) do
      {:duplicate, existing} -> update_existing(existing, entry, vector)
      :no_match -> store_new(entry, vector)
    end
  end

  # -- Success prompt --

  defp build_success_prompt(success) do
    task_summary = Map.get(success, :task_summary, "") |> to_string()
    modified_files = Map.get(success, :modified_files, []) |> Enum.join(", ")
    decisions_made = Map.get(success, :decisions_made, "") |> to_string()

    """
    Given this task execution summary, extract knowledge entries as a JSON array.
    Each entry must have "type", "text", and "source_file" fields.

    Valid types: "fact", "decision", "gotcha", "relationship", "convention"

    Rules:
    - Extract what was LEARNED, not what was CODED
    - Facts: concrete discoveries about the codebase
    - Decisions: choices made and their rationale
    - Gotchas: edge cases, surprising behaviors, things to watch out for
    - Relationships: dependencies discovered, module interactions
    - Conventions: patterns established or confirmed
    - Do NOT include raw code snippets
    - Do NOT include secret values
    - Keep each entry concise (1-3 sentences)

    Task summary: #{task_summary}
    Files modified: #{modified_files}
    Decisions: #{decisions_made}

    Respond with ONLY a JSON array of entry objects, no other text.
    """
  end

  # -- Failure prompt --

  defp build_failure_prompt(failure_log) do
    """
    Given this task failure, extract gotcha entries as a JSON array.
    Each entry must have "type" set to "gotcha", "text", and optionally "source_file".

    Rules:
    - Focus on what CONFUSED the agent, not the code that was wrong
    - Extract edge cases, ambiguities, and patterns that need caution
    - Do NOT include the failed code itself
    - Keep each entry concise (1-3 sentences)

    Failure reason: #{failure_log}

    Respond with ONLY a JSON array of entry objects, no other text.
    """
  end

  # -- LLM extraction --

  defp extract_via_llm(prompt, context, opts) do
    llm = llm_impl(opts)
    messages = [%{role: "user", content: prompt}]

    case llm.chat(messages, []) do
      {:ok, %{content: response_text}} ->
        parse_hygiene_response(response_text, context)

      {:error, reason} ->
        Logger.warning("Hygiene LLM extraction failed: #{inspect(reason)}")
        []
    end
  end

  defp parse_hygiene_response(response_text, context) do
    modified_files = Map.get(context, :modified_files, [])
    default_source_file = List.first(modified_files)

    case Jason.decode(response_text) do
      {:ok, entries} when is_list(entries) ->
        entries
        |> Enum.filter(&valid_hygiene_entry?/1)
        |> Enum.map(fn entry ->
          text = SecretFilter.filter(entry["text"])

          %{
            text: text,
            type: entry["type"],
            source: "post_task",
            source_file: entry["source_file"] || default_source_file,
            metadata: Jason.encode!(%{})
          }
        end)

      _ ->
        []
    end
  end

  defp valid_hygiene_entry?(%{"type" => type, "text" => text})
       when is_binary(type) and is_binary(text) do
    type in @valid_hygiene_types and String.trim(text) != ""
  end

  defp valid_hygiene_entry?(_), do: false

  # -- Duplicate detection --

  defp find_duplicate(%{source_file: nil}, _vector), do: :no_match

  defp find_duplicate(entry, vector) do
    case Knowledge.search_by_vector(vector, 5) do
      {:ok, results} -> check_results_for_duplicate(results, entry.source_file)
      {:error, _} -> :no_match
    end
  end

  defp check_results_for_duplicate(results, source_file) do
    match =
      Enum.find(results, fn %{entry: existing, distance: distance} ->
        distance < @duplicate_threshold and existing.source_file == source_file
      end)

    if match, do: {:duplicate, match.entry}, else: :no_match
  end

  defp update_existing(existing, new_attrs, vector) do
    metadata = increment_update_count(existing.metadata)

    changeset =
      Entry.changeset(existing, %{
        text: new_attrs.text,
        type: new_attrs.type,
        metadata: metadata
      })

    with {:ok, updated} <- Repo.update(changeset),
         :ok <- Knowledge.replace_embedding(updated.id, vector) do
      {:updated, updated}
    else
      {:error, reason} ->
        Logger.warning("Hygiene update failed for entry #{existing.id}: #{inspect(reason)}")
        {:skipped, existing}
    end
  end

  defp increment_update_count(metadata_json) do
    case Jason.decode(metadata_json || "{}") do
      {:ok, meta} ->
        count = Map.get(meta, "update_count", 0)
        Jason.encode!(Map.put(meta, "update_count", count + 1))

      _ ->
        Jason.encode!(%{"update_count" => 1})
    end
  end

  defp store_new(entry, vector) do
    case Knowledge.store_with_vector(entry, vector) do
      {:ok, stored} -> {:extracted, stored}
      {:error, reason} ->
        Logger.warning("Hygiene store failed: #{inspect(reason)}")
        {:skipped, entry}
    end
  end

  # -- Result counting --

  defp count_results(results) do
    Enum.reduce(results, %{extracted: 0, updated: 0, skipped: 0}, fn
      {:extracted, _}, acc -> %{acc | extracted: acc.extracted + 1}
      {:updated, _}, acc -> %{acc | updated: acc.updated + 1}
      {:skipped, _}, acc -> %{acc | skipped: acc.skipped + 1}
    end)
  end

  # -- DI --

  defp llm_impl(opts) do
    Keyword.get_lazy(opts, :llm, fn ->
      Application.get_env(:familiar, Familiar.Providers.LLM)
    end)
  end
end
