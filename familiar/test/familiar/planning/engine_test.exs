defmodule Familiar.Planning.EngineTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning.Engine
  alias Familiar.Planning.Message
  alias Familiar.Planning.Session
  alias Familiar.Planning.Spec

  defmodule StubLibrarian do
    @moduledoc false
    def query(_text, _opts) do
      {:ok, %{summary: "Project uses Phoenix with SQLite. [lib/repo.ex]", results: [], hops: 1}}
    end
  end

  defmodule StubLibrarianError do
    @moduledoc false
    def query(_text, _opts) do
      {:error, {:search_failed, %{}}}
    end
  end

  defmodule StubProviders do
    @moduledoc false
    def chat(_messages, _opts) do
      {:ok, %{content: "What authentication method would you like to use?", tool_calls: []}}
    end
  end

  defmodule StubProvidersSpecReady do
    @moduledoc false
    def chat(_messages, _opts) do
      {:ok, %{content: "[SPEC_READY] I have enough information to write a spec for user accounts with OAuth2."}}
    end
  end

  defmodule StubProvidersError do
    @moduledoc false
    def chat(_messages, _opts) do
      {:error, {:provider_unavailable, %{}}}
    end
  end

  defp base_opts do
    [
      providers_mod: StubProviders,
      librarian_mod: StubLibrarian
    ]
  end

  describe "start_plan/2" do
    test "creates session and returns first LLM response" do
      {:ok, result} = Engine.start_plan("add user accounts", base_opts())

      assert result.session_id
      assert is_binary(result.response)
      assert result.status == :questioning
    end

    test "persists session with context in database" do
      {:ok, result} = Engine.start_plan("add user accounts", base_opts())

      session = Repo.get!(Session, result.session_id)
      assert session.description == "add user accounts"
      assert session.status == "active"
      assert session.context =~ "Phoenix"
    end

    test "persists initial user message and assistant response" do
      {:ok, result} = Engine.start_plan("add user accounts", base_opts())

      messages =
        from(m in Message, where: m.session_id == ^result.session_id, order_by: [asc: m.inserted_at])
        |> Repo.all()

      assert [user_msg, assistant_msg] = messages
      assert user_msg.role == "user"
      assert user_msg.content == "add user accounts"
      assert assistant_msg.role == "assistant"
      assert assistant_msg.content =~ "authentication"
    end

    test "detects spec_ready status from LLM response" do
      opts = Keyword.put(base_opts(), :providers_mod, StubProvidersSpecReady)
      {:ok, result} = Engine.start_plan("detailed plan with specific files", opts)

      assert result.status == :spec_ready
    end

    test "returns error when LLM fails" do
      opts = Keyword.put(base_opts(), :providers_mod, StubProvidersError)
      {:error, {type, _}} = Engine.start_plan("test", opts)

      assert type == :llm_failed
    end

    test "proceeds even when Librarian fails (graceful degradation)" do
      opts = Keyword.put(base_opts(), :librarian_mod, StubLibrarianError)

      {:ok, result} = Engine.start_plan("test", opts)
      assert result.session_id
    end

    test "applies SecretFilter to persisted messages" do
      {:ok, result} = Engine.start_plan("use key AKIA1234567890ABCDEF", base_opts())

      messages =
        from(m in Message, where: m.session_id == ^result.session_id)
        |> Repo.all()

      user_msg = Enum.find(messages, &(&1.role == "user"))
      refute user_msg.content =~ "AKIA1234567890ABCDEF"
    end

    test "rejects empty description" do
      {:error, {type, _}} = Engine.start_plan("", base_opts())
      assert type == :session_create_failed
    end
  end

  describe "respond/3" do
    test "continues conversation with user response" do
      {:ok, %{session_id: sid}} = Engine.start_plan("add auth", base_opts())

      {:ok, result} = Engine.respond(sid, "OAuth2 with Google", base_opts())

      assert result.session_id == sid
      assert is_binary(result.response)
    end

    test "persists user and assistant messages in correct order" do
      {:ok, %{session_id: sid}} = Engine.start_plan("add auth", base_opts())

      {:ok, _result} = Engine.respond(sid, "OAuth2 with Google", base_opts())

      messages =
        from(m in Message, where: m.session_id == ^sid, order_by: [asc: m.inserted_at])
        |> Repo.all()

      roles = Enum.map(messages, & &1.role)
      # user (description) + assistant (start_plan) + user (respond) + assistant (respond)
      assert roles == ["user", "assistant", "user", "assistant"]
    end

    test "returns error for non-existent session" do
      {:error, {type, _}} = Engine.respond(999_999, "test", base_opts())
      assert type == :session_not_found
    end

    test "returns error for completed session" do
      {:ok, %{session_id: sid}} = Engine.start_plan("test", base_opts())

      Repo.get!(Session, sid)
      |> Session.changeset(%{status: "completed"})
      |> Repo.update!()

      {:error, {type, _}} = Engine.respond(sid, "test", base_opts())
      assert type == :session_not_active
    end
  end

  describe "resume/1" do
    test "loads session state with last response" do
      {:ok, %{session_id: sid}} = Engine.start_plan("add auth", base_opts())

      {:ok, state} = Engine.resume(sid)

      assert state.session_id == sid
      assert state.description == "add auth"
      assert state.status == :active
      assert state.message_count >= 1
      assert is_binary(state.last_response)
    end

    test "returns nil last_response for session with no assistant messages" do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "test"})
        |> Repo.insert()

      {:ok, state} = Engine.resume(session.id)

      assert state.last_response == nil
      assert state.message_count == 0
    end

    test "returns error for non-existent session" do
      {:error, {type, _}} = Engine.resume(999_999)
      assert type == :session_not_found
    end
  end

  describe "latest_active_session/0" do
    test "returns the most recent active session" do
      {:ok, %{session_id: sid1}} = Engine.start_plan("first", base_opts())
      {:ok, %{session_id: sid2}} = Engine.start_plan("second", base_opts())

      {:ok, latest} = Engine.latest_active_session()
      assert latest == sid2
      assert sid2 > sid1
    end

    test "returns error when no active sessions exist" do
      {:error, {type, _}} = Engine.latest_active_session()
      assert type == :no_active_session
    end
  end

  describe "tool_definitions/0" do
    test "returns list of tool definitions" do
      tools = Engine.tool_definitions()
      assert [_ | _] = tools
      assert hd(tools).name == "knowledge_search"
    end
  end

  describe "generate_spec/2" do
    test "generates spec from session" do
      {:ok, %{session_id: sid}} = Engine.start_plan("add auth", base_opts())

      spec_opts = [
        providers_mod: %{chat: fn _msgs, _opts ->
          {:ok, %{content: "# Add Auth\n\n## Assumptions\n\nUses JWT in `lib/auth.ex`\n\n## Implementation Plan\n\n1. Add handler"}}
        end},
        file_system: __MODULE__.StubFileSystem,
        knowledge_mod: __MODULE__.StubKnowledge
      ]

      {:ok, result} = Engine.generate_spec(sid, spec_opts)

      assert result.spec.title == "Add Auth"
      assert result.spec.session_id == sid
    end

    test "returns error for non-existent session" do
      {:error, {type, _}} = Engine.generate_spec(999_999)
      assert type == :session_not_found
    end
  end

  describe "get_spec/1" do
    test "returns spec by ID" do
      {:ok, %{session_id: sid}} = Engine.start_plan("add auth", base_opts())

      spec_opts = [
        providers_mod: %{chat: fn _msgs, _opts ->
          {:ok, %{content: "# Test Spec\n\n## Assumptions\n\nNone\n\n## Implementation Plan\n\n1. Do it"}}
        end},
        file_system: __MODULE__.StubFileSystem,
        knowledge_mod: __MODULE__.StubKnowledge
      ]

      {:ok, %{spec: spec}} = Engine.generate_spec(sid, spec_opts)
      {:ok, fetched} = Engine.get_spec(spec.id)
      assert fetched.id == spec.id
    end

    test "returns error for non-existent spec" do
      {:error, {type, _}} = Engine.get_spec(999_999)
      assert type == :spec_not_found
    end
  end

  describe "approve_spec/2 and reject_spec/2" do
    test "approve_spec returns error for non-existent spec" do
      {:error, {:spec_not_found, _}} = Engine.approve_spec(999_999)
    end

    test "reject_spec returns error for non-existent spec" do
      {:error, {:spec_not_found, _}} = Engine.reject_spec(999_999)
    end

    test "approve_spec updates spec status" do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "test", context: "ctx"})
        |> Repo.insert()

      {:ok, spec} =
        %Spec{}
        |> Spec.changeset(%{
          session_id: session.id,
          title: "Test",
          body: "# Test",
          file_path: ".familiar/specs/test.md"
        })
        |> Repo.insert()

      {:ok, approved} = Engine.approve_spec(spec.id, file_system: __MODULE__.ReviewFS)
      assert approved.status == "approved"
    end

    test "reject_spec updates spec status" do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "test", context: "ctx"})
        |> Repo.insert()

      {:ok, spec} =
        %Spec{}
        |> Spec.changeset(%{
          session_id: session.id,
          title: "Test",
          body: "# Test",
          file_path: ".familiar/specs/test.md"
        })
        |> Repo.insert()

      {:ok, rejected} = Engine.reject_spec(spec.id, file_system: __MODULE__.ReviewFS)
      assert rejected.status == "rejected"
    end
  end

  defmodule ReviewFS do
    @moduledoc false
    def read(_path), do: {:ok, "---\nstatus: draft\n---\n\n# Body"}
    def write(_path, _content), do: :ok
    def stat(_path), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 50}}
  end

  defmodule StubFileSystem do
    @moduledoc false
    def read(_path), do: {:error, {:file_error, %{reason: :enoent}}}
    def write(_path, _content), do: :ok
    def stat(_path), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 50}}
  end

  defmodule StubKnowledge do
    @moduledoc false
    def search(_query), do: {:ok, []}
  end
end
