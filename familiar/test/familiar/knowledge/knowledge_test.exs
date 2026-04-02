defmodule Familiar.Knowledge.KnowledgeTest do
  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbedderMock
  alias Familiar.Knowledge.Entry

  # async: false because sqlite-vec virtual tables
  # don't participate in Ecto sandbox transactions.

  setup :verify_on_exit!

  setup do
    Familiar.Repo.query!("DELETE FROM knowledge_entry_embeddings")
    :ok
  end

  describe "fetch_entry/1" do
    test "returns {:ok, entry} for existing entry" do
      {:ok, entry} =
        Repo.insert(
          Entry.changeset(%Entry{}, %{
            text: "Auth uses JWT tokens",
            type: "convention",
            source: "init_scan",
            source_file: "lib/auth.ex"
          })
        )

      assert {:ok, fetched} = Knowledge.fetch_entry(entry.id)
      assert fetched.id == entry.id
      assert fetched.text == "Auth uses JWT tokens"
      assert fetched.type == "convention"
      assert fetched.source == "init_scan"
      assert fetched.source_file == "lib/auth.ex"
    end

    test "returns {:error, {:not_found, _}} for non-existent ID" do
      assert {:error, {:not_found, %{id: 99_999}}} = Knowledge.fetch_entry(99_999)
    end

    test "returns {:error, {:not_found, _}} for nil ID" do
      assert {:error, {:not_found, %{id: nil}}} = Knowledge.fetch_entry(nil)
    end
  end

  describe "store/1" do
    test "stores entry with embedding and returns it" do
      vector = deterministic_vector(1.0, 0.0)
      expect(EmbedderMock, :embed, fn _text -> {:ok, vector} end)

      assert {:ok, entry} =
               Knowledge.store(%{
                 text: "Auth module uses JWT tokens for API authentication",
                 type: "convention",
                 source: "manual",
                 source_file: "lib/auth.ex"
               })

      assert entry.id
      assert entry.text =~ "JWT tokens"
    end

    test "rejects raw code content" do
      code = """
      defmodule MyApp.Auth do
        def verify(token) do
          JWT.decode(token)
        end
      end
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} = Knowledge.store(%{
               text: code,
               type: "convention",
               source: "manual"
             })
    end

    test "returns changeset validation error for missing type/source" do
      # No embed mock needed — changeset validation fails before embedding
      assert {:error, {:validation_failed, %{changeset: _}}} =
               Knowledge.store(%{text: "Some knowledge about the project"})
    end

    test "returns changeset validation error for missing text (not knowledge_not_code)" do
      # Missing text should produce :validation_failed, not :knowledge_not_code
      assert {:error, {:validation_failed, %{changeset: changeset}}} =
               Knowledge.store(%{type: "convention", source: "manual"})

      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "propagates embedding failure" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      assert {:error, {:provider_unavailable, _}} =
               Knowledge.store(%{
                 text: "Some knowledge about the project",
                 type: "convention",
                 source: "manual"
               })
    end
  end

  describe "search/1" do
    test "returns results ranked by distance" do
      v_close = deterministic_vector(1.0, 0.0)
      v_far = deterministic_vector(0.0, 1.0)

      EmbedderMock
      |> expect(:embed, fn "Auth uses JWT" -> {:ok, v_close} end)
      |> expect(:embed, fn "Database uses PostgreSQL" -> {:ok, v_far} end)
      |> expect(:embed, fn "authentication query" -> {:ok, v_close} end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Auth uses JWT",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Database uses PostgreSQL",
          type: "architecture",
          source: "init_scan",
          source_file: "lib/repo.ex"
        })

      assert {:ok, results} = Knowledge.search("authentication query")
      assert length(results) == 2

      [first, second] = results
      assert first.id
      assert first.text == "Auth uses JWT"
      assert first.type == "convention"
      assert first.source == "init_scan"
      assert first.source_file == "lib/auth.ex"
      assert first.distance <= second.distance
      assert first.inserted_at
    end

    test "returns empty list for empty query without calling embedder" do
      # No embed mock needed — empty query short-circuits
      assert {:ok, []} = Knowledge.search("")
      assert {:ok, []} = Knowledge.search("   ")
    end

    test "returns empty list when no entries exist" do
      v = deterministic_vector(0.5, 0.5)
      expect(EmbedderMock, :embed, fn _query -> {:ok, v} end)

      assert {:ok, []} = Knowledge.search("anything")
    end

    test "returns error when embedding fails" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      assert {:error, {:provider_unavailable, _}} = Knowledge.search("query")
    end
  end

  describe "full CRUD cycle" do
    test "store → fetch → search → verify" do
      v1 = deterministic_vector(1.0, 0.0)
      v2 = deterministic_vector(0.0, 1.0)

      EmbedderMock
      |> expect(:embed, fn "Auth uses JWT" -> {:ok, v1} end)
      |> expect(:embed, fn "DB uses PostgreSQL" -> {:ok, v2} end)
      |> expect(:embed, fn "auth" -> {:ok, v1} end)

      # Store
      assert {:ok, entry1} =
               Knowledge.store(%{
                 text: "Auth uses JWT",
                 type: "fact",
                 source: "user",
                 source_file: "lib/auth.ex"
               })

      assert {:ok, entry2} =
               Knowledge.store(%{
                 text: "DB uses PostgreSQL",
                 type: "architecture",
                 source: "agent"
               })

      # Fetch
      assert {:ok, fetched} = Knowledge.fetch_entry(entry1.id)
      assert fetched.text == "Auth uses JWT"
      assert fetched.type == "fact"
      assert fetched.source == "user"

      # Search
      assert {:ok, results} = Knowledge.search("auth")
      assert length(results) == 2
      assert hd(results).text == "Auth uses JWT"
      assert hd(results).type == "fact"
      assert hd(results).source == "user"
      assert hd(results).source_file == "lib/auth.ex"

      # Verify second entry also accessible
      assert {:ok, fetched2} = Knowledge.fetch_entry(entry2.id)
      assert fetched2.type == "architecture"
      assert fetched2.source == "agent"
    end
  end

  describe "store/1 with new types and sources" do
    test "accepts gotcha type" do
      expect(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1.0, 0.0)} end)

      assert {:ok, entry} =
               Knowledge.store(%{
                 text: "Session middleware has conflicting patterns for web vs API",
                 type: "gotcha",
                 source: "post_task"
               })

      assert entry.type == "gotcha"
    end

    test "accepts fact type with agent source" do
      expect(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1.0, 0.0)} end)

      assert {:ok, entry} =
               Knowledge.store(%{
                 text: "Project uses Phoenix 1.8 with LiveView",
                 type: "fact",
                 source: "agent"
               })

      assert entry.type == "fact"
      assert entry.source == "agent"
    end
  end

  # Generate a deterministic 768-dimensional vector.
  defp deterministic_vector(primary, secondary) do
    half = div(768, 2)
    List.duplicate(primary, half) ++ List.duplicate(secondary, half)
  end
end
