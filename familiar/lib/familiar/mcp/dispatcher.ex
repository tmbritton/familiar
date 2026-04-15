defmodule Familiar.MCP.Dispatcher do
  @moduledoc """
  Method-to-handler routing for MCP JSON-RPC methods.

  Creates a dispatcher from a map of method names to handler functions,
  then routes incoming calls to the matching handler. Pure module — no
  GenServer, no IO.

  ## Example

      handlers = %{
        "tools/list" => fn _params, _ctx -> {:ok, %{"tools" => []}} end,
        "tools/call" => fn params, ctx -> MyTools.call(params, ctx) end
      }

      dispatcher = Dispatcher.new(handlers)
      {:ok, result} = Dispatcher.dispatch(dispatcher, "tools/list", %{}, %{})
  """

  alias Familiar.MCP.Protocol

  @type handler :: (map(), map() -> {:ok, term()} | {:error, integer(), String.t()})
  @type t :: %__MODULE__{handlers: %{String.t() => handler()}}

  @enforce_keys [:handlers]
  defstruct [:handlers]

  @doc "Creates a new dispatcher from a map of method names to handler functions."
  @spec new(%{String.t() => handler()}) :: t()
  def new(handlers) when is_map(handlers) do
    Enum.each(handlers, fn {method, handler} ->
      unless is_function(handler, 2) do
        raise ArgumentError,
              "handler for #{inspect(method)} must be an arity-2 function, got: #{inspect(handler)}"
      end
    end)

    %__MODULE__{handlers: handlers}
  end

  @doc """
  Dispatches a method call to the matching handler.

  Returns `{:ok, result}` on success, `{:error, code, message}` on failure.
  If no handler matches, returns `{:error, -32601, "Method not found: <method>"}`.
  If the handler raises, returns `{:error, -32603, "Internal error: <message>"}`.
  """
  @spec dispatch(t(), String.t(), map(), map()) ::
          {:ok, term()} | {:error, integer(), String.t()}
  def dispatch(%__MODULE__{handlers: handlers}, method, params, context) do
    case Map.fetch(handlers, method) do
      {:ok, handler} when is_function(handler, 2) ->
        try do
          handler.(params, context)
        rescue
          e ->
            {:error, Protocol.error_code(:internal_error),
             "Internal error: #{Exception.message(e)}"}
        catch
          :exit, reason ->
            {:error, Protocol.error_code(:internal_error),
             "Internal error: exit #{inspect(reason)}"}
        end

      :error ->
        {:error, Protocol.error_code(:method_not_found), "Method not found: #{method}"}
    end
  end
end
