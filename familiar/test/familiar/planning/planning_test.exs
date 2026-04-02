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
    test "returns not_implemented (stub)" do
      {:error, {:not_implemented, %{}}} = Planning.get_spec(1)
    end
  end
end
