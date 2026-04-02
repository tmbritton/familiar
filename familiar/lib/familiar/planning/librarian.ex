defmodule Familiar.Planning.Librarian do
  @moduledoc """
  Ephemeral GenServer for curated knowledge retrieval.

  Spins up per query under `Familiar.LibrarianSupervisor`, performs
  multi-hop retrieval (search → evaluate → refine → re-search),
  summarizes results via LLM, then terminates. No state survives
  between queries.

  ## LLM Call Budget

  A single `query/2` may make up to `@max_hops` gap-detection LLM calls
  (one per hop when results are sparse) plus 1 summarization call.
  With the default `@max_hops` of 3, the worst case is 4 LLM roundtrips.
  """

  use GenServer

  require Logger

  @max_hops 3
  @min_results_for_summary 1
  # Gap detection fires below this threshold; related to @min_results_for_summary.
  # Sparse results (< threshold) trigger a refinement hop; once at or above,
  # results are considered sufficient and go straight to summarization.
  @gap_threshold 3

  # -- Public API --

  @doc """
  Query the knowledge store through the Librarian.

  Starts an ephemeral GenServer that performs multi-hop retrieval,
  summarizes results via LLM, and returns a context block with citations.

  Options:
  - `:knowledge_mod` — override Knowledge module (DI, for testing)
  - `:providers_mod` — override Providers module (DI, for testing)
  - `:max_hops` — max retrieval hops (default: #{@max_hops})
  """
  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def query(text, opts \\ []) do
    case DynamicSupervisor.start_child(
           supervisor(opts),
           {__MODULE__, {text, opts, self()}}
         ) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        send(pid, :run)
        await_result(pid, ref)

      {:error, reason} ->
        {:error, {:librarian_start_failed, %{reason: reason}}}
    end
  end

  defp await_result(pid, ref) do
    receive do
      {:librarian_result, ^pid, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, {:librarian_crashed, %{reason: reason}}}
    after
      30_000 ->
        Process.demonitor(ref, [:flush])
        safe_stop(pid)
        {:error, {:librarian_timeout, %{}}}
    end
  end

  defp safe_stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :timeout)
  rescue
    _ -> :ok
  end

  # -- GenServer callbacks --

  def start_link({_text, _opts, _caller} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  @impl true
  def init({text, opts, caller}) do
    {:ok, %{text: text, opts: opts, caller: caller}}
  end

  @impl true
  def handle_info(:run, state) do
    result = do_query(state.text, state.opts)
    send(state.caller, {:librarian_result, self(), result})
    {:stop, :normal, state}
  end

  # -- Internal --

  defp do_query(text, opts) do
    knowledge = knowledge_mod(opts)
    max_hops = Keyword.get(opts, :max_hops, @max_hops)
    knowledge_opts = Keyword.take(opts, [:limit])

    case multi_hop_search(text, knowledge, max_hops, 0, [], knowledge_opts, opts) do
      {:ok, results, hops_taken} when length(results) >= @min_results_for_summary ->
        summarize_results(text, results, hops_taken, opts)

      {:ok, results, hops_taken} ->
        {:ok, %{summary: format_raw_results(results), results: results, hops: hops_taken}}

      {:error, _} = error ->
        error
    end
  end

  defp multi_hop_search(_query, _knowledge, 0, hops_taken, acc, _k_opts, _opts) do
    {:ok, acc, hops_taken}
  end

  defp multi_hop_search(query, knowledge, hops_remaining, hops_taken, acc, k_opts, opts) do
    case knowledge.search(query, k_opts) do
      {:ok, new_results} ->
        combined = merge_results(acc, new_results)
        gaps = detect_gaps(query, combined, opts)

        if gaps != nil and hops_remaining > 1 do
          Logger.debug("[Librarian] Hop #{hops_taken + 1}: refining query for gaps")
          multi_hop_search(gaps, knowledge, hops_remaining - 1, hops_taken + 1, combined, k_opts, opts)
        else
          {:ok, combined, hops_taken + 1}
        end

      {:error, reason} ->
        if acc == [] do
          {:error, reason}
        else
          {:ok, acc, hops_taken}
        end
    end
  end

  defp merge_results(existing, new) do
    existing_ids = MapSet.new(existing, & &1.id)

    new_unique = Enum.reject(new, &MapSet.member?(existing_ids, &1.id))
    existing ++ new_unique
  end

  defp detect_gaps(original_query, results, opts) do
    if length(results) < @gap_threshold do
      ask_for_refinement(original_query, results, opts)
    else
      nil
    end
  end

  defp ask_for_refinement(original_query, results, opts) do
    providers = providers_mod(opts)

    messages = [
      %{
        role: "system",
        content:
          "You are a search refinement assistant. Given a query and search results, " <>
            "identify what information is missing. Return ONLY a refined search query " <>
            "that would fill the gaps, or return exactly \"SUFFICIENT\" if the results " <>
            "adequately cover the query. No explanation."
      },
      %{
        role: "user",
        content: "Original query: #{original_query}\n\nResults found:\n#{format_raw_results(results)}"
      }
    ]

    case providers.chat(messages, []) do
      {:ok, %{content: content}} -> parse_refinement(content)
      {:error, _} -> nil
    end
  end

  defp parse_refinement(content) do
    trimmed = String.trim(content)
    if trimmed == "SUFFICIENT", do: nil, else: trimmed
  end

  defp summarize_results(query, results, hops_taken, opts) do
    providers = providers_mod(opts)

    case providers.chat(
           [
             %{
               role: "system",
               content:
                 "You are a knowledge librarian. Summarize the following search results into a " <>
                   "concise context block relevant to the query. Cite sources using the format " <>
                   "\"[source_file]\" after each claim. Keep the summary focused and actionable."
             },
             %{
               role: "user",
               content: "Query: #{query}\n\nResults:\n#{format_results_for_llm(results)}"
             }
           ],
           []
         ) do
      {:ok, %{content: summary}} ->
        {:ok, %{summary: summary, results: results, hops: hops_taken}}

      {:error, reason} ->
        Logger.warning("[Librarian] Summarization failed: #{inspect(reason)}, using raw results")
        {:ok, %{summary: format_raw_results(results), results: results, hops: hops_taken}}
    end
  end

  defp format_results_for_llm(results) do
    results
    |> Enum.take(20)
    |> Enum.map_join("\n\n", fn result ->
      source = result[:source_file] || "unknown"
      "--- [#{source}] ---\n#{result.text}"
    end)
  end

  defp format_raw_results([]), do: "No relevant context found."

  defp format_raw_results(results) do
    results
    |> Enum.take(10)
    |> Enum.map_join("\n", fn result ->
      source = result[:source_file] || "unknown"
      "[#{source}] #{String.slice(result.text, 0, 200)}"
    end)
  end

  defp knowledge_mod(opts), do: Keyword.get(opts, :knowledge_mod, Familiar.Knowledge)
  defp providers_mod(opts), do: Keyword.get(opts, :providers_mod, Familiar.Providers)
  defp supervisor(opts), do: Keyword.get(opts, :supervisor, Familiar.LibrarianSupervisor)
end
