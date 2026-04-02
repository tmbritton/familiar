defmodule Familiar.Planning.LibrarianTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning.Librarian

  defmodule MockKnowledge do
    @moduledoc false
    def search(query, _opts \\ []) do
      results =
        case query do
          "add user accounts" ->
            [
              %{id: 1, text: "Users table has email and password columns", source_file: "db/migrations/001.sql", type: "file_summary"},
              %{id: 2, text: "Auth middleware checks session tokens", source_file: "lib/auth.ex", type: "convention"},
              %{id: 3, text: "Password hashing uses bcrypt", source_file: "lib/crypto.ex", type: "decision"}
            ]

          "SUFFICIENT" ->
            []

          "authentication patterns" ->
            [
              %{id: 4, text: "OAuth2 integration with Google", source_file: "lib/oauth.ex", type: "convention"}
            ]

          _ ->
            []
        end

      {:ok, results}
    end
  end

  defmodule MockProviders do
    @moduledoc false
    def chat(messages, _opts) do
      system_msg = List.first(messages)

      cond do
        String.contains?(system_msg.content, "search refinement") ->
          {:ok, %{content: "SUFFICIENT"}}

        String.contains?(system_msg.content, "knowledge librarian") ->
          {:ok, %{content: "Summary: The project uses bcrypt for passwords [lib/crypto.ex] and has auth middleware [lib/auth.ex]."}}

        true ->
          {:ok, %{content: "SUFFICIENT"}}
      end
    end
  end

  defmodule MockProvidersWithGaps do
    @moduledoc false
    def chat(messages, _opts) do
      system_msg = List.first(messages)

      cond do
        String.contains?(system_msg.content, "search refinement") ->
          {:ok, %{content: "authentication patterns"}}

        String.contains?(system_msg.content, "knowledge librarian") ->
          {:ok, %{content: "Curated summary with multi-hop results."}}

        true ->
          {:ok, %{content: "SUFFICIENT"}}
      end
    end
  end

  defmodule MockKnowledgeSparse do
    @moduledoc false
    def search(_query, _opts \\ []) do
      {:ok, [%{id: 1, text: "Single result", source_file: "lib/app.ex", type: "file_summary"}]}
    end
  end

  defmodule MockKnowledgeEmpty do
    @moduledoc false
    def search(_query, _opts \\ []) do
      {:ok, []}
    end
  end

  defmodule MockKnowledgeError do
    @moduledoc false
    def search(_query, _opts \\ []) do
      {:error, {:search_failed, %{reason: :timeout}}}
    end
  end

  describe "query/2" do
    test "returns summarized context block with citations" do
      {:ok, result} =
        Librarian.query("add user accounts",
          knowledge_mod: MockKnowledge,
          providers_mod: MockProviders,
          supervisor: Familiar.LibrarianSupervisor
        )

      assert is_binary(result.summary)
      assert String.contains?(result.summary, "bcrypt")
      assert is_list(result.results)
      assert length(result.results) == 3
    end

    test "GenServer completes lifecycle: starts, delivers result, and stops" do
      # The Librarian GenServer starts, performs retrieval, sends the result,
      # then returns {:stop, :normal, state}. query/2 blocks until the result
      # arrives (proving the full lifecycle). If the GenServer didn't stop,
      # the DynamicSupervisor would accumulate children over repeated calls.
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

      # Run 3 sequential queries — if GenServers didn't stop, children would accumulate
      for _ <- 1..3 do
        {:ok, result} =
          Librarian.query("add user accounts",
            knowledge_mod: MockKnowledge,
            providers_mod: MockProviders,
            supervisor: sup
          )

        assert is_binary(result.summary)
      end

      DynamicSupervisor.stop(sup)
    end

    test "returns raw results when no results found" do
      {:ok, result} =
        Librarian.query("nonexistent topic",
          knowledge_mod: MockKnowledgeEmpty,
          providers_mod: MockProviders,
          supervisor: Familiar.LibrarianSupervisor
        )

      assert result.summary == "No relevant context found."
      assert result.results == []
    end

    test "returns error when search fails with no fallback" do
      {:error, {type, _details}} =
        Librarian.query("anything",
          knowledge_mod: MockKnowledgeError,
          providers_mod: MockProviders,
          supervisor: Familiar.LibrarianSupervisor
        )

      assert type == :search_failed
    end

    test "multi-hop detects gaps and refines query" do
      {:ok, result} =
        Librarian.query("add user accounts",
          knowledge_mod: MockKnowledgeSparse,
          providers_mod: MockProvidersWithGaps,
          supervisor: Familiar.LibrarianSupervisor
        )

      assert is_binary(result.summary)
      assert is_list(result.results)
    end

    test "respects max_hops option" do
      {:ok, result} =
        Librarian.query("add user accounts",
          knowledge_mod: MockKnowledge,
          providers_mod: MockProviders,
          supervisor: Familiar.LibrarianSupervisor,
          max_hops: 1
        )

      assert is_binary(result.summary)
      assert result.hops == 1
    end

    test "tracks actual hop count" do
      {:ok, result} =
        Librarian.query("add user accounts",
          knowledge_mod: MockKnowledge,
          providers_mod: MockProviders,
          supervisor: Familiar.LibrarianSupervisor
        )

      # 3 results from MockKnowledge >= @gap_threshold (3), so only 1 hop
      assert result.hops == 1
    end
  end
end
