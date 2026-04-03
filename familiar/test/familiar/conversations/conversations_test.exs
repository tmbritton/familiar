defmodule Familiar.ConversationsTest do
  use Familiar.DataCase, async: false

  alias Familiar.Conversations
  alias Familiar.Conversations.{Conversation, Message}

  describe "create/2" do
    test "creates a conversation with description" do
      {:ok, conv} = Conversations.create("add user auth")
      assert conv.description == "add user auth"
      assert conv.status == "active"
      assert conv.scope == "default"
    end

    test "creates a conversation with context and scope" do
      {:ok, conv} = Conversations.create("fix bug", context: "some context", scope: "planning")
      assert conv.context == "some context"
      assert conv.scope == "planning"
    end

    test "fails without description" do
      {:error, {:conversation_create_failed, _}} = Conversations.create("")
    end
  end

  describe "get/1" do
    test "fetches existing conversation" do
      {:ok, conv} = Conversations.create("test")
      {:ok, fetched} = Conversations.get(conv.id)
      assert fetched.id == conv.id
    end

    test "returns error for non-existent conversation" do
      {:error, {:conversation_not_found, %{id: 999}}} = Conversations.get(999)
    end
  end

  describe "latest_active/1" do
    test "finds an active conversation" do
      {:ok, conv} = Conversations.create("test conversation")
      {:ok, id} = Conversations.latest_active()
      assert id == conv.id
    end

    test "filters by scope" do
      {:ok, _planning} = Conversations.create("plan", scope: "planning")
      {:ok, fix} = Conversations.create("fix", scope: "fix")
      {:ok, id} = Conversations.latest_active(scope: "fix")
      assert id == fix.id
    end

    test "returns error when no active conversations" do
      {:error, {:no_active_conversation, %{}}} = Conversations.latest_active()
    end

    test "ignores completed conversations" do
      {:ok, conv} = Conversations.create("done")
      Conversations.update_status(conv.id, "completed")
      {:error, {:no_active_conversation, %{}}} = Conversations.latest_active()
    end
  end

  describe "add_message/4" do
    test "adds a message to a conversation" do
      {:ok, conv} = Conversations.create("test")
      {:ok, msg} = Conversations.add_message(conv.id, "user", "hello")
      assert msg.role == "user"
      assert msg.content == "hello"
      assert msg.conversation_id == conv.id
    end

    test "supports tool role" do
      {:ok, conv} = Conversations.create("test")
      {:ok, msg} = Conversations.add_message(conv.id, "tool", "result data")
      assert msg.role == "tool"
    end

    test "supports tool_calls" do
      {:ok, conv} = Conversations.create("test")
      {:ok, msg} = Conversations.add_message(conv.id, "assistant", "thinking...", tool_calls: ~s([{"name":"read_file"}]))
      assert msg.tool_calls =~ "read_file"
    end
  end

  describe "messages/1" do
    test "returns messages in insertion order" do
      {:ok, conv} = Conversations.create("test")
      {:ok, _m1} = Conversations.add_message(conv.id, "user", "first")
      {:ok, _m2} = Conversations.add_message(conv.id, "assistant", "second")
      {:ok, _m3} = Conversations.add_message(conv.id, "user", "third")

      {:ok, msgs} = Conversations.messages(conv.id)
      assert length(msgs) == 3
      assert Enum.map(msgs, & &1.content) == ["first", "second", "third"]
    end

    test "returns empty list for conversation with no messages" do
      {:ok, conv} = Conversations.create("empty")
      {:ok, msgs} = Conversations.messages(conv.id)
      assert msgs == []
    end
  end

  describe "update_status/2" do
    test "updates conversation status" do
      {:ok, conv} = Conversations.create("test")
      {:ok, updated} = Conversations.update_status(conv.id, "completed")
      assert updated.status == "completed"
    end

    test "returns error for invalid status" do
      {:ok, conv} = Conversations.create("test")
      {:error, {:status_update_failed, _}} = Conversations.update_status(conv.id, "invalid")
    end
  end

  describe "Conversation schema" do
    test "valid statuses" do
      assert Conversation.valid_statuses() == ~w(active completed abandoned)
    end
  end

  describe "Message schema" do
    test "valid roles include tool" do
      assert "tool" in Message.valid_roles()
    end

    test "validates tool_calls is JSON array" do
      {:ok, conv} = Conversations.create("test")
      {:error, _} = Conversations.add_message(conv.id, "assistant", "test", tool_calls: "not json")
    end
  end
end
