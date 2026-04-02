defmodule Familiar.Planning.SpecGenerator do
  @moduledoc """
  LLM-driven spec generation with tool dispatch.

  Generates a feature specification by sending the planning conversation
  to the LLM with tool definitions for file reading and knowledge search.
  Tool calls are dispatched, results injected, and the full tool call log
  is captured for the Verification module.
  """

  require Logger

  import Ecto.Query

  alias Familiar.Knowledge.SecretFilter
  alias Familiar.Planning.Message
  alias Familiar.Planning.PromptAssembly
  alias Familiar.Planning.Session
  alias Familiar.Planning.Spec
  alias Familiar.Planning.Verification
  alias Familiar.Repo

  @max_tool_rounds 10

  @spec_generation_prompt """
  Generate a thorough feature specification based on the planning conversation above.

  ## Format Requirements

  1. Start with a level-1 heading: the feature title
  2. Include an "## Assumptions" section listing each assumption about the codebase.
     For each assumption, reference the specific file or table you're basing it on.
  3. Include a "## Conventions Applied" section noting project patterns being followed.
     Use format: "Following existing pattern: <example_file> → <new_file>"
  4. Include an "## Implementation Plan" section with numbered steps.
  5. Reference specific files, tables, migrations, and patterns from the project.
     Use backticks for file paths: `path/to/file.ex`
  6. Do NOT add verification marks (✓/⚠) — those will be added automatically.

  Use the file_read and knowledge_search tools to verify assumptions before stating them.
  """

  @tool_definitions [
    %{
      name: "file_read",
      description: "Read a file from the project directory to verify an assumption",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "Relative file path to read"}
        },
        required: ["path"]
      }
    },
    %{
      name: "knowledge_search",
      description: "Search the project knowledge store for relevant context",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query"}
        },
        required: ["query"]
      }
    }
  ]

  @doc """
  Generate a verified spec from a planning session.

  Calls the LLM with the conversation history and spec generation prompt,
  dispatches tool calls, runs verification, and persists the annotated spec.

  Returns `{:ok, %{spec: Spec.t(), metadata: map(), tool_call_log: [map()]}}`.
  """
  @spec generate(Session.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def generate(session, opts \\ []) do
    with :ok <- validate_specifiable(session) do
      providers = Keyword.get(opts, :providers_mod, Familiar.Providers)
      history = load_messages(session.id)

      {_system, messages} = PromptAssembly.assemble(session.context, history)
      messages = messages ++ [%{role: "user", content: @spec_generation_prompt}]

      case generate_with_tools(messages, providers, opts) do
        {:ok, spec_markdown, tool_call_log} ->
          finalize_spec(session, spec_markdown, tool_call_log, opts)

        {:error, _} = error ->
          error
      end
    end
  end

  # -- Guards --

  defp validate_specifiable(%Session{status: "active"}), do: :ok

  defp validate_specifiable(%Session{status: status}) do
    {:error, {:session_not_specifiable, %{status: status}}}
  end

  # -- Tool dispatch loop --

  defp generate_with_tools(messages, providers, opts) do
    case do_tool_loop(messages, providers, opts, [], @max_tool_rounds) do
      {:ok, content, log} -> {:ok, content, Enum.reverse(log)}
      {:error, _} = error -> error
    end
  end

  defp do_tool_loop(_messages, _providers, _opts, _log, 0) do
    {:error, {:tool_loop_exhausted, %{rounds: @max_tool_rounds}}}
  end

  defp do_tool_loop(messages, providers, opts, log, rounds_left) do
    case call_provider(providers, messages, tools: @tool_definitions) do
      {:ok, %{tool_calls: tool_calls} = response} when is_list(tool_calls) and tool_calls != [] ->
        content = Map.get(response, :content, "")
        {tool_results, new_log_entries} = dispatch_tools(tool_calls, opts)
        tool_messages = build_tool_messages(tool_calls, tool_results)

        updated_messages =
          messages ++
            [%{role: "assistant", content: content || "", tool_calls: tool_calls}] ++
            tool_messages

        # Prepend new entries (reversed at end for correct order)
        do_tool_loop(updated_messages, providers, opts, new_log_entries ++ log, rounds_left - 1)

      {:ok, response} ->
        {:ok, Map.get(response, :content, ""), log}

      {:error, reason} ->
        {:error, {:llm_failed, %{reason: reason}}}
    end
  end

  defp dispatch_tools(tool_calls, opts) do
    fs = file_system(opts)
    knowledge = Keyword.get(opts, :knowledge_mod, Familiar.Knowledge)

    {results, log_entries} =
      Enum.map_reduce(tool_calls, [], fn call, acc ->
        {result, log_entry} = dispatch_single_tool(call, fs, knowledge)
        {result, [log_entry | acc]}
      end)

    {results, Enum.reverse(log_entries)}
  end

  defp dispatch_single_tool(%{name: "file_read"} = call, fs, _knowledge) do
    path = get_in(call, [:arguments, "path"]) || get_in(call, [:arguments, :path]) || ""

    {result, validated_path} =
      case validate_path(path) do
        :ok ->
          case fs.read(path) do
            {:ok, content} -> {SecretFilter.filter(content), path}
            {:error, _} -> {"Error: file not found or unreadable: #{path}", path}
          end

        {:error, reason} ->
          {"Error: #{reason}", path}
      end

    log_entry = %{type: "file_read", path: validated_path, timestamp: DateTime.utc_now()}
    {result, log_entry}
  end

  defp dispatch_single_tool(%{name: "knowledge_search"} = call, _fs, knowledge) do
    query = get_in(call, [:arguments, "query"]) || get_in(call, [:arguments, :query]) || ""

    result =
      case knowledge.search(query) do
        {:ok, entries} ->
          entries
          |> Enum.take(5)
          |> Enum.map_join("\n", fn e -> "[#{e[:source_file] || "?"}] #{e[:text]}" end)
          |> SecretFilter.filter()

        {:error, _} ->
          "Error: knowledge search failed for: #{query}"
      end

    log_entry = %{type: "context_query", path: "knowledge:#{query}", timestamp: DateTime.utc_now()}
    {result, log_entry}
  end

  defp dispatch_single_tool(%{name: name}, _fs, _knowledge) do
    {"Error: unknown tool: #{name}", %{type: "unknown", path: name, timestamp: DateTime.utc_now()}}
  end

  defp validate_path(path) when is_binary(path) and byte_size(path) > 0 do
    if String.starts_with?(path, "/") or String.contains?(path, "..") do
      {:error, "path must be relative and within the project (got: #{path})"}
    else
      :ok
    end
  end

  defp validate_path(_), do: {:error, "path must be a non-empty string"}

  defp build_tool_messages(tool_calls, tool_results) do
    tool_calls
    |> Enum.zip(tool_results)
    |> Enum.with_index()
    |> Enum.map(fn {{call, result}, idx} ->
      id = call[:id] || "#{call[:name]}_#{idx}"
      %{role: "tool", tool_call_id: id, content: result}
    end)
  end

  # -- Finalization --

  defp finalize_spec(session, spec_markdown, tool_call_log, opts) do
    claims = Verification.extract_claims(spec_markdown)
    verified_claims = verify_with_freshness(claims, tool_call_log, opts)
    annotated = Verification.annotate_spec(spec_markdown, verified_claims)
    metadata = Verification.build_metadata(verified_claims, spec_markdown)

    title = extract_title(spec_markdown)
    slug = slugify(title)
    file_path = ".familiar/specs/#{session.id}-#{slug}.md"

    body = build_spec_body(annotated, metadata)
    frontmatter = build_frontmatter(title, session.id, metadata)
    full_content = frontmatter <> body

    with :ok <- write_spec_file(file_path, full_content, opts),
         {:ok, spec} <- persist_spec(session, title, body, metadata, file_path),
         :ok <- complete_session(session) do
      {:ok, %{spec: spec, metadata: metadata, tool_call_log: tool_call_log, file_path: file_path}}
    end
  end

  defp verify_with_freshness(claims, tool_call_log, opts) do
    freshness_map = build_freshness_map(tool_call_log, opts)
    verified = Verification.verify_claims(claims, tool_call_log)
    Enum.map(verified, &apply_freshness(&1, freshness_map))
  end

  defp build_freshness_map(tool_call_log, opts) do
    fs = file_system(opts)

    tool_call_log
    |> Enum.filter(&(&1.type == "file_read"))
    |> Map.new(fn entry -> {entry.path, check_file_freshness(fs, entry.path)} end)
  end

  defp check_file_freshness(fs, path) do
    case fs.stat(path) do
      {:ok, _stat} -> :fresh
      {:error, {:file_error, %{reason: :enoent}}} -> :deleted
      {:error, :enoent} -> :deleted
      {:error, _} -> :stale
    end
  end

  defp apply_freshness(%{status: :verified, source: source} = result, freshness_map)
       when not is_nil(source) do
    case Map.get(freshness_map, source) do
      :deleted -> %{result | status: :unverified, source: "#{source} (file not found)"}
      :stale -> %{result | status: :unverified, source: "#{source} (stale)"}
      _ -> result
    end
  end

  defp apply_freshness(result, _freshness_map), do: result

  defp extract_title(markdown) when is_binary(markdown) do
    case Regex.run(~r/^#\s+(.+)$/m, markdown) do
      [_, title] -> String.trim(title)
      _ -> "Untitled Spec"
    end
  end

  defp extract_title(_), do: "Untitled Spec"

  defp slugify(title) do
    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)

    if slug == "", do: "untitled", else: slug
  end

  defp build_spec_body(annotated_markdown, metadata) do
    date = Date.utc_today() |> Date.to_iso8601()

    meta_line =
      "Generated #{date} · #{metadata.verified_count} verified · " <>
        "#{metadata.unverified_count} unverified · #{metadata.conventions_count} conventions applied"

    case String.split(annotated_markdown || "", "\n", parts: 2) do
      [heading, rest] -> "#{heading}\n\n#{meta_line}\n\n#{rest}"
      [single] -> "#{single}\n\n#{meta_line}"
    end
  end

  defp build_frontmatter(title, session_id, metadata) do
    date = DateTime.utc_now() |> DateTime.to_iso8601()
    escaped_title = title |> String.replace("\"", "\\\"") |> String.replace("\n", " ")

    """
    ---
    title: "#{escaped_title}"
    session_id: #{session_id}
    status: draft
    generated_at: #{date}
    verified: #{metadata.verified_count}
    unverified: #{metadata.unverified_count}
    conventions: #{metadata.conventions_count}
    ---

    """
  end

  defp write_spec_file(file_path, content, opts) do
    fs = file_system(opts)

    case fs.write(file_path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:spec_write_failed, %{reason: reason, path: file_path}}}
    end
  end

  defp persist_spec(session, title, body, metadata, file_path) do
    metadata_json =
      Jason.encode!(%{
        verified_count: metadata.verified_count,
        unverified_count: metadata.unverified_count,
        conventions_count: metadata.conventions_count,
        total_claims: metadata.total_claims
      })

    %Spec{}
    |> Spec.changeset(%{
      session_id: session.id,
      title: SecretFilter.filter(title),
      body: SecretFilter.filter(body),
      metadata: metadata_json,
      file_path: file_path
    })
    |> Repo.insert()
    |> case do
      {:ok, spec} -> {:ok, spec}
      {:error, changeset} -> {:error, {:spec_persist_failed, %{changeset: changeset}}}
    end
  end

  # Best-effort session completion — spec is already persisted, so a
  # status update failure should not roll back the entire operation.
  defp complete_session(session) do
    session
    |> Session.changeset(%{status: "completed"})
    |> Repo.update()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[SpecGenerator] Failed to complete session #{session.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp load_messages(session_id) do
    from(m in Message, where: m.session_id == ^session_id, order_by: [asc: m.inserted_at])
    |> Repo.all()
    |> Enum.map(&message_to_map/1)
  end

  defp message_to_map(m) do
    base = %{role: m.role, content: m.content}
    maybe_add_tool_calls(base, m)
  end

  defp maybe_add_tool_calls(base, %{role: "assistant", tool_calls: tc})
       when tc not in [nil, "[]"] do
    case Jason.decode(tc) do
      {:ok, calls} when calls != [] -> Map.put(base, :tool_calls, calls)
      _ -> base
    end
  end

  defp maybe_add_tool_calls(base, _message), do: base

  defp call_provider(%{chat: fun}, messages, opts) when is_function(fun, 2), do: fun.(messages, opts)
  defp call_provider(module, messages, opts) when is_atom(module), do: module.chat(messages, opts)

  defp file_system(opts) do
    Keyword.get_lazy(opts, :file_system, fn ->
      Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
    end)
  end
end
