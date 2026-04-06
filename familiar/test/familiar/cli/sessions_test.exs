defmodule Familiar.CLI.SessionsTest do
  use Familiar.DataCase, async: false

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Conversations
  alias Familiar.Daemon.Paths

  setup do
    dir = Path.join(System.tmp_dir!(), "sessions_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, ".familiar"))
    Application.put_env(:familiar, :project_dir, dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  defp deps(overrides \\ []) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, Map.new(overrides))
  end

  # == Conversations.list/1 ==

  describe "Conversations.list/1" do
    test "lists all conversations" do
      {:ok, c1} = Conversations.create("first session", scope: "chat")
      {:ok, c2} = Conversations.create("second session", scope: "planning")

      {:ok, result} = Conversations.list()
      ids = Enum.map(result, & &1.id)
      assert c1.id in ids
      assert c2.id in ids
    end

    test "filters by scope" do
      {:ok, _} = Conversations.create("chat session", scope: "chat")
      {:ok, _} = Conversations.create("plan session", scope: "planning")

      {:ok, chat_only} = Conversations.list(scope: "chat")
      assert Enum.all?(chat_only, &(&1.scope == "chat"))
    end

    test "filters by status" do
      {:ok, c1} = Conversations.create("active one", scope: "chat")
      {:ok, c2} = Conversations.create("completed one", scope: "chat")
      Conversations.update_status(c2.id, "completed")

      {:ok, active_only} = Conversations.list(status: "active")
      ids = Enum.map(active_only, & &1.id)
      assert c1.id in ids
      refute c2.id in ids
    end
  end

  # == Conversations.cleanup_stale/1 ==

  describe "Conversations.cleanup_stale/1" do
    test "marks old active conversations as abandoned" do
      {:ok, conv} = Conversations.create("old session", scope: "chat")

      # Manually backdate the conversation
      import Ecto.Query

      from(c in Familiar.Conversations.Conversation,
        where: c.id == ^conv.id
      )
      |> Familiar.Repo.update_all(set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

      {:ok, %{cleaned: count}} = Conversations.cleanup_stale(max_age_hours: 1)
      assert count >= 1

      {:ok, updated} = Conversations.get(conv.id)
      assert updated.status == "abandoned"
    end

    test "does not touch recent active conversations" do
      {:ok, conv} = Conversations.create("fresh session", scope: "chat")

      {:ok, %{cleaned: _}} = Conversations.cleanup_stale(max_age_hours: 24)

      {:ok, still_active} = Conversations.get(conv.id)
      assert still_active.status == "active"
    end
  end

  # == fam sessions CLI ==

  describe "fam sessions" do
    test "lists sessions with DI" do
      d =
        deps(
          list_sessions_fn: fn _opts ->
            {:ok,
             [
               %{
                 id: 1,
                 scope: "chat",
                 status: "active",
                 description: "user-manager: chat",
                 updated_at: ~U[2026-04-06 12:00:00Z]
               },
               %{
                 id: 2,
                 scope: "planning",
                 status: "completed",
                 description: "analyst: plan auth",
                 updated_at: ~U[2026-04-06 11:00:00Z]
               }
             ]}
          end
        )

      Paths.ensure_familiar_dir!()
      assert {:ok, %{sessions: sessions}} = Main.run({"sessions", [], %{}}, d)
      assert length(sessions) == 2
      assert hd(sessions).scope == "chat"
    end

    test "filters by --scope" do
      test_pid = self()

      d =
        deps(
          list_sessions_fn: fn opts ->
            send(test_pid, {:list_called, opts})
            {:ok, []}
          end
        )

      Paths.ensure_familiar_dir!()
      Main.run({"sessions", [], %{scope: "chat"}}, d)
      assert_receive {:list_called, [scope: "chat"]}
    end
  end

  describe "fam sessions <id>" do
    test "shows session detail" do
      d =
        deps(
          get_session_fn: fn 42 ->
            {:ok,
             %{
               id: 42,
               scope: "chat",
               status: "active",
               description: "user-manager: help",
               inserted_at: ~U[2026-04-06 12:00:00Z]
             }}
          end,
          messages_fn: fn 42 ->
            {:ok,
             [
               %{
                 role: "user",
                 content: "Help me refactor",
                 inserted_at: ~U[2026-04-06 12:01:00Z]
               },
               %{
                 role: "assistant",
                 content: "I'll analyze the code.",
                 inserted_at: ~U[2026-04-06 12:02:00Z]
               }
             ]}
          end
        )

      Paths.ensure_familiar_dir!()
      assert {:ok, %{session: detail}} = Main.run({"sessions", ["42"], %{}}, d)
      assert detail.id == 42
      assert detail.message_count == 2
      assert length(detail.recent_messages) == 2
    end

    test "returns error for invalid ID" do
      Paths.ensure_familiar_dir!()
      assert {:error, {:usage_error, _}} = Main.run({"sessions", ["abc"], %{}}, deps())
    end
  end

  describe "fam sessions --cleanup" do
    test "calls cleanup function" do
      d = deps(cleanup_sessions_fn: fn _opts -> {:ok, %{cleaned: 3}} end)

      Paths.ensure_familiar_dir!()
      assert {:ok, %{cleaned: 3}} = Main.run({"sessions", [], %{cleanup: true}}, d)
    end
  end

  # == Output formatting ==

  describe "output formatting" do
    test "quiet mode for sessions list" do
      result = {:ok, %{sessions: [%{}, %{}, %{}]}}
      assert Output.format(result, :quiet) == "sessions:3"
    end

    test "quiet mode for session detail" do
      result = {:ok, %{session: %{id: 42}}}
      assert Output.format(result, :quiet) == "session:42"
    end

    test "quiet mode for cleanup" do
      result = {:ok, %{cleaned: 5}}
      assert Output.format(result, :quiet) == "cleaned:5"
    end

    test "json mode for sessions list" do
      result = {:ok, %{sessions: [%{id: 1, scope: "chat", status: "active"}]}}
      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert [s] = decoded["data"]["sessions"]
      assert s["id"] == 1
    end
  end
end
