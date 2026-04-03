defmodule Familiar.ExtensionTest do
  use ExUnit.Case, async: true

  alias Familiar.Extension

  defmodule GoodExtension do
    @behaviour Extension

    @impl true
    def name, do: "good-ext"

    @impl true
    def tools, do: [{:my_tool, &__MODULE__.my_tool/2, "A test tool"}]

    @impl true
    def hooks do
      [
        %{hook: :before_tool_call, handler: &__MODULE__.before_tool/2, priority: 50, type: :alter}
      ]
    end

    @impl true
    def init(_opts), do: :ok

    def my_tool(_args, _ctx), do: {:ok, %{}}
    def before_tool(payload, _ctx), do: {:ok, payload}
  end

  defmodule ExtensionWithChildSpec do
    @behaviour Extension

    @impl true
    def name, do: "with-child"

    @impl true
    def tools, do: []

    @impl true
    def hooks, do: []

    @impl true
    def child_spec(_opts), do: %{id: __MODULE__, start: {Agent, :start_link, [fn -> %{} end]}}

    @impl true
    def init(_opts), do: :ok
  end

  defmodule MinimalExtension do
    @behaviour Extension

    @impl true
    def name, do: "minimal"

    @impl true
    def tools, do: []

    @impl true
    def hooks, do: []

    @impl true
    def init(_opts), do: :ok
  end

  describe "Extension behaviour" do
    test "module implementing all callbacks compiles and returns expected values" do
      assert GoodExtension.name() == "good-ext"
      assert [{:my_tool, fun, "A test tool"}] = GoodExtension.tools()
      assert is_function(fun, 2)

      assert [%{hook: :before_tool_call, type: :alter, priority: 50}] = GoodExtension.hooks()
      assert GoodExtension.init([]) == :ok
    end

    test "minimal extension without child_spec compiles" do
      assert MinimalExtension.name() == "minimal"
      assert MinimalExtension.tools() == []
      assert MinimalExtension.hooks() == []
      assert MinimalExtension.init([]) == :ok
    end

    test "extension with child_spec returns a valid spec" do
      spec = ExtensionWithChildSpec.child_spec([])
      assert %{id: _, start: {Agent, :start_link, _}} = spec
    end
  end
end
