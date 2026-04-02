defmodule Familiar.PlanningTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning

  defmodule StubLibrarian do
    @moduledoc false
    def query(_text, _opts) do
      {:ok, %{summary: "Test context", results: [], hops: 1}}
    end
  end

  defmodule StubProviders do
    @moduledoc false
    def chat(_messages, _opts) do
      {:ok, %{content: "What do you want?", tool_calls: []}}
    end
  end

  defp opts do
    [providers_mod: StubProviders, librarian_mod: StubLibrarian]
  end

  describe "start_plan/2" do
    test "delegates to Engine.start_plan" do
      {:ok, result} = Planning.start_plan("add auth", opts())
      assert result.session_id
      assert is_binary(result.response)
    end
  end

  describe "respond/3" do
    test "delegates to Engine.respond" do
      {:ok, %{session_id: sid}} = Planning.start_plan("add auth", opts())
      {:ok, result} = Planning.respond(sid, "OAuth2", opts())
      assert result.session_id == sid
    end
  end

  describe "resume/1" do
    test "delegates to Engine.resume" do
      {:ok, %{session_id: sid}} = Planning.start_plan("test", opts())
      {:ok, state} = Planning.resume(sid)
      assert state.session_id == sid
      assert state.status == :active
    end
  end

  describe "latest_active_session/0" do
    test "delegates to Engine.latest_active_session" do
      {:ok, %{session_id: sid}} = Planning.start_plan("test", opts())
      {:ok, latest} = Planning.latest_active_session()
      assert latest == sid
    end
  end

  describe "get_spec/1" do
    test "returns error for non-existent spec" do
      {:error, {:spec_not_found, %{spec_id: 1}}} = Planning.get_spec(1)
    end
  end

  describe "generate_spec/2" do
    test "delegates to Engine.generate_spec" do
      {:ok, %{session_id: sid}} = Planning.start_plan("add auth", opts())

      spec_opts = [
        providers_mod: %{
          chat: fn _msgs, _opts ->
            {:ok, %{content: "# Auth\n\n## Assumptions\n\nNone\n\n## Implementation Plan\n\n1. Do it"}}
          end
        },
        file_system: __MODULE__.StubFS,
        knowledge_mod: __MODULE__.StubKnow
      ]

      {:ok, result} = Planning.generate_spec(sid, spec_opts)
      assert result.spec.title == "Auth"
    end
  end

  defmodule StubFS do
    @moduledoc false
    def read(_), do: {:error, {:file_error, %{reason: :enoent}}}
    def write(_, _), do: :ok
    def stat(_), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 50}}
  end

  defmodule StubKnow do
    @moduledoc false
    def search(_), do: {:ok, []}
  end
end
