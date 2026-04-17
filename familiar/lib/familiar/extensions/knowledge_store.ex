defmodule Familiar.Extensions.KnowledgeStore do
  @moduledoc """
  Default extension wrapping the Knowledge context for agent use.

  Registers two tools and two event hooks:

  ## Tools

    * `:search_context` — semantic search of the knowledge store
    * `:store_context` — insert a new knowledge entry

  ## Hooks

    * `:on_agent_complete` — triggers post-task hygiene loop
    * `:on_file_changed` — invalidates/refreshes entries for changed files
  """

  @behaviour Familiar.Extension

  require Logger

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Freshness
  alias Familiar.Knowledge.Hygiene

  # -- Extension Callbacks --

  @impl true
  def name, do: "knowledge-store"

  @impl true
  def tools do
    [
      {:search_context, &search_context/2, "Semantic search of the knowledge store",
       %{
         "type" => "object",
         "properties" => %{
           "query" => %{"type" => "string", "description" => "Search query"}
         },
         "required" => ["query"]
       }},
      {:store_context, &store_context/2, "Insert a new knowledge entry",
       %{
         "type" => "object",
         "properties" => %{
           "text" => %{"type" => "string", "description" => "Knowledge entry text"},
           "type" => %{
             "type" => "string",
             "description" =>
               "Entry type — any lowercase snake_case slug (e.g. convention, fact, decision, gotcha, file_summary, architecture)"
           }
         },
         "required" => ["text", "type"]
       }}
    ]
  end

  @impl true
  def hooks do
    [
      %{hook: :on_agent_complete, handler: &handle_agent_complete/1, priority: 100, type: :event},
      %{hook: :on_file_changed, handler: &handle_file_changed/1, priority: 100, type: :event}
    ]
  end

  @impl true
  def init(_opts), do: :ok

  # -- Tool Functions --

  @doc false
  def search_context(args, _context) do
    query = Map.get(args, :query, Map.get(args, "query"))
    query = if is_binary(query), do: query, else: ""
    opts = extract_search_opts(args)
    Knowledge.search(query, opts)
  end

  @doc false
  def store_context(args, _context) do
    attrs = normalize_store_attrs(args)

    case Knowledge.store(attrs) do
      {:ok, entry} ->
        {:ok, %{id: entry.id, text: entry.text, type: entry.type}}

      {:error, _reason} = error ->
        error
    end
  end

  # -- Event Handlers --

  @doc false
  def handle_agent_complete(payload) do
    Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
      context = build_hygiene_context(payload)

      {:ok, stats} = Hygiene.run(context)

      Logger.info(
        "[KnowledgeStore] Hygiene complete: " <>
          "#{stats.extracted} extracted, #{stats.updated} updated, #{stats.skipped} skipped"
      )
    end)
  rescue
    error ->
      Logger.warning("[KnowledgeStore] Failed to start hygiene task: #{Exception.message(error)}")
  end

  @doc false
  def handle_file_changed(%{path: path, type: event_type}) when is_binary(path) do
    Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
      entries = Knowledge.list_by_source_file(path)
      process_file_event(event_type, entries, path)
    end)
  rescue
    error ->
      Logger.warning(
        "[KnowledgeStore] Failed to handle file change for #{inspect(path)}: #{Exception.message(error)}"
      )
  end

  # Handle unexpected payload shape
  def handle_file_changed(_payload), do: :ok

  # -- Private: File Event Processing --

  defp process_file_event(:deleted, [], _path), do: :ok

  defp process_file_event(:deleted, entries, path) do
    results = for entry <- entries, do: Knowledge.delete_entry(entry)
    failed = Enum.count(results, &match?({:error, _}, &1))

    if failed > 0,
      do: Logger.warning("[KnowledgeStore] #{failed} delete(s) failed for file: #{path}")

    Logger.info(
      "[KnowledgeStore] Removed #{length(entries) - failed} entries for deleted file: #{path}"
    )
  end

  defp process_file_event(type, entries, path)
       when type in [:changed, :created] and entries != [] do
    Freshness.refresh_stale(entries)

    Logger.info(
      "[KnowledgeStore] Refreshing #{length(entries)} entries for changed file: #{path}"
    )
  end

  defp process_file_event(_type, _entries, _path), do: :ok

  # -- Private --

  defp extract_search_opts(args) do
    limit = Map.get(args, :limit, Map.get(args, "limit"))
    if limit, do: [limit: limit], else: []
  end

  defp normalize_store_attrs(args) do
    %{}
    |> put_if_present(args, :text)
    |> put_if_present(args, :type)
    |> put_if_present(args, :source)
    |> put_if_present(args, :source_file)
    |> put_if_present(args, :metadata)
  end

  defp put_if_present(map, args, key) do
    value = Map.get(args, key, Map.get(args, to_string(key)))
    if is_nil(value), do: map, else: Map.put(map, key, value)
  end

  defp build_hygiene_context(payload) do
    # Pass through the full payload as success_context so Hygiene can
    # access all fields (result, role, agent_id, task_summary, modified_files, etc.)
    %{success_context: payload}
  end
end
