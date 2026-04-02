defmodule Familiar.Planning.MessageTest do
  use Familiar.DataCase, async: true

  alias Familiar.Planning.Message
  alias Familiar.Planning.Session

  setup do
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{description: "test session"})
      |> Repo.insert()

    %{session: session}
  end

  describe "changeset/2" do
    test "valid attrs create a valid changeset", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "user",
          content: "add user accounts"
        })

      assert changeset.valid?
    end

    test "requires session_id, role, and content" do
      changeset = Message.changeset(%Message{}, %{})
      refute changeset.valid?
      assert %{session_id: ["can't be blank"], role: ["can't be blank"], content: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates role inclusion", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "invalid",
          content: "test"
        })

      refute changeset.valid?
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid roles", %{session: session} do
      for role <- Message.valid_roles() do
        changeset =
          Message.changeset(%Message{}, %{
            session_id: session.id,
            role: role,
            content: "test"
          })

        assert changeset.valid?, "expected #{role} to be valid"
      end
    end

    test "defaults tool_calls to empty array", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "user",
          content: "test"
        })

      assert get_field(changeset, :tool_calls) == "[]"
    end

    test "validates tool_calls is valid JSON array", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "user",
          content: "test",
          tool_calls: "not json"
        })

      refute changeset.valid?
      assert %{tool_calls: ["must be valid JSON"]} = errors_on(changeset)
    end

    test "rejects tool_calls that is JSON object instead of array", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "user",
          content: "test",
          tool_calls: ~s({"key": "value"})
        })

      refute changeset.valid?
      assert %{tool_calls: ["must be a JSON array"]} = errors_on(changeset)
    end

    test "accepts valid JSON array for tool_calls", %{session: session} do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: session.id,
          role: "user",
          content: "test",
          tool_calls: ~s([{"name": "search", "args": {}}])
        })

      assert changeset.valid?
    end
  end

  describe "persistence" do
    test "inserts and retrieves a message", %{session: session} do
      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "add user accounts"
        })
        |> Repo.insert()

      assert message.id
      assert message.session_id == session.id
      assert message.role == "user"
      assert message.content == "add user accounts"
      assert message.inserted_at
    end

    test "enforces foreign key constraint" do
      changeset =
        Message.changeset(%Message{}, %{
          session_id: 999_999,
          role: "user",
          content: "test"
        })

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "cascade deletes messages when session is deleted", %{session: session} do
      {:ok, _message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: "user",
          content: "test"
        })
        |> Repo.insert()

      Repo.delete!(session)
      assert [] == Repo.all(Message)
    end
  end
end
