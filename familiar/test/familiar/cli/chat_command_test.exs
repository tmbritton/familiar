defmodule Familiar.CLI.ChatCommandTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  defp chat_deps(overrides \\ []) do
    %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end,
      chat_fn:
        Keyword.get(overrides, :chat_fn, fn _role, _context, _deps ->
          {:ok, %{chat: "ended", status: "user_exit"}}
        end)
    }
    |> Map.merge(
      overrides
      |> Keyword.drop([:chat_fn])
      |> Map.new()
    )
  end

  # == parse_args ==

  describe "parse_args/1" do
    test "no args defaults to chat command" do
      assert {"chat", [], %{}} = Main.parse_args([])
    end

    test "explicit chat command" do
      assert {"chat", [], %{}} = Main.parse_args(["chat"])
    end

    test "chat with --role flag" do
      assert {"chat", [], %{role: "analyst"}} = Main.parse_args(["chat", "--role", "analyst"])
    end

    test "chat with -r alias" do
      assert {"chat", [], %{role: "coder"}} = Main.parse_args(["chat", "-r", "coder"])
    end

    test "chat with --json flag" do
      assert {"chat", [], %{json: true}} = Main.parse_args(["chat", "--json"])
    end

    test "chat with --resume flag" do
      assert {"chat", [], %{resume: true}} = Main.parse_args(["chat", "--resume"])
    end

    test "--help still shows help, not chat" do
      assert {"help", [], _} = Main.parse_args(["--help"])
    end

    test "bare fam with --json goes to chat with json" do
      assert {"chat", [], %{json: true}} = Main.parse_args(["--json"])
    end
  end

  # == chat command dispatch ==

  describe "chat command" do
    test "dispatches to chat_fn with default role" do
      test_pid = self()

      deps =
        chat_deps(
          chat_fn: fn role, _context, _deps ->
            send(test_pid, {:chat_called, role})
            {:ok, %{chat: "ended", status: "user_exit"}}
          end
        )

      assert {:ok, %{chat: "ended"}} = Main.run({"chat", [], %{}}, deps)
      assert_receive {:chat_called, "user-manager"}
    end

    test "--role overrides default role" do
      test_pid = self()

      deps =
        chat_deps(
          chat_fn: fn role, _context, _deps ->
            send(test_pid, {:chat_called, role})
            {:ok, %{chat: "ended", status: "agent_complete"}}
          end
        )

      assert {:ok, _} = Main.run({"chat", [], %{role: "analyst"}}, deps)
      assert_receive {:chat_called, "analyst"}
    end

    test "bare fam (no command) dispatches to chat" do
      test_pid = self()

      deps =
        chat_deps(
          chat_fn: fn role, _context, _deps ->
            send(test_pid, {:chat_called, role})
            {:ok, %{chat: "ended", status: "user_exit"}}
          end
        )

      assert {:ok, _} = Main.run({"chat", [], %{}}, deps)
      assert_receive {:chat_called, "user-manager"}
    end
  end

  # == resume ==

  describe "chat --resume" do
    test "calls find_conversation_fn for latest chat session" do
      test_pid = self()

      deps =
        chat_deps(
          find_conversation_fn: fn session_id ->
            send(test_pid, {:find_called, session_id})
            {:error, {:no_active_conversation, %{}}}
          end
        )

      assert {:error, {:no_active_conversation, _}} =
               Main.run({"chat", [], %{resume: true}}, deps)

      assert_receive {:find_called, nil}
    end

    test "returns error for completed session" do
      deps =
        chat_deps(
          find_conversation_fn: fn _id ->
            {:ok, %{id: 5, status: "completed"}}
          end
        )

      assert {:error, {:conversation_completed, _}} =
               Main.run({"chat", [], %{resume: true}}, deps)
    end

    test "resumes active session with context" do
      test_pid = self()

      deps =
        chat_deps(
          find_conversation_fn: fn _id ->
            {:ok, %{id: 7, status: "active", description: "user-manager: chat"}}
          end,
          messages_fn: fn 7 ->
            {:ok,
             [
               %{role: "user", content: "Help me refactor"},
               %{role: "assistant", content: "I'll analyze the code."}
             ]}
          end,
          chat_fn: fn role, context, _deps ->
            send(test_pid, {:resume_called, role, context})
            {:ok, %{chat: "ended", status: "user_exit"}}
          end
        )

      assert {:ok, _} = Main.run({"chat", [], %{resume: true}}, deps)

      assert_receive {:resume_called, "user-manager", context}
      assert context.session_id == 7
      assert is_binary(context.resume_context)
    end
  end

  describe "chat --session" do
    test "calls find_conversation_fn with specific ID" do
      test_pid = self()

      deps =
        chat_deps(
          find_conversation_fn: fn session_id ->
            send(test_pid, {:find_called, session_id})
            {:error, {:conversation_not_found, %{id: session_id}}}
          end
        )

      assert {:error, {:conversation_not_found, _}} =
               Main.run({"chat", [], %{session: 99}}, deps)

      assert_receive {:find_called, 99}
    end
  end

  # == output formatting ==

  describe "output formatting" do
    test "text mode formats chat end" do
      result = {:ok, %{chat: "ended", status: "user_exit"}}
      output = Output.format(result, :text, nil)
      assert output =~ "chat"
    end

    test "json mode returns chat result" do
      result = {:ok, %{chat: "ended", status: "agent_complete"}}
      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["data"]["chat"] == "ended"
      assert decoded["data"]["status"] == "agent_complete"
    end

    test "quiet mode returns chat status" do
      result = {:ok, %{chat: "ended", status: "user_exit"}}
      output = Output.format(result, :quiet)
      assert output == "chat:user_exit"
    end
  end
end
