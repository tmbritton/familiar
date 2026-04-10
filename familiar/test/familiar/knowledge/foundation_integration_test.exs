defmodule Familiar.Knowledge.FoundationIntegrationTest do
  @moduledoc """
  Integration test validating the full init pipeline end-to-end.

  Uses real SQLite + sqlite-vec (via Ecto sandbox) with mocked LLM/Embedder.
  Tests the golden path: scan → classify → extract → embed → store → retrieve.
  """

  use Familiar.DataCase, async: false
  use Familiar.MockCase

  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.InitScanner
  alias Familiar.Repo

  @moduletag :tmp_dir

  @fs Familiar.System.LocalFileSystem

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    {:ok, project_dir: tmp_dir}
  end

  # -- Fixture Helpers --

  defp create_file(base, relative_path, content) do
    full_path = Path.join(base, relative_path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, content)
  end

  defp generate_fixture(tmp_dir, file_count \\ 110) do
    source_count = div(file_count * 6, 10)
    test_count = div(file_count * 2, 10)
    doc_count = div(file_count, 10)
    config_count = file_count - source_count - test_count - doc_count

    # Source files with varied patterns
    for i <- 1..source_count do
      content = source_content(i)
      create_file(tmp_dir, "lib/app/mod#{i}.ex", content)
    end

    # Test files
    for i <- 1..test_count do
      create_file(tmp_dir, "test/app/mod#{i}_test.exs", """
      defmodule App.Mod#{i}Test do
        use ExUnit.Case
        test "mod#{i} works" do
          assert App.Mod#{i}.run() == :ok
        end
      end
      """)
    end

    # Doc files
    for i <- 1..doc_count do
      create_file(tmp_dir, "docs/guide_#{i}.md", "# Guide #{i}\n\nDocumentation for module #{i}.")
    end

    # Config files
    create_file(tmp_dir, "mix.exs", """
    defmodule App.MixProject do
      use Mix.Project
      def project, do: [app: :app, version: "0.1.0", elixir: "~> 1.14"]
      def application, do: [extra_applications: [:logger]]
    end
    """)

    create_file(tmp_dir, "config/config.exs", """
    import Config
    config :app, env: config_env()
    """)

    for i <- 1..max(config_count - 2, 1) do
      create_file(tmp_dir, "config/extra_#{i}.exs", "import Config\n")
    end

    # Skip targets — must be excluded
    create_file(tmp_dir, "_build/dev/lib/app.beam", "binary")
    create_file(tmp_dir, "deps/phoenix/mix.exs", "defmodule Phoenix.MixProject do end")
    create_file(tmp_dir, ".git/config", "[core]\nbare = false")

    :ok
  end

  defp source_content(i) do
    case rem(i, 5) do
      0 ->
        """
        defmodule App.Worker#{i} do
          use GenServer
          def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          def init(state), do: {:ok, state}
          def handle_call(:status, _from, state), do: {:reply, :ok, state}
        end
        """

      1 ->
        """
        defmodule App.Schema#{i} do
          use Ecto.Schema
          schema "items_#{i}" do
            field :name, :string
            field :value, :integer
            timestamps()
          end
        end
        """

      2 ->
        """
        defmodule App.Context#{i} do
          @moduledoc "Context module #{i} for business logic."
          def list_items, do: []
          def get_item(id), do: {:ok, %{id: id}}
          def create_item(attrs), do: {:ok, attrs}
        end
        """

      3 ->
        """
        defmodule App.Controller#{i} do
          @moduledoc "Controller #{i} handling HTTP requests."
          def index(conn, _params), do: send_resp(conn, 200, "ok")
          def show(conn, %{"id" => id}), do: send_resp(conn, 200, id)
        end
        """

      4 ->
        """
        defmodule App.Supervisor#{i} do
          use Supervisor
          def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
          def init(_opts) do
            children = []
            Supervisor.init(children, strategy: :one_for_one)
          end
        end
        """
    end
  end

  defp stub_llm_extraction do
    Mox.stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      prompt = hd(messages).content

      if prompt =~ "conventions" do
        llm_convention_response()
      else
        llm_extraction_response(prompt)
      end
    end)
  end

  defp llm_convention_response do
    {:ok,
     %{
       content:
         Jason.encode!([
           %{
             "type" => "convention",
             "text" => "LLM-discovered convention: modules follow consistent naming",
             "evidence_count" => 5,
             "evidence_total" => 10
           }
         ])
     }}
  end

  defp llm_extraction_response(prompt) do
    source =
      case Regex.run(~r/File: (.+)\n/, prompt, capture: :all_but_first) do
        [file] -> file
        _ -> "unknown"
      end

    {:ok,
     %{
       content:
         Jason.encode!([
           %{
             "type" => "file_summary",
             "text" => "Module at #{source} provides application functionality",
             "source_file" => source
           }
         ])
     }}
  end

  defp stub_shell_commands do
    Mox.stub(Familiar.System.ShellMock, :cmd, fn _cmd, _args, _opts ->
      {:ok, %{output: "ok", exit_code: 0}}
    end)
  end

  defp stub_embedder_deterministic do
    counter = :counters.new(1, [:atomics])
    dims = Knowledge.embedding_dimensions()

    Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      idx = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      dim = rem(idx, dims)
      vector = zero_vector() |> List.replace_at(dim, 1.0)
      {:ok, vector}
    end)
  end

  # -- Task 2: Golden Path Integration Test --

  describe "golden path: scan → classify → extract → embed → store → retrieve" do
    test "full init pipeline stores entries in real SQLite and enables vector search", %{
      project_dir: tmp_dir
    } do
      generate_fixture(tmp_dir)
      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned >= 100
      assert summary.entries_created >= 1
      assert summary.conventions_discovered >= 1

      # Verify entries persisted in real SQLite
      entries = Repo.all(Entry)
      assert entries != []

      types = entries |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()
      assert "file_summary" in types

      sources = entries |> Enum.map(& &1.source) |> Enum.uniq()
      assert "init_scan" in sources

      # Verify embeddings persisted in sqlite-vec table
      {:ok, %{rows: [[embedding_count]]}} =
        Repo.query("SELECT count(*) FROM knowledge_entry_embeddings")

      assert embedding_count > 0
      assert embedding_count == length(entries)

      # Verify all entries have required fields
      for entry <- entries do
        assert is_binary(entry.text) and entry.text != ""
        assert entry.type in ~w(convention file_summary architecture relationship decision)
        assert entry.source in ~w(init_scan post_task manual)
        assert entry.inserted_at != nil
        assert entry.updated_at != nil
      end

      # Verify vector search works end-to-end
      stub_embedder_deterministic()
      {:ok, results} = Knowledge.search_similar("application functionality")

      assert results != []

      # Results have entry and distance
      for result <- results do
        assert %{entry: %Entry{}, distance: distance} = result
        assert is_number(distance)
        assert distance >= 0.0
      end

      # Verify ordering by ascending distance
      distances = Enum.map(results, & &1.distance)
      assert distances == Enum.sort(distances)
    end
  end

  # -- Task 3: Scale and Prioritization Test --

  describe "scale and prioritization" do
    test "prioritizes source files over docs when above large_project_threshold", %{
      project_dir: tmp_dir
    } do
      # Generate 510 files to exceed @large_project_threshold of 500
      for i <- 1..310 do
        create_file(tmp_dir, "lib/app/mod#{i}.ex", """
        defmodule App.Mod#{i} do
          def run, do: :ok
        end
        """)
      end

      for i <- 1..200 do
        create_file(tmp_dir, "docs/page#{i}.md", "# Page #{i}\n\nContent here.")
      end

      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      result =
        InitScanner.run(tmp_dir,
          max_files: 200,
          progress_fn: fn _msg -> :ok end,
          file_system: @fs
        )

      assert {:ok, summary} = result

      # max_files respected and NFR14 minimum scale met
      assert summary.files_scanned >= 100
      assert summary.files_scanned <= 200

      # Deferred count is positive (more files than max_files)
      assert summary.deferred > 0
    end

    test "scan_files prioritizes .ex over .md in selected files", %{project_dir: tmp_dir} do
      for i <- 1..310 do
        create_file(tmp_dir, "lib/app/mod#{i}.ex", "defmodule App.Mod#{i} do end")
      end

      for i <- 1..200 do
        create_file(tmp_dir, "docs/page#{i}.md", "# Page #{i}")
      end

      {:ok, files, deferred} =
        InitScanner.scan_files(tmp_dir, max_files: 200, file_system: @fs)

      assert length(files) <= 200
      assert deferred > 0

      source_count = Enum.count(files, &String.ends_with?(&1.relative_path, ".ex"))
      doc_count = Enum.count(files, &String.ends_with?(&1.relative_path, ".md"))
      assert source_count > doc_count
    end
  end

  # -- Task 4: Error Path Tests --

  describe "error paths" do
    test "run_with_cleanup cleans up .familiar/ on error return", %{project_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          File.mkdir_p!(familiar_dir)
          File.write!(Path.join(familiar_dir, "test.txt"), "data")
          {:error, {:init_failed, %{reason: "test failure"}}}
        end)

      assert {:error, {:init_failed, _}} = result
      refute File.dir?(familiar_dir)
    end

    test "run_with_cleanup cleans up .familiar/ on exception", %{project_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          File.mkdir_p!(familiar_dir)
          raise "boom"
        end)

      assert {:error, {:init_failed, %{reason: reason}}} = result
      assert reason =~ "boom"
      refute File.dir?(familiar_dir)
    end

    test "pipeline continues when LLM is unavailable, with extraction warnings", %{
      project_dir: tmp_dir
    } do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do\n  def hello, do: :world\nend")

      create_file(
        tmp_dir,
        "lib/app/server.ex",
        "defmodule App.Server do\n  def run, do: :ok\nend"
      )

      # LLM fails for all calls
      Mox.stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{reason: :timeout}}}
      end)

      # Structural conventions still get embedded
      stub_embedder_deterministic()
      stub_shell_commands()

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned >= 1
      assert summary.extraction_warnings =~ "could not be analyzed"
      # Structural conventions discovered even without LLM
      assert summary.conventions_discovered >= 1
    end

    test "corrupt/unreadable files are skipped gracefully", %{project_dir: tmp_dir} do
      create_file(tmp_dir, "lib/good.ex", "defmodule Good do\n  def run, do: :ok\nend")
      create_file(tmp_dir, "lib/also_good.ex", "defmodule AlsoGood do\n  def run, do: :ok\nend")
      create_file(tmp_dir, "lib/bad.ex", "defmodule Bad do end")
      File.chmod!(Path.join(tmp_dir, "lib/bad.ex"), 0o000)

      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      # At least the good files were processed
      assert summary.files_scanned >= 2
    after
      bad_path = Path.join(tmp_dir, "lib/bad.ex")
      if File.exists?(bad_path), do: File.chmod!(bad_path, 0o644)
    end

    test "embedding failure rolls back entry via compensating delete", %{project_dir: tmp_dir} do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do\n  def hello, do: :world\nend")

      # LLM succeeds
      Mox.stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        prompt = hd(messages).content

        if prompt =~ "conventions" do
          {:ok, %{content: Jason.encode!([])}}
        else
          {:ok,
           %{
             content:
               Jason.encode!([
                 %{
                   "type" => "file_summary",
                   "text" => "Test module",
                   "source_file" => "lib/app.ex"
                 }
               ])
           }}
        end
      end)

      # Embedder always fails
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{reason: :connection_refused}}}
      end)

      stub_shell_commands()

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      # Entries that failed embedding should have been rolled back
      assert summary.entries_created == 0

      # Verify no orphan entries in DB (compensating delete worked)
      entries = Repo.all(Entry)
      assert entries == []
    end
  end

  # -- Task 5: Retrieval Verification Tests --

  describe "retrieval verification" do
    test "search_similar returns entries ordered by distance with distinct vectors" do
      # Store two entries with known distinct vectors
      auth_vector = zero_vector() |> List.replace_at(0, 1.0)
      db_vector = zero_vector() |> List.replace_at(1, 1.0)

      # Stub embedder to return specific vectors per content
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        cond do
          text =~ "authentication" -> {:ok, auth_vector}
          text =~ "database" -> {:ok, db_vector}
          true -> {:ok, auth_vector}
        end
      end)

      # Store auth entry
      {:ok, auth_entry} =
        Knowledge.store_with_embedding(%{
          text: "Handles user authentication and session management",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/auth.ex",
          metadata: "{}"
        })

      # Store database entry
      {:ok, db_entry} =
        Knowledge.store_with_embedding(%{
          text: "Provides database connection pooling and query helpers",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/db.ex",
          metadata: "{}"
        })

      # Search with vector close to auth (should return auth first)
      query_vector =
        zero_vector()
        |> List.replace_at(0, 0.9)
        |> List.replace_at(1, 0.1)

      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, query_vector}
      end)

      {:ok, results} = Knowledge.search_similar("authentication login")

      assert length(results) == 2
      [first, second] = results

      assert first.entry.id == auth_entry.id
      assert first.entry.text =~ "authentication"
      assert second.entry.id == db_entry.id
      assert second.entry.text =~ "database"
      assert first.distance <= second.distance
    end

    test "dimension enforcement rejects wrong dimension vectors" do
      expected = Knowledge.embedding_dimensions()
      wrong = if expected == 512, do: 256, else: 512

      # Stub embedder to return wrong-dimension vector
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, List.duplicate(0.1, wrong)}
      end)

      result =
        Knowledge.store_with_embedding(%{
          text: "Test entry with wrong dimensions",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/test.ex",
          metadata: "{}"
        })

      assert {:error,
              {:storage_failed, %{reason: :dimension_mismatch, expected: ^expected, got: ^wrong}}} =
               result

      # Verify no orphan entry left behind
      entries = Repo.all(Entry)
      assert entries == []
    end

    test "entry fields are populated correctly after store_with_embedding" do
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, List.duplicate(0.1, Knowledge.embedding_dimensions())}
      end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Handler files follow the pattern handler/{resource}.go",
          type: "convention",
          source: "init_scan",
          source_file: "handler/song.go",
          metadata: Jason.encode!(%{evidence_count: 3})
        })

      assert entry.text == "Handler files follow the pattern handler/{resource}.go"
      assert entry.type == "convention"
      assert entry.source == "init_scan"
      assert entry.source_file == "handler/song.go"
      assert entry.metadata == Jason.encode!(%{evidence_count: 3})
      assert %DateTime{} = entry.inserted_at
      assert %DateTime{} = entry.updated_at
    end

    test "search_similar respects limit option" do
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, List.duplicate(0.1, Knowledge.embedding_dimensions())}
      end)

      for i <- 1..5 do
        {:ok, _} =
          Knowledge.store_with_embedding(%{
            text: "Entry number #{i} for limit testing",
            type: "file_summary",
            source: "init_scan",
            source_file: "lib/mod#{i}.ex",
            metadata: "{}"
          })
      end

      {:ok, all_results} = Knowledge.search_similar("limit testing", limit: 10)
      assert length(all_results) == 5

      {:ok, limited} = Knowledge.search_similar("limit testing", limit: 2)
      assert length(limited) == 2
    end
  end

  # -- Deferred Fix Tests --

  describe "edge cases" do
    test "scan_files handles non-existent project directory gracefully" do
      result =
        InitScanner.scan_files("/tmp/nonexistent_#{System.unique_integer([:positive])}",
          file_system: @fs
        )

      assert {:ok, [], 0} = result
    end

    test "second init run creates additional entries (no dedup)", %{project_dir: tmp_dir} do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do\n  def hello, do: :world\nend")

      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      {:ok, first_summary} =
        InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert first_summary.entries_created > 0
      entries_after_first = Repo.aggregate(Entry, :count)

      # Run again — same files, creates more entries (no dedup in init_scanner)
      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      {:ok, second_summary} =
        InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert second_summary.entries_created > 0
      entries_after_second = Repo.aggregate(Entry, :count)

      # Documents current behavior: entries accumulate, no deduplication
      assert entries_after_second > entries_after_first
    end

    test "pipeline handles file with corrupt binary content", %{project_dir: tmp_dir} do
      # Valid file
      create_file(tmp_dir, "lib/good.ex", "defmodule Good do\n  def run, do: :ok\nend")
      # Corrupt binary content (not valid UTF-8)
      corrupt_path = Path.join(tmp_dir, "lib/corrupt.ex")
      corrupt_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(corrupt_path, <<0xFF, 0xFE, 0x00, 0x01, 0xFF>>)

      stub_llm_extraction()
      stub_embedder_deterministic()
      stub_shell_commands()

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      # Pipeline should complete — corrupt file processed (LLM handles the content)
      assert {:ok, summary} = result
      assert summary.files_scanned >= 1
    end
  end
end
