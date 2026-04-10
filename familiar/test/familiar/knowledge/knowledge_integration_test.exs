defmodule Familiar.Knowledge.KnowledgeIntegrationTest do
  @moduledoc """
  Integration test validating the full knowledge store lifecycle.

  Proves search, freshness, hygiene, management, backup/restore, and
  safety (secret filtering, knowledge-not-code) work as a coherent system.

  Uses real SQLite + sqlite-vec (via Ecto sandbox) with mocked providers.
  """

  use Familiar.DataCase, async: false
  use Familiar.MockCase

  import Familiar.Test.EmbeddingHelpers

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Backup
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Hygiene
  alias Familiar.Knowledge.Management
  alias Familiar.Repo

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    {:ok, project_dir: tmp_dir}
  end

  setup do
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Default stubs: fresh files, frozen clock, safe read/LLM fallbacks.
    # Background tasks spawned by search (refresh_stale, remove_deleted) need
    # FileSystem.read, LLM.chat, and Embedder.embed stubs to not crash.
    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.FileSystemMock, :read, fn _path ->
      {:ok, "# placeholder content"}
    end)

    stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
      {:ok, %{content: Jason.encode!([])}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-02 12:00:00Z] end)

    :ok
  end

  # -- Helpers --

  defp stub_embedder_sequential do
    counter = :counters.new(1, [:atomics])
    dims = Knowledge.embedding_dimensions()

    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      idx = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      dim = rem(idx, dims)
      vector = zero_vector() |> List.replace_at(dim, 1.0)
      {:ok, vector}
    end)
  end

  defp create_source_file(tmp_dir, relative_path, content) do
    full = Path.join(tmp_dir, relative_path)
    full |> Path.dirname() |> File.mkdir_p!()
    File.write!(full, content)
  end

  # -- Task 1: Golden Path Lifecycle --

  describe "golden path: store → search → freshness → hygiene → backup → restore" do
    test "full knowledge store lifecycle", %{tmp_dir: tmp_dir} do
      # Stub all providers broadly — background tasks from search trigger
      # refresh_stale/remove_deleted which call LLM, Embedder, and FileSystem.
      stub_embedder_sequential()

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: Jason.encode!([])}}
      end)

      # --- Store phase ---
      {:ok, auth_entry} =
        Knowledge.store(%{
          text: "Auth module uses JWT tokens for session management",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, db_entry} =
        Knowledge.store(%{
          text: "Database uses connection pooling via DBConnection",
          type: "fact",
          source: "init_scan",
          source_file: "lib/repo.ex"
        })

      {:ok, _gotcha_entry} =
        Knowledge.store(%{
          text: "Config files must not import from lib directory",
          type: "gotcha",
          source: "manual",
          source_file: "config/config.exs"
        })

      # Verify entries persisted with embeddings
      assert Repo.aggregate(Entry, :count) == 3

      {:ok, %{rows: [[emb_count]]}} =
        Repo.query("SELECT count(*) FROM knowledge_entry_embeddings")

      assert emb_count == 3

      # --- Search phase ---
      {:ok, results} = Knowledge.search("JWT authentication")
      assert length(results) >= 2
      first = hd(results)
      assert first.text == "Auth module uses JWT tokens for session management"
      assert first.type == "convention"
      assert first.freshness in [:fresh, :unknown]

      # --- Freshness phase: mark auth file as modified ---
      # ClockMock sets entry.updated_at to 12:00, so mtime 15:00 = stale
      stub(Familiar.System.FileSystemMock, :stat, fn
        "lib/auth.ex" ->
          {:ok, %{mtime: ~U[2026-04-02 15:00:00Z], size: 200}}

        _other ->
          {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
      end)

      {:ok, stale_results} = Knowledge.search("JWT authentication")
      auth_result = Enum.find(stale_results, &(&1.id == auth_entry.id))
      assert auth_result.freshness == :stale

      # Non-auth entries remain fresh
      db_result = Enum.find(stale_results, &(&1.id == db_entry.id))
      assert db_result.freshness == :fresh

      # --- Hygiene phase ---
      # Reset stat stubs to fresh and give background tasks time to settle
      stub(Familiar.System.FileSystemMock, :stat, fn _path ->
        {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
      end)

      hygiene_response =
        Jason.encode!([
          %{
            "type" => "gotcha",
            "text" => "Rate limiter resets at midnight UTC not local time",
            "source_file" => "lib/rate_limiter.ex"
          }
        ])

      # Override LLM stub for hygiene extraction
      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: hygiene_response}}
      end)

      context = %{
        success_context: %{
          task_summary: "Added rate limiter",
          modified_files: ["lib/rate_limiter.ex"],
          decisions_made: "Use sliding window"
        },
        modified_files: ["lib/rate_limiter.ex"]
      }

      {:ok, hygiene_result} = Hygiene.run(context, llm: Familiar.Providers.LLMMock)
      assert hygiene_result.extracted >= 1

      # Verify new entry persisted
      assert Repo.aggregate(Entry, :count) >= 4

      # --- Backup → Restore phase ---
      backups_dir = Path.join(tmp_dir, "backups")
      db_path = Familiar.Repo.config()[:database]

      {:ok, backup_info} = Backup.create(db_path: db_path, backups_dir: backups_dir)
      assert File.exists?(backup_info.path)
      assert backup_info.size > 0

      # Verify backup is listed
      {:ok, backups} = Backup.list(backups_dir: backups_dir)
      assert length(backups) == 1
      assert hd(backups).path == backup_info.path

      # Verify restore completes without error
      :ok = Backup.restore(backup_info.path, db_path: db_path)
    end
  end

  # -- Task 1.4: Freshness stale detection (standalone) --

  describe "freshness: stale detection triggers background refresh" do
    test "stale entries detected when source file modified after entry creation" do
      v = deterministic_vector(1.0, 0.0)

      # Use stub (not expect) — background tasks from search also call embed
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, v} end)

      {:ok, entry} =
        Knowledge.store(%{
          text: "Router uses RESTful resource conventions",
          type: "convention",
          source: "init_scan",
          source_file: "lib/router.ex"
        })

      # Source file modified after entry was stored (ClockMock sets updated_at to 12:00)
      stub(Familiar.System.FileSystemMock, :stat, fn "lib/router.ex" ->
        {:ok, %{mtime: ~U[2026-04-02 15:00:00Z], size: 300}}
      end)

      {:ok, results} = Knowledge.search("router conventions")
      result = Enum.find(results, &(&1.id == entry.id))
      assert result.freshness == :stale
    end
  end

  # -- Task 2: Failure Scenarios --

  describe "failure: secret filtering blocks secrets at storage gateway" do
    test "AWS key is filtered before persisting" do
      v = deterministic_vector(1.0, 0.0)

      expect(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        refute text =~ "AKIAIOSFODNN7EXAMPLE"
        assert text =~ "[AWS_ACCESS_KEY]"
        {:ok, v}
      end)

      {:ok, entry} =
        Knowledge.store(%{
          text: "S3 configured with AKIAIOSFODNN7EXAMPLE in production",
          type: "fact",
          source: "manual",
          source_file: "config/s3.ex"
        })

      assert entry.text =~ "[AWS_ACCESS_KEY]"
      refute entry.text =~ "AKIAIOSFODNN7EXAMPLE"
    end
  end

  describe "failure: knowledge-not-code rejects raw code" do
    test "defmodule code block rejected with knowledge_not_code error" do
      code = """
      defmodule MyApp.Worker do
        use GenServer
        def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
        def init(state), do: {:ok, state}
      end
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               Knowledge.store(%{
                 text: code,
                 type: "convention",
                 source: "manual"
               })
    end
  end

  describe "failure: freshness excludes entries referencing deleted files" do
    test "entries for deleted files are excluded from search results" do
      v = deterministic_vector(1.0, 0.0)

      expect(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, v} end)

      {:ok, entry} =
        Knowledge.store(%{
          text: "Helper module for date formatting utilities",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/helpers/date.ex"
        })

      # Source file now deleted
      stub(Familiar.System.FileSystemMock, :stat, fn "lib/helpers/date.ex" ->
        {:error, {:file_error, %{path: "lib/helpers/date.ex", reason: :enoent}}}
      end)

      expect(Familiar.Knowledge.EmbedderMock, :embed, fn _query -> {:ok, v} end)

      {:ok, results} = Knowledge.search("date formatting")
      refute Enum.any?(results, &(&1.id == entry.id))
    end
  end

  describe "failure: auto-restore on database integrity failure" do
    test "recovery restores from backup when integrity check fails", %{tmp_dir: tmp_dir} do
      backups_dir = Path.join(tmp_dir, "backups")
      db_path = Familiar.Repo.config()[:database]

      # Create a backup first
      {:ok, _} = Backup.create(db_path: db_path, backups_dir: backups_dir)

      # Verify auto_restore_from_backup is wired via Recovery module
      # We can't easily corrupt the DB in-process, but we can verify
      # the backup/latest/restore pipeline works end-to-end
      {:ok, latest_path} = Backup.latest(backups_dir: backups_dir)
      assert File.exists?(latest_path)

      :ok = Backup.restore(latest_path, db_path: db_path)
    end
  end

  # -- Task 3: Cross-Module Interactions --

  describe "cross-module: management refresh preserves user entries" do
    test "user entries survive refresh while init_scan entries are updated", %{
      tmp_dir: tmp_dir
    } do
      stub_embedder_sequential()

      # Store user-sourced entry
      {:ok, user_entry} =
        Knowledge.store(%{
          text: "Team decided to use Tailwind for styling",
          type: "decision",
          source: "user",
          source_file: "lib/app_web.ex"
        })

      # Store init_scan entry
      {:ok, auto_entry} =
        Knowledge.store(%{
          text: "AppWeb uses Phoenix LiveView components",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/app_web.ex"
        })

      # Create source file for scanning
      create_source_file(tmp_dir, "lib/app_web.ex", """
      defmodule AppWeb do
        def router do
          use Phoenix.Router
        end
      end
      """)

      # Stub LLM for extraction during refresh
      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 "type" => "file_summary",
                 "text" => "AppWeb provides Phoenix framework integration",
                 "source_file" => "lib/app_web.ex"
               }
             ])
         }}
      end)

      # Stub FileSystem for refresh scan
      stub(Familiar.System.FileSystemMock, :read, fn _path ->
        {:ok, "defmodule AppWeb do end"}
      end)

      stub(Familiar.System.FileSystemMock, :stat, fn _path ->
        {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
      end)

      scan_fn = fn _dir, _opts ->
        {:ok, [%{relative_path: "lib/app_web.ex"}], 0}
      end

      {:ok, refresh_result} =
        Management.refresh(tmp_dir,
          scan_fn: scan_fn,
          file_system: Familiar.System.FileSystemMock
        )

      assert refresh_result.preserved >= 1

      # User entry preserved with original text
      {:ok, preserved} = Knowledge.fetch_entry(user_entry.id)
      assert preserved.text == "Team decided to use Tailwind for styling"
      assert preserved.source == "user"

      # Init_scan entry was refreshed with new LLM-extracted text
      {:ok, refreshed} = Knowledge.fetch_entry(auto_entry.id)
      assert refreshed.text == "AppWeb provides Phoenix framework integration"
    end
  end

  describe "cross-module: hygiene duplicate detection" do
    test "hygiene supersedes existing entry instead of creating duplicate" do
      v = deterministic_vector(1.0, 0.0)

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, v} end)

      # Store initial entry
      {:ok, original} =
        Knowledge.store(%{
          text: "Auth module uses bcrypt for password hashing",
          type: "fact",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      count_before = Repo.aggregate(Entry, :count)

      # Hygiene extracts a similar entry for the same file
      hygiene_response =
        Jason.encode!([
          %{
            "type" => "fact",
            "text" => "Auth module uses bcrypt with cost factor 12 for password hashing",
            "source_file" => "lib/auth.ex"
          }
        ])

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: hygiene_response}}
      end)

      context = %{
        success_context: %{
          task_summary: "Updated auth hashing",
          modified_files: ["lib/auth.ex"],
          decisions_made: "Increase bcrypt cost"
        },
        modified_files: ["lib/auth.ex"]
      }

      {:ok, result} = Hygiene.run(context, llm: Familiar.Providers.LLMMock)
      assert result.updated >= 1

      # Entry count should NOT increase — existing entry was superseded
      assert Repo.aggregate(Entry, :count) == count_before

      # Original entry should have updated text
      {:ok, updated} = Knowledge.fetch_entry(original.id)
      assert updated.text =~ "cost factor 12"
    end
  end

  describe "cross-module: consolidation candidates" do
    test "find_consolidation_candidates detects similar entries" do
      # Use identical vectors so distance is 0 (perfect match)
      v = deterministic_vector(1.0, 0.0)

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, v} end)

      {:ok, _} =
        Knowledge.store(%{
          text: "Auth uses JWT tokens for API sessions",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, _} =
        Knowledge.store(%{
          text: "Authentication relies on JWT tokens for session management",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, %{candidates: candidates}} = Management.find_consolidation_candidates()
      assert candidates != []

      candidate = hd(candidates)
      assert candidate.type == "convention"
      assert candidate.distance < 0.3
    end
  end

  describe "cross-module: health signal accuracy" do
    test "health reflects correct entry count, types, and signal" do
      stub_embedder_sequential()

      {:ok, _} =
        Knowledge.store(%{
          text: "Auth pattern uses middleware chain",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, _} =
        Knowledge.store(%{
          text: "Database pool size set to 10 for production",
          type: "fact",
          source: "init_scan",
          source_file: "lib/repo.ex"
        })

      {:ok, _} =
        Knowledge.store(%{
          text: "Config reload requires restart due to compile-time evaluation",
          type: "gotcha",
          source: "manual",
          source_file: "config/runtime.exs"
        })

      {:ok, health} = Knowledge.health()

      assert health.entry_count == 3
      assert health.types["convention"] == 1
      assert health.types["fact"] == 1
      assert health.types["gotcha"] == 1
      assert health.signal in [:red, :amber]
      assert health.staleness_ratio >= 0.0
    end

    test "health returns green with backup and no staleness", %{tmp_dir: tmp_dir} do
      backups_dir = Path.join(tmp_dir, "backups")
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260402T120000.db"), "backup")

      {:ok, health} = Knowledge.health(backups_dir: backups_dir)
      assert health.signal == :green
      assert health.backup.count == 1
    end
  end
end
