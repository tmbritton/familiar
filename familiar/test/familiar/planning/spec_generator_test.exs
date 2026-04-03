defmodule Familiar.Planning.SpecGeneratorTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning.Message
  alias Familiar.Planning.Session
  alias Familiar.Planning.Spec
  alias Familiar.Planning.SpecGenerator

  @spec_markdown """
  # Add User Accounts

  ## Assumptions

  Users table has email and hashed_password columns in `db/migrations/001_init.sql`
  Auth middleware validates session tokens in `lib/auth.ex`
  Rate limiting for login attempts is needed

  ## Conventions Applied

  Following existing pattern: handler/song.go → handler/user.go

  ## Implementation Plan

  1. Create user schema
  2. Add authentication handler
  """

  defmodule StubFileSystem do
    @moduledoc false
    def read("db/migrations/001_init.sql"), do: {:ok, "CREATE TABLE users (email TEXT);"}
    def read(_path), do: {:error, {:file_error, %{reason: :enoent}}}
    def write(_path, _content), do: :ok
    def stat("db/migrations/001_init.sql"), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 100}}
    def stat("lib/auth.ex"), do: {:error, {:file_error, %{reason: :enoent}}}
    def stat(_path), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 50}}
  end

  defmodule StubKnowledge do
    @moduledoc false
    def search(_query) do
      {:ok, [%{id: 1, text: "Auth uses JWT tokens", source_file: "lib/auth.ex", type: "convention"}]}
    end
  end

  defmodule StubTrail do
    @moduledoc false
    def broadcast(_session_id, _event), do: :ok
  end

  setup do
    spec_text = @spec_markdown

    {:ok, session} =
      %Session{}
      |> Session.changeset(%{description: "add user accounts", context: "Project uses Phoenix."})
      |> Repo.insert()

    %Message{}
    |> Message.changeset(%{session_id: session.id, role: "user", content: "add user accounts"})
    |> Repo.insert!()

    %{session: session, spec_text: spec_text}
  end

  defp stub_providers_with_tools(spec_text) do
    # Returns a module-like map with a chat function
    # We use a closure-based approach instead of nested defmodule
    fn messages, _opts ->
      has_tool_result = Enum.any?(messages, &(&1[:role] == "tool"))

      if has_tool_result do
        {:ok, %{content: spec_text}}
      else
        {:ok, %{
          content: "Let me verify the schema.",
          tool_calls: [
            %{id: "tc_1", name: "file_read", arguments: %{"path" => "db/migrations/001_init.sql"}},
            %{id: "tc_2", name: "knowledge_search", arguments: %{"query" => "auth patterns"}}
          ]
        }}
      end
    end
  end

  defp stub_providers_no_tools(spec_text) do
    fn _messages, _opts ->
      {:ok, %{content: spec_text}}
    end
  end

  defp stub_providers_error do
    fn _messages, _opts ->
      {:error, {:provider_unavailable, %{}}}
    end
  end

  defp wrap_fn(fun) do
    # Wrap a function as a module-like struct the SpecGenerator can call
    %{chat: fun}
  end

  describe "generate/2" do
    test "generates spec with tool dispatch and verification", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_with_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert result.spec.title == "Add User Accounts"
      assert result.spec.status == "draft"
      assert result.spec.session_id == session.id
      assert result.file_path =~ ".familiar/specs/"
      assert is_list(result.tool_call_log)
    end

    test "dispatches file_read tool calls", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_with_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      file_reads = Enum.filter(result.tool_call_log, &(&1.type == "file_read"))
      assert [%{path: "db/migrations/001_init.sql"} | _] = file_reads
    end

    test "dispatches knowledge_search tool calls", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_with_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      context_queries = Enum.filter(result.tool_call_log, &(&1.type == "context_query"))
      assert [_ | _] = context_queries
    end

    test "generates spec without tool calls", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert result.spec.title == "Add User Accounts"
      assert result.tool_call_log == []
    end

    test "persists spec in database", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, _result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert [spec] = Repo.all(Spec)
      assert spec.session_id == session.id
    end

    test "marks session as completed", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, _result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      updated = Repo.get!(Session, session.id)
      assert updated.status == "completed"
    end

    test "returns error when LLM fails", %{session: session} do
      providers = wrap_fn(stub_providers_error())

      {:error, {type, _}} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert type == :llm_failed
    end

    test "spec body includes metadata line", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert result.spec.body =~ "Generated"
      assert result.spec.body =~ "verified"
    end

    test "spec body includes verification marks", %{session: session, spec_text: spec_text} do
      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      # With no tool calls, all claims should be ⚠
      assert result.spec.body =~ "⚠"
    end

    test "freshness downgrades verified claims for deleted files", %{session: session} do
      # Spec references lib/auth.ex which StubFileSystem.stat returns :enoent for
      spec_with_auth = """
      # Auth Feature

      ## Assumptions

      Auth middleware validates tokens in `lib/auth.ex`
      DB schema has users table in `db/migrations/001_init.sql`

      ## Implementation Plan

      1. Add handler
      """

      providers = wrap_fn(fn messages, _opts ->
        has_tool_result = Enum.any?(messages, &(&1[:role] == "tool"))

        if has_tool_result do
          {:ok, %{content: spec_with_auth}}
        else
          {:ok, %{
            content: "Checking files.",
            tool_calls: [
              %{id: "tc_1", name: "file_read", arguments: %{"path" => "lib/auth.ex"}},
              %{id: "tc_2", name: "file_read", arguments: %{"path" => "db/migrations/001_init.sql"}}
            ]
          }}
        end
      end)

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      # lib/auth.ex is :enoent in StubFileSystem.stat → should be downgraded to ⚠
      assert result.spec.body =~ "⚠"
      # db/migrations/001_init.sql is :ok in StubFileSystem.stat → should stay verified ✓
      assert result.spec.body =~ "✓"
      # Metadata should reflect the freshness downgrade
      assert result.metadata.unverified_count >= 1
      assert result.metadata.verified_count >= 1
    end

    test "rejects spec generation for completed session", %{session: session} do
      # Complete the session and reload to get the updated struct
      completed =
        session
        |> Session.changeset(%{status: "completed"})
        |> Repo.update!()

      providers = wrap_fn(fn _msgs, _opts -> {:ok, %{content: "spec"}} end)

      {:error, {type, _}} =
        SpecGenerator.generate(completed,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert type == :session_not_specifiable
    end

    test "returns error when tool loop is exhausted" do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "infinite tools", context: "ctx"})
        |> Repo.insert()

      %Message{}
      |> Message.changeset(%{session_id: session.id, role: "user", content: "test"})
      |> Repo.insert!()

      # Provider always returns tool calls — will exhaust the loop
      providers = wrap_fn(fn _msgs, _opts ->
        {:ok, %{
          content: "still working",
          tool_calls: [%{id: "tc", name: "file_read", arguments: %{"path" => "lib/app.ex"}}]
        }}
      end)

      {:error, {type, _}} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      assert type == :tool_loop_exhausted
    end

    test "validates file paths — rejects traversal attempts", %{session: session} do
      providers = wrap_fn(fn messages, _opts ->
        has_tool_result = Enum.any?(messages, &(&1[:role] == "tool"))

        if has_tool_result do
          {:ok, %{content: "# Spec\n\n## Assumptions\n\nNone\n\n## Implementation Plan\n\n1. Do it"}}
        else
          {:ok, %{
            content: "checking",
            tool_calls: [%{id: "tc", name: "file_read", arguments: %{"path" => "../../etc/passwd"}}]
          }}
        end
      end)

      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: StubTrail
        )

      # Should not crash — path traversal returns error string to LLM
      assert result.spec
    end

    test "broadcasts trail events during tool dispatch", %{session: session, spec_text: spec_text} do
      test_pid = self()

      trail_mod = %{
        broadcast: fn session_id, event ->
          send(test_pid, {:trail, session_id, event})
          :ok
        end
      }

      providers = wrap_fn(stub_providers_with_tools(spec_text))

      {:ok, _result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: trail_mod
        )

      # Should receive spec_started
      sid = session.id
      assert_received {:trail, ^sid, %{type: :spec_started}}

      # Should receive file_read event
      assert_received {:trail, _, %{type: :file_read, path: "db/migrations/001_init.sql"}}

      # Should receive knowledge_search event
      assert_received {:trail, _, %{type: :knowledge_search}}

      # Should receive verification results
      assert_received {:trail, _, %{type: :verification_result}}

      # Should receive spec_complete
      assert_received {:trail, _, %{type: :spec_complete}}
    end

    test "trail events include session_id", %{session: session, spec_text: spec_text} do
      test_pid = self()

      trail_mod = %{
        broadcast: fn session_id, event ->
          send(test_pid, {:trail, session_id, event})
          :ok
        end
      }

      providers = wrap_fn(stub_providers_no_tools(spec_text))

      {:ok, _result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: trail_mod
        )

      sid = session.id
      assert_received {:trail, ^sid, %{type: :spec_started}}
      assert_received {:trail, ^sid, %{type: :spec_complete}}
    end

    test "trail broadcasts do not block on failure", %{session: session, spec_text: spec_text} do
      # Trail module that raises — should not crash spec generation
      trail_mod = %{
        broadcast: fn _sid, _event -> raise "trail broken" end
      }

      providers = wrap_fn(stub_providers_no_tools(spec_text))

      # Should succeed despite trail module raising
      {:ok, result} =
        SpecGenerator.generate(session,
          providers_mod: providers,
          file_system: StubFileSystem,
          knowledge_mod: StubKnowledge,
          trail_mod: trail_mod
        )

      assert result.spec
    end
  end
end
