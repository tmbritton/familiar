defmodule Familiar.MCP.DispatcherTest do
  use ExUnit.Case, async: true

  alias Familiar.MCP.Dispatcher
  alias Familiar.MCP.Protocol

  defp test_dispatcher do
    Dispatcher.new(%{
      "tools/list" => fn _params, _ctx -> {:ok, %{"tools" => []}} end,
      "tools/call" => fn params, _ctx -> {:ok, %{"result" => params["name"]}} end,
      "echo" => fn params, _ctx -> {:ok, params} end
    })
  end

  describe "new/1" do
    test "creates a dispatcher from a handlers map" do
      d = Dispatcher.new(%{"test" => fn _, _ -> {:ok, nil} end})
      assert %Dispatcher{} = d
    end

    test "creates a dispatcher from an empty map" do
      d = Dispatcher.new(%{})
      assert %Dispatcher{handlers: handlers} = d
      assert handlers == %{}
    end
  end

  describe "dispatch/4" do
    test "dispatches to matching handler" do
      d = test_dispatcher()
      assert {:ok, %{"tools" => []}} = Dispatcher.dispatch(d, "tools/list", %{}, %{})
    end

    test "passes params and context to handler" do
      d =
        Dispatcher.new(%{
          "test" => fn params, ctx -> {:ok, %{"p" => params["key"], "c" => ctx[:agent]}} end
        })

      assert {:ok, %{"p" => "val", "c" => "coder"}} =
               Dispatcher.dispatch(d, "test", %{"key" => "val"}, %{agent: "coder"})
    end

    test "returns method_not_found for unregistered method" do
      d = test_dispatcher()

      assert {:error, code, message} = Dispatcher.dispatch(d, "unknown/method", %{}, %{})
      assert code == Protocol.error_code(:method_not_found)
      assert message =~ "Method not found: unknown/method"
    end

    test "returns handler error tuple as-is" do
      d =
        Dispatcher.new(%{
          "fail" => fn _params, _ctx -> {:error, -32_602, "Invalid params"} end
        })

      assert {:error, -32_602, "Invalid params"} = Dispatcher.dispatch(d, "fail", %{}, %{})
    end

    test "catches handler exceptions and returns internal error" do
      d =
        Dispatcher.new(%{
          "boom" => fn _params, _ctx -> raise "kaboom" end
        })

      assert {:error, code, message} = Dispatcher.dispatch(d, "boom", %{}, %{})
      assert code == Protocol.error_code(:internal_error)
      assert message =~ "Internal error: kaboom"
    end

    test "dispatches with empty params" do
      d = test_dispatcher()
      assert {:ok, %{}} = Dispatcher.dispatch(d, "echo", %{}, %{})
    end

    test "catches handler exits and returns internal error" do
      d =
        Dispatcher.new(%{
          "exit" => fn _params, _ctx -> exit(:shutdown) end
        })

      assert {:error, code, message} = Dispatcher.dispatch(d, "exit", %{}, %{})
      assert code == Protocol.error_code(:internal_error)
      assert message =~ "Internal error: exit"
    end
  end

  describe "new/1 validation" do
    test "raises ArgumentError for handler with wrong arity" do
      assert_raise ArgumentError, ~r/must be an arity-2 function/, fn ->
        Dispatcher.new(%{"bad" => fn x -> x end})
      end
    end

    test "raises ArgumentError for non-function handler" do
      assert_raise ArgumentError, ~r/must be an arity-2 function/, fn ->
        Dispatcher.new(%{"bad" => "not a function"})
      end
    end
  end
end
