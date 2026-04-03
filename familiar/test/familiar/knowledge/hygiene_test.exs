defmodule Familiar.Knowledge.HygieneTest do
  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbedderMock
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Hygiene
  alias Familiar.Providers.LLMMock
  alias Familiar.System.ClockMock
  alias Familiar.System.FileSystemMock

  # async: false because sqlite-vec virtual tables
  # don't participate in Ecto sandbox transactions.

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Familiar.Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Stub FileSystem and Clock for any indirect freshness checks
    stub(FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(ClockMock, :now, fn -> ~U[2026-04-02 12:00:00Z] end)

    :ok
  end

  # -- Task 1: Core structure --

  describe "run/2 core structure" do
    test "returns {:ok, summary} with zero counts for empty context" do
      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(%{}, llm: LLMMock)
    end

    test "returns {:ok, summary} when success_context is nil" do
      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(%{success_context: nil, failure_log: nil}, llm: LLMMock)
    end

    test "accepts DI via opts for LLM" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      assert {:ok, _} = Hygiene.run(%{success_context: %{task_summary: "test"}}, llm: LLMMock)
    end
  end

  # -- Task 2: Success extraction --

  describe "extract_from_success/2" do
    test "extracts entries with correct types and source from LLM response" do
      llm_response =
        Jason.encode!([
          %{
            "type" => "fact",
            "text" => "Phoenix uses conn-based middleware",
            "source_file" => "lib/auth.ex"
          },
          %{
            "type" => "decision",
            "text" => "Chose cookie sessions for web",
            "source_file" => "lib/auth.ex"
          }
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      context = %{
        success_context: %{
          task_summary: "Added auth middleware",
          modified_files: ["lib/auth.ex"],
          decisions_made: "Cookie sessions for web"
        },
        modified_files: ["lib/auth.ex"]
      }

      entries = Hygiene.extract_from_success(context, llm: LLMMock)

      assert length(entries) == 2
      assert Enum.all?(entries, fn e -> e.source == "post_task" end)
      assert Enum.map(entries, & &1.type) == ["fact", "decision"]
    end

    test "returns empty list for nil success_context" do
      assert [] == Hygiene.extract_from_success(%{success_context: nil}, llm: LLMMock)
    end

    test "returns empty list for empty success_context map" do
      assert [] == Hygiene.extract_from_success(%{success_context: %{}}, llm: LLMMock)
    end

    test "filters out invalid types like file_summary" do
      llm_response =
        Jason.encode!([
          %{
            "type" => "file_summary",
            "text" => "This is a summary",
            "source_file" => "lib/foo.ex"
          },
          %{"type" => "fact", "text" => "Valid fact entry", "source_file" => "lib/foo.ex"}
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: ["lib/foo.ex"]
      }

      entries = Hygiene.extract_from_success(context, llm: LLMMock)

      assert length(entries) == 1
      assert hd(entries).type == "fact"
    end

    test "applies SecretFilter to extracted text" do
      llm_response =
        Jason.encode!([
          %{
            "type" => "fact",
            "text" => "Uses AWS key AKIAIOSFODNN7EXAMPLE for S3",
            "source_file" => "lib/s3.ex"
          }
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      context = %{
        success_context: %{task_summary: "S3 integration"},
        modified_files: ["lib/s3.ex"]
      }

      entries = Hygiene.extract_from_success(context, llm: LLMMock)

      assert length(entries) == 1
      assert hd(entries).text =~ "[AWS_ACCESS_KEY]"
      refute hd(entries).text =~ "AKIAIOSFODNN7EXAMPLE"
    end

    test "returns empty list when LLM fails" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: []
      }

      assert [] == Hygiene.extract_from_success(context, llm: LLMMock)
    end
  end

  # -- Task 3: Failure extraction --

  describe "extract_from_failure/2" do
    test "extracts gotcha entries from failure log" do
      llm_response =
        Jason.encode!([
          %{
            "type" => "gotcha",
            "text" => "Session middleware has conflicting patterns",
            "source_file" => "lib/auth.ex"
          }
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      context = %{failure_log: "Session middleware has two conflicting patterns"}

      entries = Hygiene.extract_from_failure(context, llm: LLMMock)

      assert length(entries) == 1
      assert hd(entries).type == "gotcha"
      assert hd(entries).source == "post_task"
    end

    test "returns empty list for nil failure_log" do
      assert [] == Hygiene.extract_from_failure(%{failure_log: nil}, llm: LLMMock)
    end

    test "returns empty list for empty failure_log" do
      assert [] == Hygiene.extract_from_failure(%{failure_log: ""}, llm: LLMMock)
    end

    test "only keeps gotcha type from failure extraction" do
      llm_response =
        Jason.encode!([
          %{"type" => "decision", "text" => "Should not appear", "source_file" => "lib/foo.ex"},
          %{"type" => "gotcha", "text" => "Edge case with nil", "source_file" => "lib/foo.ex"},
          %{"type" => "fact", "text" => "Also should not appear", "source_file" => "lib/foo.ex"}
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      context = %{failure_log: "Task failed due to nil handling"}

      entries = Hygiene.extract_from_failure(context, llm: LLMMock)

      assert length(entries) == 1
      assert hd(entries).type == "gotcha"
      assert hd(entries).text == "Edge case with nil"
    end
  end

  # -- Task 4: Duplicate detection --

  describe "store_with_dedup/2 duplicate detection" do
    test "stores new entry when no match exists" do
      # Single embed call: store_with_dedup embeds upfront, reuses vector for search + store
      expect(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      entries = [
        %{
          text: "New fact about the codebase",
          type: "fact",
          source: "post_task",
          source_file: "lib/foo.ex",
          metadata: Jason.encode!(%{})
        }
      ]

      assert {:ok, %{extracted: 1, updated: 0, skipped: 0}} = Hygiene.store_with_dedup(entries)

      # Verify entry was stored
      stored = Repo.all(Entry)
      assert length(stored) == 1
      assert hd(stored).text == "New fact about the codebase"
    end

    test "updates existing entry when duplicate found (same source_file + similar text)" do
      # Store an existing entry first
      existing_vector = deterministic_vector(1, 0)

      expect(EmbedderMock, :embed, fn "Existing fact about auth" -> {:ok, existing_vector} end)

      {:ok, existing} =
        Knowledge.store_with_embedding(%{
          text: "Existing fact about auth",
          type: "fact",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        })

      # Now run dedup — single embed call upfront, reused for search + update
      new_vector = deterministic_vector(1, 0)
      expect(EmbedderMock, :embed, fn "Updated fact about auth patterns" -> {:ok, new_vector} end)

      entries = [
        %{
          text: "Updated fact about auth patterns",
          type: "fact",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        }
      ]

      assert {:ok, %{extracted: 0, updated: 1, skipped: 0}} = Hygiene.store_with_dedup(entries)

      # Verify existing entry was updated, not duplicated
      all_entries = Repo.all(Entry)
      assert length(all_entries) == 1
      assert hd(all_entries).id == existing.id
      assert hd(all_entries).text == "Updated fact about auth patterns"

      # Verify metadata counter incremented
      meta = Jason.decode!(hd(all_entries).metadata)
      assert meta["update_count"] == 1
    end

    test "updates type field when superseding" do
      existing_vector = deterministic_vector(1, 0)

      expect(EmbedderMock, :embed, fn "Auth pattern" -> {:ok, existing_vector} end)

      {:ok, existing} =
        Knowledge.store_with_embedding(%{
          text: "Auth pattern",
          type: "fact",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        })

      assert existing.type == "fact"

      # Single embed call — reused for search + update
      new_vector = deterministic_vector(1, 0)
      expect(EmbedderMock, :embed, fn "Auth pattern is a convention" -> {:ok, new_vector} end)

      entries = [
        %{
          text: "Auth pattern is a convention",
          type: "convention",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        }
      ]

      assert {:ok, %{extracted: 0, updated: 1, skipped: 0}} = Hygiene.store_with_dedup(entries)

      updated = Repo.get(Entry, existing.id)
      assert updated.type == "convention"
    end

    test "entries with different source_files are not considered duplicates" do
      existing_vector = deterministic_vector(1, 0)

      expect(EmbedderMock, :embed, fn "Fact about auth" -> {:ok, existing_vector} end)

      {:ok, _existing} =
        Knowledge.store_with_embedding(%{
          text: "Fact about auth",
          type: "fact",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        })

      # Single embed call — reused for search + store
      new_vector = deterministic_vector(1, 0)
      expect(EmbedderMock, :embed, fn "Fact about auth" -> {:ok, new_vector} end)

      entries = [
        %{
          text: "Fact about auth",
          type: "fact",
          source: "post_task",
          source_file: "lib/different.ex",
          metadata: Jason.encode!(%{})
        }
      ]

      assert {:ok, %{extracted: 1, updated: 0, skipped: 0}} = Hygiene.store_with_dedup(entries)

      all_entries = Repo.all(Entry)
      assert length(all_entries) == 2
    end

    test "entry without source_file is stored as new (no dedup)" do
      expect(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      entries = [
        %{
          text: "General knowledge without file",
          type: "gotcha",
          source: "post_task",
          source_file: nil,
          metadata: Jason.encode!(%{})
        }
      ]

      assert {:ok, %{extracted: 1, updated: 0, skipped: 0}} = Hygiene.store_with_dedup(entries)
    end
  end

  # -- Task 5: Full pipeline --

  describe "run/2 full pipeline" do
    test "success + failure extraction, dedup, and store" do
      success_response =
        Jason.encode!([
          %{"type" => "fact", "text" => "Auth uses JWT tokens", "source_file" => "lib/auth.ex"},
          %{
            "type" => "decision",
            "text" => "Cookie sessions for web",
            "source_file" => "lib/session.ex"
          }
        ])

      failure_response =
        Jason.encode!([
          %{
            "type" => "gotcha",
            "text" => "Session middleware conflicts",
            "source_file" => "lib/plug.ex"
          }
        ])

      # LLM: first call for success, second for failure
      LLMMock
      |> expect(:chat, fn [%{content: prompt}], _opts ->
        if prompt =~ "task execution summary" do
          {:ok, %{content: success_response}}
        else
          {:ok, %{content: failure_response}}
        end
      end)
      |> expect(:chat, fn [%{content: prompt}], _opts ->
        if prompt =~ "task failure" do
          {:ok, %{content: failure_response}}
        else
          {:ok, %{content: success_response}}
        end
      end)

      # Each entry embeds once upfront; vector reused for search + store
      stub(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      context = %{
        success_context: %{
          task_summary: "Added auth middleware",
          modified_files: ["lib/auth.ex", "lib/session.ex"],
          decisions_made: "Cookie sessions"
        },
        failure_log: "Session middleware has conflicting patterns",
        modified_files: ["lib/auth.ex", "lib/session.ex"]
      }

      assert {:ok, %{extracted: extracted, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)

      assert extracted == 3

      entries = Repo.all(Entry)
      assert length(entries) == 3
      assert Enum.all?(entries, fn e -> e.source == "post_task" end)

      types = Enum.map(entries, & &1.type) |> Enum.sort()
      assert "decision" in types
      assert "fact" in types
      assert "gotcha" in types
    end

    test "LLM failure produces warning, not error — fail-open" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        failure_log: "some failure",
        modified_files: []
      }

      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)
    end

    test "handles exception in run/2 gracefully — fail-open" do
      # Pass a context that will cause an exception via bad LLM impl
      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(
                 %{success_context: %{task_summary: "test"}},
                 llm: :not_a_module
               )
    end
  end

  # -- Task 6: Comprehensive coverage --

  describe "comprehensive edge cases" do
    test "LLM returns empty JSON array" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: []
      }

      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)
    end

    test "LLM returns invalid JSON" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "not json at all"}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: []
      }

      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)
    end

    test "LLM returns JSON object instead of array" do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: ~s({"type": "fact", "text": "something"})}}
      end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: []
      }

      assert {:ok, %{extracted: 0, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)
    end

    test "entries with empty or whitespace-only text are filtered out" do
      llm_response =
        Jason.encode!([
          %{"type" => "fact", "text" => "", "source_file" => "lib/foo.ex"},
          %{"type" => "fact", "text" => "   ", "source_file" => "lib/foo.ex"},
          %{"type" => "fact", "text" => "Valid entry", "source_file" => "lib/foo.ex"}
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      # 1 valid entry: search_similar + store_with_embedding = 2 embeds
      stub(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      context = %{
        success_context: %{task_summary: "test"},
        modified_files: ["lib/foo.ex"]
      }

      assert {:ok, %{extracted: 1, updated: 0, skipped: 0}} =
               Hygiene.run(context, llm: LLMMock)
    end

    test "mixed scenario: success entries + failure gotchas + duplicate in single run" do
      # Pre-store an entry that will be a duplicate
      existing_vector = deterministic_vector(1, 0)
      expect(EmbedderMock, :embed, fn "Existing auth convention" -> {:ok, existing_vector} end)

      {:ok, _existing} =
        Knowledge.store_with_embedding(%{
          text: "Existing auth convention",
          type: "convention",
          source: "post_task",
          source_file: "lib/auth.ex",
          metadata: Jason.encode!(%{})
        })

      success_response =
        Jason.encode!([
          %{
            "type" => "convention",
            "text" => "Updated auth convention patterns",
            "source_file" => "lib/auth.ex"
          },
          %{
            "type" => "fact",
            "text" => "New fact about routing",
            "source_file" => "lib/router.ex"
          }
        ])

      failure_response =
        Jason.encode!([
          %{
            "type" => "gotcha",
            "text" => "Watch out for nil sessions",
            "source_file" => "lib/session.ex"
          }
        ])

      LLMMock
      |> expect(:chat, fn _messages, _opts -> {:ok, %{content: success_response}} end)
      |> expect(:chat, fn _messages, _opts -> {:ok, %{content: failure_response}} end)

      # Stub embedder for all dedup + store operations
      stub(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      context = %{
        success_context: %{
          task_summary: "Auth refactor",
          modified_files: ["lib/auth.ex", "lib/router.ex"],
          decisions_made: "Standardized patterns"
        },
        failure_log: "Nil session edge case",
        modified_files: ["lib/auth.ex", "lib/router.ex"]
      }

      assert {:ok, result} = Hygiene.run(context, llm: LLMMock)

      # Convention entry should be updated (duplicate), fact + gotcha stored new
      assert result.updated == 1
      assert result.extracted == 2
      assert result.skipped == 0

      # Should have 3 total entries (1 existing updated + 2 new)
      all_entries = Repo.all(Entry)
      assert length(all_entries) == 3
    end

    test "secret values are filtered from all extracted text" do
      llm_response =
        Jason.encode!([
          %{
            "type" => "gotcha",
            "text" => "API uses key sk_live_abcdefghijklmnopqrstuvwx for Stripe",
            "source_file" => "lib/billing.ex"
          }
        ])

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      stub(EmbedderMock, :embed, fn _text -> {:ok, deterministic_vector(1, 0)} end)

      context = %{
        failure_log: "Stripe key issue",
        modified_files: ["lib/billing.ex"]
      }

      assert {:ok, %{extracted: 1}} = Hygiene.run(context, llm: LLMMock)

      entry = Repo.one(Entry)
      assert entry.text =~ "[STRIPE_SECRET_KEY]"
      refute entry.text =~ "sk_live_"
    end
  end

  # -- Helpers --

  defp deterministic_vector(primary, secondary) do
    half = div(768, 2)
    List.duplicate(primary, half) ++ List.duplicate(secondary, half)
  end
end
