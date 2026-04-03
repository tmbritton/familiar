defmodule FamiliarWeb.PlanningChannelTest do
  use FamiliarWeb.ChannelCase, async: false

  alias Familiar.Planning.Session
  alias Familiar.Repo

  defmodule StubLibrarian do
    @moduledoc false
    def query(_text, _opts) do
      {:ok, %{summary: "Test context [lib/repo.ex]", results: [], hops: 1}}
    end
  end

  defmodule StubProviders do
    @moduledoc false
    def chat(_messages, _opts) do
      {:ok, %{content: "What authentication method?", tool_calls: []}}
    end
  end

  setup do
    # Configure DI overrides for the channel's Engine calls
    Application.put_env(:familiar, :planning_engine_opts, [
      providers_mod: StubProviders,
      librarian_mod: StubLibrarian
    ])

    on_exit(fn -> Application.delete_env(:familiar, :planning_engine_opts) end)

    {:ok, socket} = connect(FamiliarWeb.UserSocket, %{})
    {:ok, _, socket} = subscribe_and_join(socket, "planning:lobby", %{})

    %{socket: socket}
  end

  describe "start_plan" do
    test "starts a planning session and returns response", %{socket: socket} do
      ref = push(socket, "start_plan", %{"description" => "add user auth"})
      assert_reply ref, :ok, payload
      assert payload.session_id
      assert is_binary(payload.response)
      assert payload.status in ["questioning", "spec_ready"]
    end
  end

  describe "respond" do
    test "continues conversation with user response", %{socket: socket} do
      # Start a session first
      ref = push(socket, "start_plan", %{"description" => "add auth"})
      assert_reply ref, :ok, %{session_id: sid}

      ref = push(socket, "respond", %{"session_id" => sid, "message" => "OAuth2"})
      assert_reply ref, :ok, payload
      assert payload.session_id == sid
      assert is_binary(payload.response)
    end

    test "returns error for non-existent session", %{socket: socket} do
      ref = push(socket, "respond", %{"session_id" => 999_999, "message" => "test"})
      assert_reply ref, :error, payload
      assert payload.type == "session_not_found"
    end

    test "returns error for completed session", %{socket: socket} do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "test", status: "completed"})
        |> Repo.insert()

      ref = push(socket, "respond", %{"session_id" => session.id, "message" => "test"})
      assert_reply ref, :error, payload
      assert payload.type == "session_not_active"
    end
  end

  describe "resume" do
    test "returns error when no active sessions exist", %{socket: socket} do
      ref = push(socket, "resume", %{})
      assert_reply ref, :error, payload
      assert payload.type == "no_active_session"
    end

    test "returns error for non-existent session", %{socket: socket} do
      ref = push(socket, "resume", %{"session_id" => 999_999})
      assert_reply ref, :error, payload
      assert payload.type == "session_not_found"
    end

    test "resumes existing session", %{socket: socket} do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "test plan"})
        |> Repo.insert()

      ref = push(socket, "resume", %{"session_id" => session.id})
      assert_reply ref, :ok, payload
      assert payload.session_id == session.id
      assert payload.description == "test plan"
    end

    test "resumes latest active session when no session_id given", %{socket: socket} do
      # Start a session via the engine
      ref = push(socket, "start_plan", %{"description" => "my feature"})
      assert_reply ref, :ok, %{session_id: sid}

      ref = push(socket, "resume", %{})
      assert_reply ref, :ok, payload
      assert payload.session_id == sid
    end
  end

  describe "trail events" do
    test "pushes trail events to socket", %{socket: socket} do
      alias Familiar.Planning.Trail.Event

      # The channel process subscribes to trail topic when generate_spec is called.
      # We can simulate by sending trail events directly to the channel process.
      event = %Event{type: :file_read, path: "lib/auth.ex", timestamp: DateTime.utc_now()}

      # Send the trail event message directly to the channel process
      send(socket.channel_pid, {:trail_event, event})

      assert_push "trail:event", payload
      assert payload.type == "file_read"
      assert payload.text =~ "Reading lib/auth.ex"
    end

    test "pushes verification trail events", %{socket: socket} do
      alias Familiar.Planning.Trail.Event

      event = %Event{
        type: :verification_result,
        result: "verified: users table schema",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:trail_event, event})

      assert_push "trail:event", payload
      assert payload.type == "verification_result"
      assert payload.text =~ "✓ Verified"
    end

    test "pushes spec lifecycle trail events", %{socket: socket} do
      alias Familiar.Planning.Trail.Event

      event = %Event{type: :spec_started, timestamp: DateTime.utc_now()}
      send(socket.channel_pid, {:trail_event, event})

      assert_push "trail:event", payload
      assert payload.type == "spec_started"
      assert payload.text == "Generating spec..."
    end
  end
end
