defmodule Familiar.Extensions.KnowledgeStoreTest do
  use Familiar.DataCase, async: false

  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]
  import Mox

  alias Familiar.Extensions.KnowledgeStore
  alias Familiar.Hooks
  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Stub embedder for search/store operations
    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, zero_vector()} end)

    # Stub FileSystem for freshness
    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-02 12:00:00Z] end)

    :ok
  end

  # == AC1: Extension Behaviour ==

  describe "extension behaviour" do
    test "name returns 'knowledge-store'" do
      assert KnowledgeStore.name() == "knowledge-store"
    end

    test "tools returns search_context and store_context" do
      tools = KnowledgeStore.tools()
      assert length(tools) == 2

      names = Enum.map(tools, &elem(&1, 0))
      assert :search_context in names
      assert :store_context in names

      Enum.each(tools, fn {_name, fun, desc} ->
        assert is_function(fun, 2)
        assert is_binary(desc)
      end)
    end

    test "hooks returns on_agent_complete and on_file_changed event hooks" do
      hooks = KnowledgeStore.hooks()
      assert length(hooks) == 2

      hook_names = Enum.map(hooks, & &1.hook)
      assert :on_agent_complete in hook_names
      assert :on_file_changed in hook_names

      Enum.each(hooks, fn hook ->
        assert hook.type == :event
        assert hook.priority == 100
      end)
    end

    test "init returns :ok" do
      assert :ok = KnowledgeStore.init([])
    end
  end

  # == AC2: search_context Tool ==

  describe "search_context/2" do
    test "returns results for valid query" do
      # Insert an entry with embedding
      {:ok, entry} =
        Familiar.Knowledge.store(%{
          text: "Uses JWT for authentication",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      assert {:ok, results} = KnowledgeStore.search_context(%{query: "authentication"}, %{})
      assert is_list(results)
      assert results != []

      result = hd(results)
      assert result.id == entry.id
      assert result.text == "Uses JWT for authentication"
    end

    test "returns empty list for empty query" do
      assert {:ok, []} = KnowledgeStore.search_context(%{query: ""}, %{})
    end

    test "returns empty list for nil query" do
      assert {:ok, []} = KnowledgeStore.search_context(%{query: nil}, %{})
    end

    test "returns empty list for non-string query" do
      assert {:ok, []} = KnowledgeStore.search_context(%{query: 42}, %{})
      assert {:ok, []} = KnowledgeStore.search_context(%{query: true}, %{})
    end

    test "supports string keys in args" do
      assert {:ok, []} = KnowledgeStore.search_context(%{"query" => ""}, %{})
    end

    test "returns error when embedding fails" do
      Familiar.Knowledge.EmbedderMock
      |> expect(:embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      assert {:error, _} = KnowledgeStore.search_context(%{query: "test"}, %{})
    end
  end

  # == AC3: store_context Tool ==

  describe "store_context/2" do
    test "stores entry with valid attrs" do
      args = %{text: "New fact about the project", type: "fact", source: "agent"}

      assert {:ok, result} = KnowledgeStore.store_context(args, %{})
      assert result.id
      assert result.text == "New fact about the project"
      assert result.type == "fact"
    end

    test "supports string keys in args" do
      args = %{"text" => "String key fact", "type" => "fact", "source" => "agent"}

      assert {:ok, result} = KnowledgeStore.store_context(args, %{})
      assert result.text == "String key fact"
    end

    test "returns error for invalid type format" do
      args = %{text: "Bad type", type: "Has Spaces", source: "agent"}

      assert {:error, {:validation_failed, _}} = KnowledgeStore.store_context(args, %{})
    end

    test "returns error for missing text" do
      args = %{type: "fact", source: "agent"}

      # Knowledge.store handles nil text by delegating to store_with_embedding
      # which validates via changeset — text is required
      assert {:error, _} = KnowledgeStore.store_context(args, %{})
    end

    test "stores entry with optional source_file and metadata" do
      args = %{
        text: "File-based fact",
        type: "file_summary",
        source: "init_scan",
        source_file: "lib/foo.ex",
        metadata: Jason.encode!(%{lines: 42})
      }

      assert {:ok, result} = KnowledgeStore.store_context(args, %{})
      assert result.text == "File-based fact"
    end
  end

  # == AC4: on_agent_complete Event Hook ==

  describe "handle_agent_complete/1" do
    test "triggers hygiene without crashing" do
      # Stub LLM for hygiene extraction — return empty to avoid complex mocking
      Familiar.Providers.LLMMock
      |> stub(:chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      payload = %{
        agent_id: "agent_1",
        role: "dev",
        result: "Implemented the feature"
      }

      # Should not raise — fire and forget
      assert KnowledgeStore.handle_agent_complete(payload)
      # Give async task time to run
      Process.sleep(20)
    end

    test "handles nil result gracefully" do
      Familiar.Providers.LLMMock
      |> stub(:chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      payload = %{agent_id: "agent_2", role: "dev", result: nil}
      assert KnowledgeStore.handle_agent_complete(payload)
      Process.sleep(100)
    end
  end

  # == AC5: on_file_changed Event Hook ==

  describe "handle_file_changed/1" do
    test "deletes entries for deleted file" do
      {:ok, entry} =
        Repo.insert(
          Entry.changeset(%Entry{}, %{
            text: "Summary of deleted file",
            type: "file_summary",
            source: "init_scan",
            source_file: "lib/deleted.ex"
          })
        )

      KnowledgeStore.handle_file_changed(%{path: "lib/deleted.ex", type: :deleted})
      # Give async task time
      Process.sleep(20)

      assert Repo.get(Entry, entry.id) == nil
    end

    test "does not delete entries for other files" do
      {:ok, entry} =
        Repo.insert(
          Entry.changeset(%Entry{}, %{
            text: "Summary of kept file",
            type: "file_summary",
            source: "init_scan",
            source_file: "lib/kept.ex"
          })
        )

      KnowledgeStore.handle_file_changed(%{path: "lib/other.ex", type: :deleted})
      Process.sleep(20)

      assert Repo.get(Entry, entry.id) != nil
    end

    test "changed event refreshes but does not delete entries" do
      stub(Familiar.System.FileSystemMock, :read, fn _path -> {:ok, "updated content"} end)
      stub(Familiar.Providers.LLMMock, :chat, fn _msgs, _opts -> {:ok, %{content: "[]"}} end)

      {:ok, entry} =
        Repo.insert(
          Entry.changeset(%Entry{}, %{
            text: "Summary of changed file",
            type: "file_summary",
            source: "init_scan",
            source_file: "lib/changed.ex"
          })
        )

      KnowledgeStore.handle_file_changed(%{path: "lib/changed.ex", type: :changed})
      Process.sleep(20)

      # Entry still exists (refresh, not delete)
      assert Repo.get(Entry, entry.id) != nil
    end

    test "created event for file with existing entries triggers refresh" do
      stub(Familiar.System.FileSystemMock, :read, fn _path -> {:ok, "new content"} end)
      stub(Familiar.Providers.LLMMock, :chat, fn _msgs, _opts -> {:ok, %{content: "[]"}} end)

      {:ok, entry} =
        Repo.insert(
          Entry.changeset(%Entry{}, %{
            text: "Summary of recreated file",
            type: "file_summary",
            source: "init_scan",
            source_file: "lib/recreated.ex"
          })
        )

      KnowledgeStore.handle_file_changed(%{path: "lib/recreated.ex", type: :created})
      Process.sleep(20)

      # Entry still exists
      assert Repo.get(Entry, entry.id) != nil
    end

    test "handles unexpected payload shape" do
      # Should not raise
      assert :ok = KnowledgeStore.handle_file_changed(%{unexpected: true})
    end
  end

  # == Integration: hooks registration contract ==

  describe "hooks integration" do
    setup do
      hooks =
        start_supervised!({Hooks, name: :"hooks_ks_#{System.unique_integer([:positive])}"})

      {:ok, hooks: hooks}
    end

    test "hooks/0 handlers can be registered with Hooks GenServer", %{hooks: hooks} do
      for hook_reg <- KnowledgeStore.hooks() do
        assert :ok =
                 GenServer.call(
                   hooks,
                   {:register_event, hook_reg.hook, hook_reg.handler, KnowledgeStore.name()}
                 )
      end
    end

    test "tools/0 functions have correct arity" do
      for {_name, fun, _desc} <- KnowledgeStore.tools() do
        assert is_function(fun, 2)
      end
    end
  end
end
