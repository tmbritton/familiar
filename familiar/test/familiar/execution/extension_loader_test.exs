defmodule Familiar.Execution.ExtensionLoaderTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Familiar.Execution.ExtensionLoader
  alias Familiar.Hooks

  setup do
    name = :"hooks_#{System.unique_integer([:positive])}"
    start_supervised!({Hooks, name: name})
    {:ok, hooks_name: name}
  end

  defmodule SuccessExtension do
    @behaviour Familiar.Extension

    @impl true
    def name, do: "success-ext"

    @impl true
    def tools, do: [{:test_tool, &__MODULE__.test_tool/2, "A test tool"}]

    @impl true
    def hooks do
      [
        %{
          hook: :before_tool_call,
          handler: &__MODULE__.before_tool/2,
          priority: 50,
          type: :alter
        }
      ]
    end

    @impl true
    def init(_opts), do: :ok

    def test_tool(_args, _ctx), do: {:ok, %{}}
    def before_tool(payload, _ctx), do: {:ok, payload}
  end

  defmodule FailingExtension do
    @behaviour Familiar.Extension

    @impl true
    def name, do: "failing-ext"

    @impl true
    def tools, do: []

    @impl true
    def hooks, do: []

    @impl true
    def init(_opts), do: {:error, "init failed on purpose"}
  end

  defmodule CrashingExtension do
    @behaviour Familiar.Extension

    @impl true
    def name, do: "crashing-ext"

    @impl true
    def tools, do: []

    @impl true
    def hooks, do: []

    @impl true
    def init(_opts), do: raise("init crash")
  end

  defmodule EventExtension do
    @behaviour Familiar.Extension

    @impl true
    def name, do: "event-ext"

    @impl true
    def tools, do: []

    @impl true
    def hooks do
      [
        %{
          hook: :on_agent_complete,
          handler: &__MODULE__.on_complete/1,
          priority: 100,
          type: :event
        }
      ]
    end

    @impl true
    def init(_opts), do: :ok

    def on_complete(_payload), do: :ok
  end

  describe "load_extensions/2" do
    test "loads successful extensions and collects registrations" do
      assert {:ok, result} = ExtensionLoader.load_extensions([SuccessExtension])

      assert result.loaded == ["success-ext"]
      assert result.failed == []
      assert [{:test_tool, fun, "A test tool"}] = result.tools
      assert is_function(fun, 2)
      assert result.child_specs == []
    end

    test "skips extensions that fail init and logs warning" do
      log =
        capture_log(fn ->
          assert {:ok, result} =
                   ExtensionLoader.load_extensions([SuccessExtension, FailingExtension])

          assert result.loaded == ["success-ext"]
          assert [{FailingExtension, {:init_failed, "init failed on purpose"}}] = result.failed
        end)

      assert log =~ "FailingExtension"
      assert log =~ "init_failed"
    end

    test "skips extensions that crash during init" do
      log =
        capture_log(fn ->
          assert {:ok, result} = ExtensionLoader.load_extensions([CrashingExtension])

          assert result.loaded == []
          assert [{CrashingExtension, {:init_crashed, _}}] = result.failed
        end)

      assert log =~ "CrashingExtension"
    end

    test "loads multiple extensions in order" do
      assert {:ok, result} =
               ExtensionLoader.load_extensions([SuccessExtension, EventExtension])

      assert result.loaded == ["success-ext", "event-ext"]
      assert result.failed == []
    end

    test "returns empty collections when no extensions configured" do
      assert {:ok, result} = ExtensionLoader.load_extensions([])

      assert result.loaded == []
      assert result.failed == []
      assert result.tools == []
      assert result.child_specs == []
    end

    test "loads extensions with event hooks" do
      assert {:ok, result} = ExtensionLoader.load_extensions([EventExtension])
      assert result.loaded == ["event-ext"]
    end

    test "rejects modules missing required callbacks" do
      defmodule NotAnExtension do
        def name, do: "not-ext"
        # Missing tools/0, hooks/0, init/1
      end

      log =
        capture_log(fn ->
          assert {:ok, result} = ExtensionLoader.load_extensions([NotAnExtension])
          assert result.loaded == []
          assert [{NotAnExtension, {:missing_callbacks, reason}}] = result.failed
          assert reason =~ "tools"
          assert reason =~ "hooks"
          assert reason =~ "init"
        end)

      assert log =~ "missing_callbacks"
    end

    test "collects child_specs from extensions that provide them" do
      defmodule WithChildExt do
        @behaviour Familiar.Extension

        @impl true
        def name, do: "child-ext"
        @impl true
        def tools, do: []
        @impl true
        def hooks, do: []
        @impl true
        def child_spec(_opts),
          do: %{id: :test_child, start: {Agent, :start_link, [fn -> :ok end]}}

        @impl true
        def init(_opts), do: :ok
      end

      assert {:ok, result} = ExtensionLoader.load_extensions([WithChildExt])
      assert result.loaded == ["child-ext"]
      assert [%{id: :test_child}] = result.child_specs
    end
  end
end
